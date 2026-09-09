-- KeyasZones.lua
--
-- Extracted from LastPurpose's LP_BankSecurity.lua and generalised. Lets a
-- consumer mod seal an area's doors/windows while some condition holds
-- (e.g. "the heist alarm is active"), using a double mechanism:
--
--   (a) Patch isValid() on the four timed actions that open/climb/smash/
--       destroy an object, so a player's own attempt is refused before it
--       ever starts.
--   (b) A per-tick sweep over the zone's known entries that reverts
--       anything broken through a path that doesn't go through those
--       actions (direct combat damage, zombies, etc).
--
-- KeyasLib.lua defines the shared namespace/debug flag; this file only
-- ever reads it from inside a function, never at file scope (see the
-- module-load-order rule in KeyasLib.lua's header comment).
--
-- KNOWN LIMITATION (see spec): once a window's glass is gone
-- (isGlassRemoved() true) it cannot be restored by this module - only the
-- smashed state and health can be reverted, not missing glass. Zones built
-- on top of this should treat "glass removed" windows as a permanent
-- breach and design around it (e.g. don't rely on a single window as the
-- only seal point).
--
-- CALL-SITE NOTE FOR MIGRATION: the exact restore call
-- (setSmashed/RecalcAllWithNeighbours) below mirrors the method names used
-- in LastPurpose's original LP_BankSecurity.lua. If your build's exact
-- signature differs from what's here, this is the one place to patch it -
-- everything else in this file is generic.

KeyasZones = KeyasZones or {}

local function dprint(...)
    if KeyasLib and KeyasLib.debugPrint then
        KeyasLib.debugPrint(...)
    end
end

-- id -> { bbox, active, warn, entries = {...}, lastWarnMs = {} }
local zones = {}

--============================================================
-- Part (a): patch isValid() on the relevant timed actions
--============================================================

-- Which field on each action instance holds the IsoObject being acted on.
-- Confirmed against the 42.x Lua class docs: all four store the target
-- directly on the instance (ISSmashWindow uses "window", the other three
-- use "item").
local ACTION_TARGET_FIELD = {
    ISSmashWindow = "window",
    ISOpenCloseDoor = "item",
    ISClimbThroughWindow = "item",
    ISDestroyStuffAction = "item",
}

-- className -> true once successfully patched. Patching is otherwise
-- retried (see tryPatchAllActionClasses) since PZ loads .lua files
-- alphabetically and a vanilla action class might not exist yet the first
-- time this file runs.
local patchedActionClasses = {}

local function isInsideAnyActiveZone(square)
    if not square then return false, nil end
    local ok, sx = pcall(square.getX, square)
    local ok2, sy = pcall(square.getY, square)
    local ok3, sz = pcall(square.getZ, square)
    if not (ok and ok2 and ok3) then return false, nil end

    for id, z in pairs(zones) do
        local b = z.bbox
        if sx >= b.minX and sx <= b.maxX
            and sy >= b.minY and sy <= b.maxY
            and sz >= b.minZ and sz <= b.maxZ then
            local ok4, activeNow = pcall(z.active)
            if ok4 and activeNow then
                return true, z, id
            end
        end
    end
    return false, nil
end

--- Rate-limits warn() so a player mashing a blocked action doesn't spam
--- their own callback (e.g. a chat message) dozens of times a second.
local WARN_COOLDOWN_MS = 2000
local function maybeWarn(zone, zoneId, player)
    if not zone.warn or not player then return end
    zone.lastWarnMs = zone.lastWarnMs or {}
    local key = tostring(player)
    local now = 0
    pcall(function() now = getTimestampMs() end)
    local last = zone.lastWarnMs[key] or 0
    if now - last < WARN_COOLDOWN_MS then return end
    zone.lastWarnMs[key] = now
    local ok = pcall(zone.warn, player)
    if not ok then dprint("KeyasZones: zone '" .. tostring(zoneId) .. "' warn() errored") end
end

local function patchActionClass(className, fieldName)
    if patchedActionClasses[className] then return true end

    local cls = _G[className]
    if not cls then
        return false -- not loaded yet, caller will retry
    end
    if cls._KeyasZones_patched then
        patchedActionClasses[className] = true
        return true
    end

    local originalIsValid = cls.isValid
    if type(originalIsValid) ~= "function" then
        print("[KeyasZones] ERROR: " .. className .. ".isValid is not a function, cannot wrap - zone sealing will not cover this action")
        patchedActionClasses[className] = true -- don't retry forever on a genuinely absent method
        return true
    end

    cls.isValid = function(self, ...)
        local okTarget, target = pcall(function() return self[fieldName] end)
        if okTarget and target then
            local okSq, square = pcall(target.getSquare, target)
            if okSq and square then
                local blocked, zone, zoneId = isInsideAnyActiveZone(square)
                if blocked then
                    maybeWarn(zone, zoneId, self.character)
                    return false
                end
            end
        end
        return originalIsValid(self, ...)
    end

    cls._KeyasZones_patched = true
    patchedActionClasses[className] = true
    dprint("KeyasZones: patched " .. className .. ".isValid")
    return true
end

local function tryPatchAllActionClasses()
    local allDone = true
    for className, fieldName in pairs(ACTION_TARGET_FIELD) do
        if not patchedActionClasses[className] then
            if not patchActionClass(className, fieldName) then
                allDone = false
            end
        end
    end
    return allDone
end

-- First attempt right away (usually succeeds; vanilla action classes load
-- before mod client files in practice). If any class wasn't ready yet,
-- keep retrying once an in-game minute until every class is patched -
-- covers the case where load order isn't what we expect.
tryPatchAllActionClasses()
local function onEveryOneMinuteRetryPatch()
    if tryPatchAllActionClasses() then
        Events.EveryOneMinute.Remove(onEveryOneMinuteRetryPatch)
    end
end
pcall(function() Events.EveryOneMinute.Add(onEveryOneMinuteRetryPatch) end)

--============================================================
-- Part (b): per-tick restoration sweep over known entries
--============================================================

--- Best-effort "is this broken" check across windows and doors. Tries
--- several candidate accessors via pcall since window/door break-state
--- accessors aren't unified in the vanilla API.
local function isEntryBroken(ref)
    local okSmashed, smashed = pcall(ref.isSmashed, ref)
    if okSmashed and smashed then return true end

    local okHealth, health = pcall(ref.getHealth, ref)
    if okHealth and type(health) == "number" and health <= 0 then return true end

    local okDestroyed, destroyed = pcall(ref.isDestroyed, ref)
    if okDestroyed and destroyed then return true end

    return false
end

-- Health a restored entry is set to. Deliberately high (not just "full")
-- so plain thumping - zombies, or a player with no smash/destroy action
-- available to KeyasZones' isValid patch - takes effectively forever
-- instead of breaking it again within seconds and fighting the sweep's
-- rebuild-rate limit. Public so a consumer can tune it.
KeyasZones.RESTORE_HEALTH = 100000

-- ref -> the health it had before KeyasZones first bumped it, so
-- unregister() can optionally put it back. Weak keys: never keeps a
-- destroyed/unloaded game object alive on our account.
local originalHealthByRef = setmetatable({}, {__mode = "k"})

--- Restores one broken entry. Returns true if a restore was attempted
--- (used for the per-object rate limit), false if this entry can't be
--- restored at all right now (e.g. glass removed).
local function restoreEntry(ref)
    local okGlassCheck, glassRemoved = pcall(ref.isGlassRemoved, ref)
    if okGlassCheck and glassRemoved then
        -- Known limitation (documented in README/MIGRATION): missing
        -- glass cannot be put back. Nothing more to do for this entry.
        return false
    end

    pcall(ref.setSmashed, ref, false)

    local okHealth, health = pcall(ref.getHealth, ref)
    if okHealth and type(health) == "number" then
        if originalHealthByRef[ref] == nil then
            originalHealthByRef[ref] = health
        end
        pcall(ref.setHealth, ref, KeyasZones.RESTORE_HEALTH)
    end

    pcall(ref.RecalcAllWithNeighbours, ref)

    return true
end

--- Decides whether an object found on a square counts as a sealable
--- entry, and what kind. IsoThumpable covers built structures like a
--- bank's reinforced doors/windows, which square:getWindow()/getDoor()
--- don't - those two only ever return a plain IsoWindow/IsoDoor, at most
--- one each, and miss everything else standing on the square.
local function classifyEntry(obj)
    local okWin, isWindowClass = pcall(instanceof, obj, "IsoWindow")
    if okWin and isWindowClass then return "window" end

    local okDoor, isDoorClass = pcall(instanceof, obj, "IsoDoor")
    if okDoor and isDoorClass then return "door" end

    local okThump, isThumpable = pcall(instanceof, obj, "IsoThumpable")
    if okThump and isThumpable then
        local okIsDoor, thumpIsDoor = pcall(obj.isDoor, obj)
        if okIsDoor and thumpIsDoor then return "thumpable" end
        local okIsWindow, thumpIsWindow = pcall(obj.isWindow, obj)
        if okIsWindow and thumpIsWindow then return "thumpable" end
    end

    return nil
end

--- The (x, y) columns to inspect for a bbox. With no `shell` this is every
--- column in the bbox (the whole footprint). With `shell = N` it is only
--- the columns within N tiles of a bbox edge - the building's outer shell -
--- which is what a seal actually cares about: interior doors/windows never
--- need sealing, and skipping the hollow middle turns an O(w*h) scan into
--- an O(2*N*(w+h)) one. Falls back to the full footprint when the bbox is
--- too small for a ring to make sense (< 2N on either axis).
local function zoneColumns(bbox, shell)
    local x0, x1, y0, y1 = bbox.minX, bbox.maxX, bbox.minY, bbox.maxY
    local n = tonumber(shell)
    if not n or n < 1 or (x1 - x0) < (2 * n) or (y1 - y0) < (2 * n) then
        local cols = {}
        for x = x0, x1 do
            for y = y0, y1 do cols[#cols + 1] = {x, y} end
        end
        return cols
    end

    local seen, cols = {}, {}
    local function add(x, y)
        local key = x .. ":" .. y
        if not seen[key] then seen[key] = true; cols[#cols + 1] = {x, y} end
    end
    -- top + bottom bands (full width, N deep)
    for x = x0, x1 do
        for d = 0, n - 1 do add(x, y0 + d); add(x, y1 - d) end
    end
    -- left + right bands (full height, N deep)
    for y = y0, y1 do
        for d = 0, n - 1 do add(x0 + d, y); add(x1 - d, y) end
    end
    return cols
end

--- Scans a zone's sealable entries and caches them as "known entries".
--- Runs at register(), automatically again for zones the local player is
--- near (see the EveryOneMinute proximity rescan below), and on demand via
--- the public rescan(). `shell` (optional) restricts the scan to the
--- building's outer ring - see zoneColumns().
local function scanZoneEntries(bbox, shell)
    local entries = {}
    local okCell, cell = pcall(getCell)
    if not okCell or not cell then
        print("[KeyasZones] ERROR: getCell() unavailable, zone will have no known entries until a rescan")
        return entries
    end

    local columns = zoneColumns(bbox, shell)
    for _, c in ipairs(columns) do
        local x, y = c[1], c[2]
        for z = bbox.minZ, bbox.maxZ do
            local okSq, square = pcall(cell.getGridSquare, cell, x, y, z)
            if okSq and square then
                local okObjs, objects = pcall(square.getObjects, square)
                if okObjs and objects then
                    local okSize, size = pcall(objects.size, objects)
                    if okSize then
                        for i = 0, size - 1 do
                            local okGet, obj = pcall(objects.get, objects, i)
                            if okGet and obj then
                                local kind = classifyEntry(obj)
                                if kind then
                                    table.insert(entries, {kind = kind, ref = obj})
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return entries
end

--- Per-object rebuild rate limit: at most KeyasLib.ZONE_MAX_REBUILDS_PER_SECOND
--- restores per second, so a persistent attacker doesn't cause visible
--- flicker as the object is repeatedly smashed and instantly un-smashed.
local rebuildTimestamps = setmetatable({}, {__mode = "k"}) -- weak keys: don't keep dead objects alive

local function canRebuildNow(ref)
    local maxPerSecond = (KeyasLib and KeyasLib.ZONE_MAX_REBUILDS_PER_SECOND) or 3
    local now = 0
    pcall(function() now = getTimestampMs() end)
    local history = rebuildTimestamps[ref]
    if not history then
        history = {}
        rebuildTimestamps[ref] = history
    end
    -- Drop timestamps older than 1 second.
    local kept = {}
    for _, t in ipairs(history) do
        if now - t < 1000 then table.insert(kept, t) end
    end
    rebuildTimestamps[ref] = kept
    if #kept >= maxPerSecond then return false end
    table.insert(kept, now)
    return true
end

-- The sweep doesn't need to run every render frame - gate it to roughly
-- 4x/second, which is fast enough to feel instant but far cheaper than a
-- true per-tick scan over every zone's entries.
local SWEEP_INTERVAL_MS = 250
local lastSweepMs = 0

local function sweepZones()
    local now = 0
    pcall(function() now = getTimestampMs() end)
    if now - lastSweepMs < SWEEP_INTERVAL_MS then return end
    lastSweepMs = now

    for id, zone in pairs(zones) do
        local ok, activeNow = pcall(zone.active)
        if ok and activeNow then
            for _, entry in ipairs(zone.entries) do
                if isEntryBroken(entry.ref) and canRebuildNow(entry.ref) then
                    restoreEntry(entry.ref)
                end
            end
        end
    end
end
pcall(function() Events.OnTick.Add(sweepZones) end)

--============================================================
-- Automatic proximity rescan
--
-- scanZoneEntries only finds anything on squares that are actually loaded
-- into memory. A zone registered while the player is far away - or right
-- after loading a save, where the whole Lua-side entries cache is gone
-- regardless of distance - would otherwise sit at zero entries forever
-- unless the consumer remembers to call rescan() itself. Instead, once a
-- minute, re-scan any active zone the local player is close enough to for
-- its squares to plausibly be loaded.
--============================================================

local RESCAN_TRIGGER_DISTANCE = 120 -- tiles, from bbox center

local function bboxCenter(bbox)
    return (bbox.minX + bbox.maxX) / 2, (bbox.minY + bbox.maxY) / 2
end

-- NOTE: uses the single local player (getPlayer(), player index 0). Last
-- Purpose is singleplayer-only today; a mod supporting local split-screen
-- should loop getSpecificPlayer(0..3) here instead.
local function onEveryOneMinuteRescanNearbyZones()
    local okPlayer, player = pcall(getPlayer)
    if not okPlayer or not player then return end
    local okX, px = pcall(player.getX, player)
    local okY, py = pcall(player.getY, player)
    if not (okX and okY) then return end

    for id, zone in pairs(zones) do
        local okActive, activeNow = pcall(zone.active)
        if okActive and activeNow then
            local cx, cy = bboxCenter(zone.bbox)
            local dx, dy = px - cx, py - cy
            if (dx * dx + dy * dy) <= (RESCAN_TRIGGER_DISTANCE * RESCAN_TRIGGER_DISTANCE) then
                zone.entries = scanZoneEntries(zone.bbox, zone.shell)
                dprint("KeyasZones: auto-rescanned zone '" .. tostring(id) .. "' (" .. tostring(#zone.entries) .. " entries)")
            end
        end
    end
end
pcall(function() Events.EveryOneMinute.Add(onEveryOneMinuteRescanNearbyZones) end)

--============================================================
-- Public API
--============================================================

--- Registers a protected zone.
--- @param id string unique zone id
--- @param def table {
---   bbox = {minX,maxX,minY,maxY,minZ,maxZ},
---   active = function() -> boolean end,   -- polled every check
---   warn = function(player) end,          -- optional, rate-limited to 1/2s per player
---   shell = number,                       -- optional: only scan within this many
---                                         --   tiles of a bbox edge (the building's
---                                         --   outer ring). Interior doors/windows
---                                         --   never need sealing, so for a mostly
---                                         --   hollow building this is a big win. If
---                                         --   the found-entry count comes out too
---                                         --   low, the bbox has padding - raise
---                                         --   shell or tighten the bbox.
--- }
function KeyasZones.register(id, def)
    if not id or not def or not def.bbox or type(def.active) ~= "function" then
        print("[KeyasZones] ERROR: register(id, def) needs id, def.bbox and def.active")
        return false
    end
    zones[id] = {
        bbox = def.bbox,
        active = def.active,
        warn = def.warn,
        shell = def.shell,
        entries = scanZoneEntries(def.bbox, def.shell),
        lastWarnMs = {},
    }
    dprint("KeyasZones: registered zone '" .. tostring(id) .. "' with " .. tostring(#zones[id].entries) .. " known entries")
    return true
end

--- Re-scans a zone's bbox for doors/windows, e.g. after the consumer mod
--- places or removes a building object inside it at runtime.
function KeyasZones.rescan(id)
    local zone = zones[id]
    if not zone then return false end
    zone.entries = scanZoneEntries(zone.bbox, zone.shell)
    return true
end

--- The zone's currently-known sealable entries, as an array of
--- { kind = "window"|"door"|"thumpable", ref = <IsoObject> }. A shallow
--- copy, so mutating the returned table doesn't disturb the zone. Lets a
--- consumer reuse this list (e.g. to lock the same doors) instead of
--- scanning the building a second time itself. Returns {} for an unknown id.
function KeyasZones.getEntries(id)
    local zone = zones[id]
    if not zone then return {} end
    local out = {}
    for i, e in ipairs(zone.entries) do out[i] = e end
    return out
end

--- Unregisters a zone: any windows/doors it was actively holding closed
--- are restored one last time (if currently broken), then the zone stops
--- being enforced.
function KeyasZones.unregister(id)
    local zone = zones[id]
    if not zone then return false end
    for _, entry in ipairs(zone.entries) do
        if isEntryBroken(entry.ref) then
            restoreEntry(entry.ref)
        end
        -- Put back whatever health this object had before we ever
        -- touched it, rather than leaving RESTORE_HEALTH in place
        -- permanently once the zone is no longer enforced.
        local original = originalHealthByRef[entry.ref]
        if original ~= nil then
            pcall(entry.ref.setHealth, entry.ref, original)
            originalHealthByRef[entry.ref] = nil
        end
    end
    zones[id] = nil
    dprint("KeyasZones: unregistered zone '" .. tostring(id) .. "'")
    return true
end

return KeyasZones
