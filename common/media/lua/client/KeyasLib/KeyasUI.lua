-- KeyasUI.lua
--
-- Retro ISUI toolkit extracted from LastPurpose's LP_Computer.lua. Gives any
-- consumer mod a "terminal / retro-OS" look: a Window base class, bevel/pane
-- drawing helpers, a tinted icon loader, and a glyph-by-glyph bitmap font
-- renderer (B42 has no clean way to register a new font without stomping the
-- vanilla ones, so custom text is drawn from a PNG atlas instead - see the
-- KeyasUI.text() section below).
--
-- Every engine call that could plausibly change shape between game versions
-- (texture loads, drawSubTexture, key-code lookups) is wrapped in pcall so a
-- missing asset or a shifted API degrades the UI instead of crashing it.
--
-- KeyasLib itself is defined in shared/KeyasLib/KeyasLib.lua. We only ever
-- touch it from inside function bodies (see debugPrint() calls below), never
-- at file scope, since load order between the two files is not guaranteed.

require "ISUI/ISPanel"
require "ISUI/ISButton"

KeyasUI = KeyasUI or {}

-- Local helper: routes to KeyasLib.debugPrint if KeyasLib has loaded yet,
-- otherwise stays silent rather than erroring on a nil global. This is the
-- pattern every KeyasLib file should use to touch the shared config.
local function dprint(...)
    if KeyasLib and KeyasLib.debugPrint then
        KeyasLib.debugPrint(...)
    end
end

--============================================================
-- Palette - local to this file. A consuming mod that wants a different
-- look should copy this table into its own file rather than reach in and
-- mutate KeyasUI's internals.
--============================================================
KeyasUI.PALETTE = {
    bgFull     = {r = 0.04, g = 0.05, b = 0.045, a = 1.0},  -- fullscreen backdrop
    panel      = {r = 0.10, g = 0.12, b = 0.10, a = 1.0},   -- window body
    titleBar   = {r = 0.06, g = 0.08, b = 0.065, a = 1.0},
    statusBar  = {r = 0.06, g = 0.08, b = 0.065, a = 1.0},
    bevelLight = {r = 0.32, g = 0.40, b = 0.32, a = 1.0},
    bevelDark  = {r = 0.01, g = 0.02, b = 0.01, a = 1.0},
    text       = {r = 0.55, g = 0.95, b = 0.55, a = 1.0},   -- phosphor green
    textDim    = {r = 0.30, g = 0.55, b = 0.30, a = 1.0},
}

--- Resolves a palette color by key, preferring an override `palette` table
--- (if given and it has that key) over KeyasUI.PALETTE. Lets a consumer
--- pass its own colors into bevel/titleBar/statusBar/Window without ever
--- mutating the shared KeyasUI.PALETTE table.
local function paletteColor(palette, key)
    if palette and palette[key] then return palette[key] end
    return KeyasUI.PALETTE[key]
end

--============================================================
-- Drawing helpers
--
-- All take the owning ISUIElement as `self` (they call self:drawRect / etc,
-- which are instance methods), so a Window (or any panel) uses them as
-- KeyasUI.pane(self, x, y, w, h). bevel/titleBar/statusBar additionally
-- take an optional trailing `palette` table ({bevelLight=, bevelDark=,
-- titleBar=, statusBar=, text=, textDim=, ...}) to override individual
-- colors for that call; rect/pane are unaffected since they already take
-- an explicit `color` argument.
--============================================================

--- Flat filled rectangle. Thin wrapper so callers don't need to remember
--- drawRect's a,r,g,b argument order.
function KeyasUI.rect(self, x, y, w, h, color)
    color = color or KeyasUI.PALETTE.panel
    self:drawRect(x, y, w, h, color.a or 1, color.r, color.g, color.b)
end

