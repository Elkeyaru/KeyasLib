-- examples/xcyos/demo.lua
--
-- Shows a KeyasUI skin window reproducing the "XCYOS" retro-OS terminal
-- from the mockup, using ONLY KeyasLib. This isn't a packaged mod - copy
-- the three files (chrome.png, zones.lua, this) into your own mod, fix the
-- require paths / media path, and call XcyosDemo.open().
--
-- chrome.png + zones.lua were produced by:
--   tools/skin_gen/generate_skin.ps1 -Spec tools/skin_gen/spec.xcyos.ps1 -OutDir examples/xcyos

require "KeyasLib/KeyasUI"

XcyosDemo = XcyosDemo or {}

-- 1. Register the skin once. chromePath is a media path (getTexture); put
--    chrome.png under your mod's media/ui/<YourMod>/ and match it here.
local REGISTERED = false
local function ensureSkin()
    if REGISTERED then return end
    local spec = require "KeyasLibExamples/xcyos_zones"   -- <- your require path to zones.lua
    KeyasUI.registerSkin("xcyos", {
        chromePath = "media/ui/KeyasLibExamples/xcyos_chrome.png",  -- <- your media path
        spec = spec,
    })
    REGISTERED = true
end

-- 2. A window class over KeyasUI.Window with skin = "xcyos".
XcyosWindow = KeyasUI.Window:derive("XcyosWindow")

function XcyosWindow:new()
    local o = KeyasUI.Window.new(self, 0, 0, 100, 100, {
        skin = "xcyos",
        closeOnEscape = true,
        closeOnClickOutside = true,
    })
    o.app = "misiones"
    return o
end

function XcyosWindow:createChildren()
    KeyasUI.Window.createChildren(self)
    -- Baked X in the title bar -> transparent click target.
    self:addZoneButton("titleClose", function(w) w:close() end,
        { hover = { r = 0.85, g = 0.16, b = 0.13, a = 0.25 } })
    -- Rail icons -> switch "app".
    for i, id in ipairs({ "misiones", "notas", "archivos", "sistema" }) do
        self:addZoneButton("rail" .. i, function(w) w.app = id end)
    end
end

-- 3. Paint dynamic content into the zones. Everything else is the baked PNG.
function XcyosWindow:onRenderContent()
    local INK   = { r = 0.086, g = 0.086, b = 0.059, a = 1 }
    local DIM   = { r = 0.29,  g = 0.28,  b = 0.235, a = 1 }
    local PHOS  = { r = 0.184, g = 0.906, b = 0.769, a = 1 }

    -- highlight the active rail zone
    local rx, ry, rw, rh = self:zone("rail" .. ({ misiones = 1, notas = 2, archivos = 3, sistema = 4 })[self.app])
    if rx then
        self:drawRect(rx, ry, rw, rh, 0.14, PHOS.r, PHOS.g, PHOS.b)
        self:drawRectBorder(rx, ry, rw, rh, 1, 0.11, 0.56, 0.49)
    end

    local lx, ly, lw = self:zone("listPane")
    local dx, dy, dw = self:zone("detailPane")

    if self.app == "misiones" then
        KeyasUI.text(self, "LADRON - GOLPES", lx, ly, DIM)
        local cy = ly + 24
        for _, m in ipairs({ "1. El ultimo golpe", "2. ?????????", "3. ?????????", "4. ?????????" }) do
            KeyasUI.text(self, m, lx, cy, INK); cy = cy + 20
        end
        KeyasUI.text(self, "El ultimo golpe", dx, dy, INK)
        KeyasUI.wrapped(self, "Preparar y ejecutar el golpe al Knox Bank, el banco mas grande de Kentucky.",
            dx, dy + 26, dw, INK)
    else
        KeyasUI.text(self, string.upper(self.app), lx, ly, INK)
        KeyasUI.wrapped(self, "Contenido de esta seccion. El chrome (marco, degradados, sombra, vinneta) es el PNG horneado; esto es lo unico que dibuja Lua.",
            lx, ly + 26, (dx + dw) - lx, DIM)
    end
end

function XcyosDemo.open()
    ensureSkin()
    if XcyosDemo.win then XcyosDemo.win:close() end
    local w = XcyosWindow:new()
    w:initialise()
    w:instantiate()
    w:addToUIManager()
    XcyosDemo.win = w
end
