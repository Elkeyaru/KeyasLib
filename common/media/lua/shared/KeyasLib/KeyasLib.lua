-- KeyasLib.lua
--
-- Single shared config file for the whole library. PZ loads every .lua file
-- independently and alphabetically, and require() does NOT force another
-- file to load first. So this is the ONLY file any KeyasLib module is
-- allowed to read a table from that was defined somewhere else - and even
-- here, callers must read KeyasLib.* from inside a function body, never at
-- file scope, since this file itself might not have loaded yet when a
-- sibling file's top level runs.
--
-- Nothing except namespace/version/debug/shared-constants belongs in this
-- file. Real logic goes in the module it belongs to.

KeyasLib = KeyasLib or {}

KeyasLib.VERSION = "1.2.5"

-- Off by default. Flip at runtime (KeyasOptions exposes a tickbox for this)
-- to get verbose logging without restarting the game.
KeyasLib.DEBUG = false

--- Prints only when KeyasLib.DEBUG is true. Use this for anything that is
--- merely informative (state transitions, cache hits, etc.). Real errors
--- must use print() directly so a debug flag left off never hides them.
-- @param ... any number of values; concatenated with spaces via tostring()
function KeyasLib.debugPrint(...)
    if not KeyasLib.DEBUG then return end
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[i] = tostring((select(i, ...)))
    end
    print("[KeyasLib] " .. table.concat(parts, " "))
end

-- Shared constants ----------------------------------------------------

-- Prefix KeyasLib itself uses when it writes to a player's ModData, so its
-- own bookkeeping (e.g. KeyasReq's scouted-region progress) never collides
-- with a consuming mod's keys. Consumers pass their OWN prefix into
-- KeyasReq.flag(); this one is only for KeyasLib-internal state.
KeyasLib.MODDATA_PREFIX = "KeyasLib_"

-- Tuning constant for KeyasZones' per-tick restoration sweep: the max number
-- of times it will rebuild any single object per second. Exists here (not
-- hidden inside KeyasZones.lua) because a consumer occasionally needs to
-- read it, e.g. to size their own timers around it - not because anything
-- outside KeyasZones should ever WRITE to it.
KeyasLib.ZONE_MAX_REBUILDS_PER_SECOND = 3

return KeyasLib