--- Two-tone 1px bevel border, like a Windows 3.1 / retro-OS widget.
--- raised = true -> light top+left, dark bottom+right (button-out look).
--- raised = false -> reversed (sunken / pressed-in look).
--- @param palette table optional override, see the drawing-helpers header comment
function KeyasUI.bevel(self, x, y, w, h, raised, palette)
    local light = paletteColor(palette, "bevelLight")
    local dark = paletteColor(palette, "bevelDark")
    local top, bottom = light, dark
    if not raised then
        top, bottom = dark, light
    end
    -- top edge + left edge
    self:drawRect(x, y, w, 1, top.a, top.r, top.g, top.b)
    self:drawRect(x, y, 1, h, top.a, top.r, top.g, top.b)
    -- bottom edge + right edge
    self:drawRect(x, y + h - 1, w, 1, bottom.a, bottom.r, bottom.g, bottom.b)
    self:drawRect(x + w - 1, y, 1, h, bottom.a, bottom.r, bottom.g, bottom.b)
end

--- A filled content pane with a sunken bevel border - the standard
--- "inset screen/readout" look used for body content and text boxes.
function KeyasUI.pane(self, x, y, w, h, color)
    KeyasUI.rect(self, x, y, w, h, color or KeyasUI.PALETTE.panel)
    KeyasUI.bevel(self, x, y, w, h, false)
end

--- Draws a title bar strip. Does NOT draw the close button - Window wires
--- that up separately since it needs a click target, not just pixels.
--- @param title string
--- @param height number bar height in px
--- @param palette table optional override, see the drawing-helpers header comment
function KeyasUI.titleBar(self, x, y, w, height, title, palette)
    KeyasUI.rect(self, x, y, w, height, paletteColor(palette, "titleBar"))
    KeyasUI.bevel(self, x, y, w, height, true, palette)
    if title and title ~= "" then
        local c = paletteColor(palette, "text")
        local ok = pcall(function()
            self:drawText(title, x + 6, y + 2, c.r, c.g, c.b, c.a, UIFont.Small)
        end)
        if not ok then dprint("KeyasUI.titleBar: drawText failed") end
    end
end

--- Draws a status bar strip along the bottom of a window.
--- @param palette table optional override, see the drawing-helpers header comment
function KeyasUI.statusBar(self, x, y, w, height, text, palette)
    KeyasUI.rect(self, x, y, w, height, paletteColor(palette, "statusBar"))
    KeyasUI.bevel(self, x, y, w, height, false, palette)
    if text and text ~= "" then
        local c = paletteColor(palette, "textDim")
        local ok = pcall(function()
            self:drawText(text, x + 6, y + 2, c.r, c.g, c.b, c.a, UIFont.Small)
        end)
        if not ok then dprint("KeyasUI.statusBar: drawText failed") end
    end
end

--============================================================
-- IconSheet - loads one image (a sheet of icons, or a single icon) with a
-- fallback so a missing PNG never breaks the UI, only makes it plainer.
--============================================================
local IconSheet = {}
IconSheet.__index = IconSheet
KeyasUI.IconSheet = IconSheet

--- @param path string media path passed to getTexture(), e.g. "media/ui/KeyasLib/icons.png"
function IconSheet.new(path)
    local o = setmetatable({}, IconSheet)
    o.path = path
    o.texture = nil
    o.loaded = false
    o:_tryLoad()
    return o
end

function IconSheet:_tryLoad()
    self.loaded = true
    local ok, tex = pcall(getTexture, self.path)
    if ok and tex then
        self.texture = tex
    else
        print("[KeyasUI] ERROR: icon texture failed to load: " .. tostring(self.path))
    end
end

--- Draws the whole sheet/icon tinted, scaled into a box. If the texture
--- failed to load, draws a plain bevelled rectangle instead so layout
--- doesn't collapse and the UI stays usable.
--- @param color table {r,g,b,a} tint, defaults to white (no tint)
function IconSheet:draw(self_owner, x, y, w, h, color)
    color = color or {r = 1, g = 1, b = 1, a = 1}
    if self.texture then
        local ok = pcall(function()
            self_owner:drawTextureScaled(self.texture, x, y, w, h, color.a or 1, color.r, color.g, color.b)
        end)
        if ok then return end
        dprint("IconSheet:draw drawTextureScaled failed for", self.path)
    end
    -- Fallback glyph: a bevelled box with an X, so a missing icon is
    -- obviously a placeholder rather than invisible.
    KeyasUI.rect(self_owner, x, y, w, h, KeyasUI.PALETTE.panel)
    KeyasUI.bevel(self_owner, x, y, w, h, true)
    local ok2 = pcall(function()
        self_owner:drawLine2(x, y, x + w, y + h, 1, 1, 0.3, 0.3)
        self_owner:drawLine2(x + w, y, x, y + h, 1, 1, 0.3, 0.3)
    end)
    if not ok2 then dprint("IconSheet:draw fallback drawLine2 failed") end
