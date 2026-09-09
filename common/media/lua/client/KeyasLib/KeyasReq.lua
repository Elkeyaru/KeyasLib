-- KeyasReq.lua
--
-- Small helpers for gating content behind player state. Every check
-- returns (boolean, humanReadableReason) so a consumer can both branch on
-- the result and show the player why something is locked.
--
-- Reads KeyasLib.* only from inside function bodies, per the shared-state
-- rule documented in KeyasLib.lua.

KeyasReq = KeyasReq or {}

local function dprint(...)
    if KeyasLib and KeyasLib.debugPrint then
        KeyasLib.debugPrint(...)
    end
end

--- @param player IsoPlayer
--- @param perk Perks a perk constant, e.g. Perks.Lockpicking
--- @param level number required level
--- @return boolean, string|nil
function KeyasReq.skillAtLeast(player, perk, level)
    if not player or not perk or not level then
        return false, "Requisito mal formado (falta player, perk o level)."
    end
    -- Perk lookups are wrapped since perk identifiers/levels are exactly
    -- the kind of engine surface that can shift between game versions.
    local ok, current = pcall(player.getPerkLevel, player, perk)
    if not ok or type(current) ~= "number" then
        dprint("KeyasReq.skillAtLeast: getPerkLevel failed")
        return false, "No se pudo comprobar esa habilidad."
    end
    if current >= level then
        return true, nil
    end
    local okName, name = pcall(perk.getName, perk)
    local label = (okName and name) or "esa habilidad"
    return false, "Necesitas nivel " .. tostring(level) .. " en " .. tostring(label) .. " (tienes " .. tostring(current) .. ")."
end

--- Reads a boolean out of the player's ModData under a prefix the CALLING
--- mod controls (not KeyasLib's own MODDATA_PREFIX - that one is reserved
--- for KeyasLib's own bookkeeping, see KeyasLib.lua).
--- @param player IsoPlayer
--- @param key string
--- @param prefix string the consumer mod's own ModData prefix
--- @return boolean, string|nil
function KeyasReq.flag(player, key, prefix)
    if not player or not key or not prefix then
        return false, "Requisito mal formado (falta player, key o prefix)."
    end
    local ok, modData = pcall(player.getModData, player)
    if not ok or not modData then
        return false, "No se pudo leer el estado del jugador."
    end
    if modData[prefix .. key] then
        return true, nil
    end
    return false, "Todavia no se cumple '" .. tostring(key) .. "'."
end

--============================================================
-- regionScoutedAndReturned: "go look at the city, then come back to base"
--============================================================

-- cityId -> { cityBbox = {minX,maxX,minY,maxY}, baseBbox = {...}, modDataPrefix = "..." }
local regions = {}

--- Registers the bboxes for a region check. Call this once (e.g. from
--- your mod's init file) before calling regionScoutedAndReturned for the
--- same cityId.
--- @param def table { cityBbox, baseBbox, modDataPrefix }
function KeyasReq.defineRegion(cityId, def)
    if not cityId or not def or not def.cityBbox or not def.baseBbox or not def.modDataPrefix then
        print("[KeyasReq] ERROR: defineRegion(cityId, def) needs cityId, def.cityBbox, def.baseBbox and def.modDataPrefix")
        return false
    end
    regions[cityId] = def
    return true
end

local function pointInBbox(x, y, bbox)
    return x >= bbox.minX and x <= bbox.maxX and y >= bbox.minY and y <= bbox.maxY
end

--- Checks (and updates) the "scouted the city, then returned to base"
--- requirement for a player. This both READS and WRITES persistent
--- ModData: call it periodically (e.g. from Events.OnPlayerUpdate, or
--- whenever you'd poll requirements anyway) so position transitions
--- actually get recorded. A single call still returns a correct answer
--- for whatever has been recorded so far - it just won't detect a
--- transition that happens between calls.
--- Idempotent: once "returned" is recorded, it's returned true forever,
--- position is not re-checked.
--- @param player IsoPlayer
--- @param cityId string a key previously passed to defineRegion()
--- @return boolean, string|nil
function KeyasReq.regionScoutedAndReturned(player, cityId)
    local region = regions[cityId]
    if not region then
        return false, "Region '" .. tostring(cityId) .. "' no definida (llama a KeyasReq.defineRegion primero)."
    end
    local ok, modData = pcall(player.getModData, player)
    if not ok or not modData then
        return false, "No se pudo leer el estado del jugador."
    end

    local visitedKey = region.modDataPrefix .. "visited_" .. cityId
    local returnedKey = region.modDataPrefix .. "returned_" .. cityId

    if modData[returnedKey] then
        return true, nil
    end

    local okX, x = pcall(player.getX, player)
    local okY, y = pcall(player.getY, player)
    if okX and okY then
        if not modData[visitedKey] and pointInBbox(x, y, region.cityBbox) then
            modData[visitedKey] = true
            dprint("KeyasReq: entered city bbox for region", cityId)
        end
        if modData[visitedKey] and pointInBbox(x, y, region.baseBbox) then
            modData[returnedKey] = true
            dprint("KeyasReq: returned to base for region", cityId)
        end
    end

    if modData[returnedKey] then
        return true, nil
    elseif modData[visitedKey] then
        return false, "Explorado - falta volver a la base."
    else
        return false, "Todavia no has explorado la zona."
    end
end

--============================================================
-- Combinators
--
-- Take an array of zero-arg functions (so each check is only evaluated if
-- actually needed) each returning (boolean, reason). Usage:
--
--   local ok, reason = KeyasReq.all({
--       function() return KeyasReq.skillAtLeast(player, Perks.Lockpicking, 3) end,
--       function() return KeyasReq.flag(player, "hasKeycard", "MyMod_") end,
--   })
--============================================================

--- Short-circuits on the first failing check and returns its reason.
function KeyasReq.all(checks)
    for _, check in ipairs(checks) do
        local ok, reason = check()
        if not ok then return false, reason end
    end
    return true, nil
end

--- Short-circuits on the first passing check. If none pass, returns the
--- last non-nil reason seen (so the player gets at least one hint).
function KeyasReq.any(checks)
    local lastReason = "Ningun requisito se cumple."
    for _, check in ipairs(checks) do
        local ok, reason = check()
        if ok then return true, nil end
        if reason then lastReason = reason end
    end
    return false, lastReason
end

return KeyasReq
