-- KeyasOptions.lua
--
-- Thin wrapper around B42's native PZAPI.ModOptions. Optional module - a
-- consumer that doesn't need a settings panel can simply not require this
-- file; nothing else in KeyasLib depends on it.
--
-- Guards against double registration two ways: an in-session table (in
-- case two of the consumer's own files both call createPanel with the
-- same id) and a check against PZAPI.ModOptions:getOptions() (in case
-- something else already registered that id first).

KeyasOptions = KeyasOptions or {}

local function dprint(...)
    if KeyasLib and KeyasLib.debugPrint then
        KeyasLib.debugPrint(...)
    end
end

-- modOptionsID -> the PZAPI Options object, cached for this session so a
-- second createPanel() call with the same id is a safe no-op / reuse.
local registeredPanels = {}

--- Creates (or reuses) a ModOptions panel.
--- @param modOptionsID string unique id, usually your mod's id
--- @param displayName string shown under Options > Mods
--- @param opts table optional: {
---   addDebugTickbox = boolean,      -- wires a tickbox straight to KeyasLib.DEBUG
---   keybind = {                     -- optional configurable keybind
---     id, name, defaultKey, tooltip,
---     onChange = function(newKeyCode) end,
---   },
--- }
--- @return the PZAPI Options object, or nil if PZAPI.ModOptions is unavailable
function KeyasOptions.createPanel(modOptionsID, displayName, opts)
    opts = opts or {}

    if registeredPanels[modOptionsID] then
        dprint("KeyasOptions: reusing already-created panel '" .. tostring(modOptionsID) .. "'")
        return registeredPanels[modOptionsID]
    end

    if not PZAPI or not PZAPI.ModOptions then
        print("[KeyasOptions] ERROR: PZAPI.ModOptions not available (unexpected on B42) - skipping options panel")
        return nil
    end

    local okExisting, existing = pcall(function() return PZAPI.ModOptions:getOptions(modOptionsID) end)
    if okExisting and existing then
        registeredPanels[modOptionsID] = existing
        dprint("KeyasOptions: panel '" .. tostring(modOptionsID) .. "' already registered elsewhere, reusing")
        return existing
    end

    local okCreate, options = pcall(function() return PZAPI.ModOptions:create(modOptionsID, displayName) end)
    if not okCreate or not options then
        print("[KeyasOptions] ERROR: PZAPI.ModOptions:create failed for '" .. tostring(modOptionsID) .. "'")
        return nil
    end
    registeredPanels[modOptionsID] = options

    if opts.addDebugTickbox then
        local currentDebug = (KeyasLib and KeyasLib.DEBUG) or false
        local okTick, tick = pcall(function()
            return options:addTickBox("KeyasLib_debug", "KeyasLib debug logging", currentDebug, "Registro detallado de KeyasLib para depurar problemas.")
        end)
        if okTick and tick then
            -- Sync in real time: no game restart needed to see debug logs.
            tick.onChange = function(_, selected)
                if KeyasLib then KeyasLib.DEBUG = selected end
            end
        else
            dprint("KeyasOptions: addTickBox for debug flag failed")
        end
    end

    if opts.keybind then
        local kb = opts.keybind
        local okDefaultKey, defaultKey = pcall(function() return kb.defaultKey or Keyboard.KEY_NONE end)
        local okKeybind, keybind = pcall(function()
            return options:addKeyBind(kb.id, kb.name, (okDefaultKey and defaultKey) or 0, kb.tooltip)
        end)
        if okKeybind and keybind then
            if kb.onChange then
                keybind.onChange = function(_, newKey)
                    pcall(kb.onChange, newKey)
                end
            end
        else
            dprint("KeyasOptions: addKeyBind failed for '" .. tostring(kb.id) .. "'")
        end
    end

    return options
end

return KeyasOptions