end

--- Draws one sub-rectangle of the sheet (for multi-icon sheets), tinted.
--- subX/subY/subW/subH are pixel coordinates within the source PNG.
function IconSheet:drawSub(self_owner, subX, subY, subW, subH, x, y, w, h, color)
    color = color or {r = 1, g = 1, b = 1, a = 1}
    if self.texture then
        local ok = pcall(function()
            self_owner:drawSubTexture(self.texture, subX, subY, subW, subH, x, y, w, h, color.a or 1, color.r, color.g, color.b)
        end)
        if ok then return end
        dprint("IconSheet:drawSub drawSubTexture failed for", self.path)
    end
    KeyasUI.rect(self_owner, x, y, w, h, KeyasUI.PALETTE.panel)
    KeyasUI.bevel(self_owner, x, y, w, h, true)
end

--============================================================
-- Bitmap font renderer
--
-- registerFont(id, { atlasPath, metrics }) where metrics =
--   { lh = <line height>, base = <baseline offset from top>,
--     g = { [codepoint] = {x,y,w,h,xoff,yoff,xadv}, ... } }
-- (this is exactly the shape tools/font_atlas_gen produces).
--
-- If the font id was never registered, or its atlas fails to load, every
-- call below falls back to vanilla UIFont.Small/Medium/Large so text is
-- never simply missing.
--============================================================
KeyasUI._fonts = {}

--- Picks the vanilla UIFont a registered font falls back to when its atlas
--- hasn't loaded (or failed to). def.fallbackFont wins if given; otherwise
--- def.size (the pixel size the atlas was generated at) is mapped onto the
--- closest vanilla size; with neither, UIFont.Small.
local function resolveFallbackFont(def)
    if def.fallbackFont then return def.fallbackFont end
    if def.size then
        if def.size >= 27 then return UIFont.Large end
        if def.size >= 18 then return UIFont.Medium end
    end
    return UIFont.Small
end

--- @param def table { atlasPath, metrics, fallbackFont = UIFont.* (optional), size = number (optional) }
function KeyasUI.registerFont(id, def)
    if not id or not def or not def.atlasPath or not def.metrics then
        print("[KeyasUI] ERROR: registerFont(id, def) needs id, def.atlasPath and def.metrics")
        return false
    end
    KeyasUI._fonts[id] = {
        atlasPath = def.atlasPath,
        metrics = def.metrics,
        texture = nil,
        triedLoad = false,
        fallbackFont = resolveFallbackFont(def),
    }
    return true
end

local function getFontEntry(fontId)
    local f = fontId and KeyasUI._fonts[fontId]
    if not f then return nil end
    if not f.triedLoad then
        f.triedLoad = true
        local ok, tex = pcall(getTexture, f.atlasPath)
        if ok and tex then
            f.texture = tex
        else
            print("[KeyasUI] ERROR: font atlas failed to load: " .. tostring(f.atlasPath) .. " (font id '" .. tostring(fontId) .. "'), falling back to vanilla font")
        end
    end
    return f
end

--- Iterates a UTF-8 string, yielding one codepoint per call (1-3 byte
--- sequences only - plenty for Latin-1/Latin Extended/box-drawing atlases;
--- a 4-byte sequence is treated as a single unknown-glyph placeholder
--- rather than attempted, since no bitmap font here ships glyphs that far
--- out anyway).
local function utf8Codepoints(s)
    local i = 1
    local len = #s
    return function()
        if i > len then return nil end
        local b1 = string.byte(s, i)
        local cp, n
        if b1 < 0x80 then
            cp, n = b1, 1
        elseif b1 >= 0xC0 and b1 < 0xE0 then
            local b2 = string.byte(s, i + 1) or 0x80
            cp = ((b1 - 0xC0) * 0x40) + (b2 - 0x80)
            n = 2
        elseif b1 >= 0xE0 and b1 < 0xF0 then
            local b2 = string.byte(s, i + 1) or 0x80
            local b3 = string.byte(s, i + 2) or 0x80
            cp = ((b1 - 0xE0) * 0x1000) + ((b2 - 0x80) * 0x40) + (b3 - 0x80)
            n = 3
        else
            cp, n = 0xFFFD, 1
        end
        i = i + n
        return cp
    end
end

--- Reads one glyph's fields regardless of whether metrics.g[cp] uses named
--- keys ({x=,y=,w=,h=,xoff=,yoff=,xadv=}) or a plain positional array
--- ({x,y,w,h,xoff,yoff,xadv}, i.e. g[1]..g[7]). Both are the same
--- convention (see the comment above KeyasUI.text's draw loop) - this just
--- lets an atlas that already ships positional metrics work unchanged.
local function glyphXYWH(g)
    if g[1] ~= nil then
        return g[1], g[2], g[3], g[4], g[5], g[6], g[7]
    end
    return g.x, g.y, g.w, g.h, g.xoff, g.yoff, g.xadv
end

--- Measures a string in a registered bitmap font.
--- @return width, lineHeight
function KeyasUI.measure(str, fontId)
    local f = getFontEntry(fontId)
    if not f or not f.texture then
        local fallbackFont = (f and f.fallbackFont) or UIFont.Small
        local w, h = 0, 12
        pcall(function() w = getTextManager():MeasureStringX(fallbackFont, str) end)
        pcall(function() h = getTextManager():getFontHeight(fallbackFont) end)
        return w, h
    end
    local width = 0
    for cp in utf8Codepoints(str) do
        local g = f.metrics.g[cp]
        if g then
            local _, _, gw, _, gxoff, _, gxadv = glyphXYWH(g)
            width = width + (gxadv or (gw + (gxoff or 0)))
        end
    end
    return width, f.metrics.lh or 12
end

--- Draws a string glyph-by-glyph from a registered atlas via drawSubTexture.
--- Falls back to self:drawText with a vanilla font if the font id isn't
--- registered or its atlas didn't load.
--- @param colorRGB table {r,g,b,a}
function KeyasUI.text(self, str, x, y, colorRGB, fontId)
    colorRGB = colorRGB or KeyasUI.PALETTE.text
    local f = getFontEntry(fontId)
    if not f or not f.texture then
        local fallbackFont = (f and f.fallbackFont) or UIFont.Small
        local ok = pcall(function()
            self:drawText(str, x, y, colorRGB.r, colorRGB.g, colorRGB.b, colorRGB.a or 1, fallbackFont)
        end)
        if not ok then dprint("KeyasUI.text: fallback drawText failed") end
        return
    end
    -- Glyph placement follows the same convention BMFont-style atlases use:
    -- xoff/yoff are measured straight from the current pen position / the
    -- top of the line, so placing a glyph is just an addition - no
    -- baseline arithmetic needed here. tools/font_atlas_gen emits exactly
    -- this convention (see its README). glyphXYWH() reads it out of either
    -- a named-key or positional glyph table - see its comment above.
    local penX = x
    for cp in utf8Codepoints(str) do
        local g = f.metrics.g[cp]
        if g then
            local gx, gy, gw, gh, gxoff, gyoff, gxadv = glyphXYWH(g)
            if gw and gw > 0 and gh and gh > 0 then
                local drawX = penX + (gxoff or 0)
                local drawY = y + (gyoff or 0)
                local ok = pcall(function()
                    self:drawSubTexture(f.texture, gx, gy, gw, gh, drawX, drawY, gw, gh, colorRGB.a or 1, colorRGB.r, colorRGB.g, colorRGB.b)
                end)
                if not ok then dprint("KeyasUI.text: drawSubTexture failed for codepoint", cp) end
            end
            -- Space and other zero-ink glyphs still advance the pen even
            -- though there's nothing to draw.
            penX = penX + (gxadv or (gw + (gxoff or 0)))
        else
            -- Unknown glyph: advance by an estimate rather than stalling
            -- the whole line at one spot.
            penX = penX + (f.metrics.lh or 8) * 0.5
        end
    end
end

--- Word-wraps `str` to width `w` and draws each line via KeyasUI.text().
--- Returns the total height used, so callers can lay out what comes next.
function KeyasUI.wrapped(self, str, x, y, w, colorRGB, fontId)
    local _, lineHeight = KeyasUI.measure("Mg", fontId)
    lineHeight = lineHeight or 12
    local lines = {}
    local current = ""
    for word in str:gmatch("%S+") do
        local candidate = (current == "" and word) or (current .. " " .. word)
        local candWidth = KeyasUI.measure(candidate, fontId)
        if candWidth > w and current ~= "" then
            table.insert(lines, current)
            current = word
        else
            current = candidate
        end
    end
    if current ~= "" then table.insert(lines, current) end

    local penY = y
    for _, line in ipairs(lines) do
        KeyasUI.text(self, line, x, penY, colorRGB, fontId)
        penY = penY + lineHeight
    end
    return penY - y
end

--============================================================
-- KeyasUI.Window - base class for retro-OS style windows.
--
-- Two modes:
--   options.fullscreen = true  -> opaque, fills the screen, no title-bar
--                                 drag, closes like any other window.
--   options.fullscreen = false (default) -> centered window with a
--                                 draggable title bar and an X button.
--
-- layout() is where every child rect gets computed from getWidth()/
-- getHeight() (and, for fullscreen windows, the current screen size) -
-- nothing is hardcoded so resolution changes don't leave stale geometry.
--============================================================
KeyasUI.Window = ISPanel:derive("KeyasUI.Window")
local Window = KeyasUI.Window

local TITLE_BAR_HEIGHT = 20
local STATUS_BAR_HEIGHT = 18
local CLOSE_BUTTON_SIZE = 16

--- @param options table optional: {
---   title = string,
---   fullscreen = boolean (default false),
---   showStatusBar = boolean (default false),
---   statusText = string,
---   closeOnEscape = boolean (default true),
---   closeOnClickOutside = boolean (default true, ignored when fullscreen),
---   palette = table (optional override, see the drawing-helpers header comment;
---              falls back to KeyasUI.PALETTE for any color it doesn't set),
--- }
function Window:new(x, y, width, height, options)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.options = options or {}
    o.title = o.options.title or ""
    o.fullscreen = o.options.fullscreen or false
    o.showStatusBar = o.options.showStatusBar or false
    o.statusText = o.options.statusText or ""
    o.closeOnEscape = (o.options.closeOnEscape ~= false)
    o.closeOnClickOutside = (o.options.closeOnClickOutside ~= false)
    o.palette = o.options.palette

    o.moveWithMouse = not o.fullscreen
    o.backgroundColor = {r = 0, g = 0, b = 0, a = 1}
    o.borderColor = {r = 0, g = 0, b = 0, a = 0}

    o._keyHandler = nil -- bound in addToUIManager, cleared in close()

    return o
end

function Window:initialise()
    ISPanel.initialise(self)
end

function Window:createChildren()
    ISPanel.createChildren(self)

    if not self.fullscreen then
        self.closeButton = ISButton:new(
            self:getWidth() - CLOSE_BUTTON_SIZE - 2, 2,
            CLOSE_BUTTON_SIZE, CLOSE_BUTTON_SIZE,
            "X", self, Window.onCloseButtonClick
        )
        self.closeButton:initialise()
        self.closeButton:instantiate()
        self:addChild(self.closeButton)
    end

    self:layout()
end

--- Recomputes every child rect from the current width/height. Call this
--- again after a manual resize/resolution change - nothing here is cached
--- across calls, so it's always safe to re-run.
function Window:layout()
    local w, h = self:getWidth(), self:getHeight()

    if self.fullscreen then
        local ok, sw = pcall(getCore().getScreenWidth, getCore())
        local ok2, sh = pcall(getCore().getScreenHeight, getCore())
        if ok and ok2 and sw and sh then
            self:setX(0)
            self:setY(0)
            self:setWidth(sw)
            self:setHeight(sh)
            w, h = sw, sh
        end
    end

    if self.closeButton then
        self.closeButton:setX(w - CLOSE_BUTTON_SIZE - 2)
        self.closeButton:setY(2)
    end

    self.contentY = self.fullscreen and 0 or TITLE_BAR_HEIGHT
    self.contentHeight = h - self.contentY - (self.showStatusBar and STATUS_BAR_HEIGHT or 0)
    self.contentWidth = w
end

function Window:render()
    ISPanel.render(self)

    -- Guards against a subclass (or an unusual init order) reaching
    -- render() before layout() has ever run - contentY/contentHeight/
    -- contentWidth would otherwise be nil and every draw call below would
    -- error.
    if not self.contentHeight then self:layout() end

    local w, h = self:getWidth(), self:getHeight()
    local panelColor = paletteColor(self.palette, "panel")

    KeyasUI.rect(self, 0, self.contentY, w, self.contentHeight, panelColor)
    if not self.fullscreen then
        KeyasUI.bevel(self, 0, 0, w, h, true, self.palette)
        KeyasUI.titleBar(self, 0, 0, w, TITLE_BAR_HEIGHT, self.title, self.palette)
    end
    if self.showStatusBar then
        KeyasUI.statusBar(self, 0, h - STATUS_BAR_HEIGHT, w, STATUS_BAR_HEIGHT, self.statusText, self.palette)
    end

    if self.onRenderContent then
        self:onRenderContent(0, self.contentY, self.contentWidth, self.contentHeight)
    end
end

function Window:onCloseButtonClick()
    self:close()
end

--- Dragging: only the title bar area should move the window. ISPanel's
--- default onMouseDown starts a drag anywhere in the panel, so we narrow
--- it to the title strip and otherwise defer to the base implementation
--- (which still handles focus/click bookkeeping).
function Window:onMouseDown(x, y)
    if not self.fullscreen and y > TITLE_BAR_HEIGHT then
        self.moveWithMouse = false
        return ISPanel.onMouseDown(self, x, y)
    end
    self.moveWithMouse = not self.fullscreen
    return ISPanel.onMouseDown(self, x, y)
end

function Window:onMouseDownOutside(x, y)
    if self.closeOnClickOutside and not self.fullscreen then
        self:close()
    end
    if ISPanel.onMouseDownOutside then
        ISPanel.onMouseDownOutside(self, x, y)
    end
end

function Window:_onGlobalKeyPressed(key)
    if not self.closeOnEscape then return end
    if not self:getIsVisible() then return end
    local ok, escKey = pcall(function() return Keyboard.KEY_ESCAPE end)
    if ok and escKey and key == escKey then
        self:close()
    end
end

function Window:addToUIManager()
    ISPanel.addToUIManager(self)
    -- Bind once so removeListener in close() targets the exact same
    -- function reference. Events.OnKeyPressed fires on key-up, which is
    -- the same hook vanilla windows use for an Escape-to-close shortcut.
    self._keyHandler = function(key) self:_onGlobalKeyPressed(key) end
    local ok = pcall(function() Events.OnKeyPressed.Add(self._keyHandler) end)
    if not ok then dprint("KeyasUI.Window: could not register OnKeyPressed") end
end

--- Closes and fully detaches the window: removes it from the UI manager
--- and unregisters its global key listener so repeated open/close cycles
--- don't pile up dead handlers.
function Window:close()
    if self._keyHandler then
        pcall(function() Events.OnKeyPressed.Remove(self._keyHandler) end)
        self._keyHandler = nil
    end
    self:setVisible(false)
    self:removeFromUIManager()
end

return KeyasUI
