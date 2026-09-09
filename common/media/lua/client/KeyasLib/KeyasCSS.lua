-- KeyasCSS.lua
--
-- A small CSS-style layout + paint engine for Project Zomboid Build 42.
--
-- WHY THIS EXISTS
--   ISUI can fill rectangles, stretch textures and draw glyphs - nothing
--   else. No box model, no flexbox, no rounded corners, no gradients, no
--   shadows, no clipping worth the name. KeyasCSS adds all of that on top
--   of those primitives so a consumer mod can describe a panel the way it
--   would on the web - a tree of boxes with a stylesheet - and have it
--   laid out and drawn in-game, matching a design instead of approximating
--   it.
--
--   Rounded corners / borders / drop shadows are drawn by 9-slicing one
--   bundled atlas (media/ui/KeyasLib/keyas_ui_9slice.png, baked by
--   tools/nineslice_gen). Everything tints at draw time, so that one white
--   atlas covers every colour.
--
-- WHAT IT SUPPORTS (v1)
--   display: block | flex | none
--   flex-direction: row | column      gap: <px>
--   justify-content: flex-start | center | flex-end | space-between | space-around
--   align-items: flex-start | center | flex-end | stretch
--   flex-grow: <number>
--   width / height: <px> | <percent> | auto      min-/max-width/height: <px>
--   margin / padding (+ -top/-right/-bottom/-left): <px>
--   border: "<px> <style> <color>"  (or border-width / border-color)
--   border-radius: <px>
--   background-color / background: <color>
--   background-image: linear-gradient(<deg>, <color> <pct>, ...)   (square corners)
--   box-shadow: "<x> <y> <blur> <color>"
--   color: <color>        line-height: <px>        text-align: left|center|right
--   font: <id registered with KeyasUI.registerFont>   (KeyasCSS redefines
--         the `font` property to mean "which bitmap font", not the CSS shorthand)
--   opacity: <0..1>       overflow: hidden | visible
--
-- SELECTORS
--   tag, .class, #id, compounds (.a.b, div.card), descendant chains
--   (.list .row.sel), comma lists. Specificity 100/10/1 per id/class/tag.
--
-- NOT in v1 (documented so nobody hunts for a bug that's just a gap):
--   grid, position:absolute/fixed, transforms, transitions, calc(),
--   per-corner border-radius, rounded corners on gradient fills, child /
--   sibling combinators (> + ~), pseudo-classes. `align-items: stretch` on
--   an auto-height row leaves children at their natural height.
--
-- LOAD ORDER
--   KeyasLib / KeyasUI globals are only ever read inside function bodies
--   here, never at file scope - PZ loads every .lua independently and
--   alphabetically (see KeyasLib.lua's header).

require "ISUI/ISPanel"

KeyasCSS = KeyasCSS or {}

local function dprint(...)
    if KeyasLib and KeyasLib.debugPrint then KeyasLib.debugPrint(...) end
end

--============================================================
-- Colours
--============================================================

local NAMED = {
    transparent = {r = 0, g = 0, b = 0, a = 0},
    black = {r = 0, g = 0, b = 0, a = 1},
    white = {r = 1, g = 1, b = 1, a = 1},
    red = {r = 0.8, g = 0.1, b = 0.1, a = 1},
    green = {r = 0.1, g = 0.7, b = 0.2, a = 1},
    blue = {r = 0.2, g = 0.4, b = 0.9, a = 1},
    gray = {r = 0.5, g = 0.5, b = 0.5, a = 1},
    grey = {r = 0.5, g = 0.5, b = 0.5, a = 1},
}

--- Normalises anything colour-ish to {r,g,b,a} in 0..1.
--- Accepts: a table (passed through, defaults a=1), "#rgb", "#rgba",
--- "#rrggbb", "#rrggbbaa", "rgb(r,g,b)", "rgba(r,g,b,a)" (channels 0..255,
--- alpha 0..1), or a handful of named colours. nil -> nil.
function KeyasCSS.color(v)
    if v == nil then return nil end
    if type(v) == "table" then
        return {r = v.r or 0, g = v.g or 0, b = v.b or 0, a = v.a == nil and 1 or v.a}
    end
    if type(v) ~= "string" then return nil end
    local s = v:match("^%s*(.-)%s*$"):lower()
    if NAMED[s] then
        local c = NAMED[s]; return {r = c.r, g = c.g, b = c.b, a = c.a}
    end
    local hex = s:match("^#([%x]+)$")
    if hex then
        local function h2(a, b) return tonumber(a .. b, 16) / 255 end
        if #hex == 3 then
            return {r = tonumber(hex:sub(1,1)..hex:sub(1,1),16)/255,
                    g = tonumber(hex:sub(2,2)..hex:sub(2,2),16)/255,
                    b = tonumber(hex:sub(3,3)..hex:sub(3,3),16)/255, a = 1}
        elseif #hex == 4 then
            return {r = tonumber(hex:sub(1,1)..hex:sub(1,1),16)/255,
                    g = tonumber(hex:sub(2,2)..hex:sub(2,2),16)/255,
                    b = tonumber(hex:sub(3,3)..hex:sub(3,3),16)/255,
                    a = tonumber(hex:sub(4,4)..hex:sub(4,4),16)/255}
        elseif #hex == 6 then
            return {r = h2(hex:sub(1,1),hex:sub(2,2)), g = h2(hex:sub(3,3),hex:sub(4,4)),
                    b = h2(hex:sub(5,5),hex:sub(6,6)), a = 1}
        elseif #hex == 8 then
            return {r = h2(hex:sub(1,1),hex:sub(2,2)), g = h2(hex:sub(3,3),hex:sub(4,4)),
                    b = h2(hex:sub(5,5),hex:sub(6,6)), a = h2(hex:sub(7,7),hex:sub(8,8))}
        end
        return nil
    end
    local rgb = s:match("^rgba?%((.+)%)$")
    if rgb then
        local parts = {}
        for n in rgb:gmatch("[^,]+") do parts[#parts + 1] = tonumber((n:gsub("%s", ""))) end
        if #parts >= 3 then
            return {r = (parts[1] or 0)/255, g = (parts[2] or 0)/255,
                    b = (parts[3] or 0)/255, a = parts[4] == nil and 1 or parts[4]}
        end
    end
    return nil
end

local function mixColor(c1, c2, t)
    return {r = c1.r + (c2.r - c1.r) * t,
            g = c1.g + (c2.g - c1.g) * t,
            b = c1.b + (c2.b - c1.b) * t,
            a = (c1.a or 1) + ((c2.a or 1) - (c1.a or 1)) * t}
end

--============================================================
-- linear-gradient parsing
--   "linear-gradient(180deg, #111 0%, #333 100%)"
--   -> { angle = 180, stops = { {color = {...}, at = 0}, {color = {...}, at = 1} } }
--============================================================

local function parseGradient(str)
    if type(str) == "table" then
        -- already a gradient object; just normalise stop colours
        local g = {angle = str.angle or 180, stops = {}}
        for i, st in ipairs(str.stops or {}) do
            g.stops[i] = {color = KeyasCSS.color(st.color) or {r=0,g=0,b=0,a=1},
                          at = st.at}
        end
        return g
    end
    if type(str) ~= "string" then return nil end
    local inner = str:match("linear%-gradient%s*%((.+)%)")
    if not inner then return nil end
    local parts = {}
    -- split on commas that aren't inside parentheses (rgba(...))
    local depth, buf = 0, ""
    for i = 1, #inner do
        local ch = inner:sub(i, i)
        if ch == "(" then depth = depth + 1; buf = buf .. ch
        elseif ch == ")" then depth = depth - 1; buf = buf .. ch
        elseif ch == "," and depth == 0 then parts[#parts + 1] = buf; buf = ""
        else buf = buf .. ch end
    end
    if buf ~= "" then parts[#parts + 1] = buf end

    local angle = 180
    local first = parts[1] and parts[1]:match("^%s*(.-)%s*$") or ""
    local startIdx = 1
    local deg = first:match("^(%-?%d+%.?%d*)deg$")
    if deg then angle = tonumber(deg); startIdx = 2
    elseif first == "to bottom" then angle = 180; startIdx = 2
    elseif first == "to top" then angle = 0; startIdx = 2
    elseif first == "to right" then angle = 90; startIdx = 2
    elseif first == "to left" then angle = 270; startIdx = 2 end

    local stops = {}
    for i = startIdx, #parts do
        local seg = parts[i]:match("^%s*(.-)%s*$")
        local pct = seg:match("(%-?%d+%.?%d*)%%%s*$")
        local colStr = pct and seg:gsub("%s*%-?%d+%.?%d*%%%s*$", "") or seg
        local col = KeyasCSS.color(colStr)
        if col then
            stops[#stops + 1] = {color = col, at = pct and (tonumber(pct) / 100) or nil}
        end
    end
    if #stops < 2 then return nil end
    -- fill in missing stop positions evenly
    if stops[1].at == nil then stops[1].at = 0 end
    if stops[#stops].at == nil then stops[#stops].at = 1 end
    for i = 2, #stops - 1 do
        if stops[i].at == nil then
            stops[i].at = stops[1].at + (stops[#stops].at - stops[1].at) * (i - 1) / (#stops - 1)
        end
    end
    return {angle = angle, stops = stops}
end

local function colorAt(grad, t)
    local stops = grad.stops
    if t <= stops[1].at then return stops[1].color end
    if t >= stops[#stops].at then return stops[#stops].color end
    for i = 1, #stops - 1 do
        local a, b = stops[i], stops[i + 1]
        if t >= a.at and t <= b.at then
            local span = (b.at - a.at)
            local lt = span > 0 and (t - a.at) / span or 0
            return mixColor(a.color, b.color, lt)
        end
    end
    return stops[#stops].color
end

--============================================================
-- box-shadow parsing:  "<x>px <y>px <blur>px <color>"
--============================================================

local function parseShadow(str)
    if type(str) == "table" then return str end
    if type(str) ~= "string" or str:match("^%s*none%s*$") then return nil end
    -- pull the colour off the end first (it may contain spaces: rgba(...))
    local colStr = str:match("(#%x+)%s*$")
                or str:match("(rgba?%([^)]*%))%s*$")
                or str:match("(%a+)%s*$")
    local nums = {}
    for n in str:gmatch("%-?%d+%.?%d*") do nums[#nums + 1] = tonumber(n) end
    return {
        x = nums[1] or 0, y = nums[2] or 0, blur = nums[3] or 0,
        color = KeyasCSS.color(colStr) or {r = 0, g = 0, b = 0, a = 0.5},
    }
end

--============================================================
-- 9-slice atlas
--============================================================

local ATLAS_PATH = "media/ui/KeyasLib/keyas_ui_9slice.png"
local ROUND  = {sx = 0,  sy = 0, s = 64, corner = 20}  -- must match generate_nineslice.ps1 -Radius
local SHADOW = {sx = 64, sy = 0, s = 64, corner = 28}  -- generous corner: captures the blur falloff

local _atlasTex, _atlasTried = nil, false
local function atlas()
    if not _atlasTried then
        _atlasTried = true
        local ok, tex = pcall(getTexture, ATLAS_PATH)
        if ok and tex then _atlasTex = tex
        else print("[KeyasCSS] ERROR: 9-slice atlas failed to load: " .. ATLAS_PATH .. " (rounded corners/shadows fall back to plain rects)") end
    end
    return _atlasTex
end

--- Draws `blk` (ROUND or SHADOW) 9-sliced into the dst rect, tinted `col`,
--- with destination corner size `cornerDst` (px). Falls back to a flat
--- rect if the atlas didn't load.
local function nineSlice(owner, blk, x, y, w, h, cornerDst, col)
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
    if w <= 0 or h <= 0 then return end
    local a = col.a == nil and 1 or col.a
    if a <= 0 then return end
    local r, g, b = col.r, col.g, col.b
    local tex = atlas()
    if not tex then
        pcall(owner.drawRect, owner, x, y, w, h, a, r, g, b)
        return
    end
    local cs = blk.corner
    local cd = math.min(cornerDst or cs, math.floor(w / 2), math.floor(h / 2))
    if cd < 0 then cd = 0 end
    local sx, sy, s = blk.sx, blk.sy, blk.s
    local midSX, midSW = sx + cs, s - 2 * cs
    local midSY, midSH = sy + cs, s - 2 * cs

    local function sub(ssx, ssy, ssw, ssh, dx, dy, dw, dh)
        if dw <= 0 or dh <= 0 or ssw <= 0 or ssh <= 0 then return end
        pcall(owner.drawSubTexture, owner, tex, ssx, ssy, ssw, ssh, dx, dy, dw, dh, a, r, g, b)
    end

    -- corners
    sub(sx,          sy,          cs, cs, x,          y,          cd, cd)
    sub(sx + s - cs, sy,          cs, cs, x + w - cd, y,          cd, cd)
    sub(sx,          sy + s - cs, cs, cs, x,          y + h - cd, cd, cd)
    sub(sx + s - cs, sy + s - cs, cs, cs, x + w - cd, y + h - cd, cd, cd)
    -- edges
    sub(midSX,       sy,          midSW, cs, x + cd,     y,          w - 2 * cd, cd)
    sub(midSX,       sy + s - cs, midSW, cs, x + cd,     y + h - cd, w - 2 * cd, cd)
    sub(sx,          midSY,       cs, midSH, x,          y + cd,     cd,         h - 2 * cd)
    sub(sx + s - cs, midSY,       cs, midSH, x + w - cd, y + cd,     cd,         h - 2 * cd)
    -- centre
    sub(midSX,       midSY,       midSW, midSH, x + cd, y + cd, w - 2 * cd, h - 2 * cd)
end

--- Public: a rounded (or square, radius 0) filled rect.
function KeyasCSS.roundedRect(owner, x, y, w, h, radius, color)
    color = KeyasCSS.color(color) or {r = 0, g = 0, b = 0, a = 1}
    if not radius or radius <= 0 then
        pcall(owner.drawRect, owner, math.floor(x), math.floor(y), math.floor(w), math.floor(h),
              color.a == nil and 1 or color.a, color.r, color.g, color.b)
        return
    end
    nineSlice(owner, ROUND, x, y, w, h, radius, color)
end

--- Public: a soft drop shadow for the rect (x,y,w,h). `sh` = {x,y,blur,color}.
function KeyasCSS.dropShadow(owner, x, y, w, h, radius, sh)
    if not sh then return end
    local blur = math.max(1, sh.blur or 0)
    nineSlice(owner, SHADOW,
        x + (sh.x or 0) - blur, y + (sh.y or 0) - blur,
        w + blur * 2, h + blur * 2,
        (radius or 0) + blur, sh.color or {r = 0, g = 0, b = 0, a = 0.5})
end

--- Public: axis-aligned linear-gradient fill (square corners). `grad` is a
--- string or a {angle, stops} table. Rendered as N tinted bands.
function KeyasCSS.gradientRect(owner, x, y, w, h, grad)
    grad = parseGradient(grad)
    if not grad then return end
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
    if w <= 0 or h <= 0 then return end
    -- snap to the nearest axis; diagonal gradients aren't worth the fill cost here
    local ang = ((grad.angle or 180) % 360 + 360) % 360
    local horizontal = (ang >= 45 and ang < 135) or (ang >= 225 and ang < 315)
    local reversed = (ang >= 135 and ang < 315)
    local BANDS = 48
    if horizontal then
        local bw = w / BANDS
        for i = 0, BANDS - 1 do
            local t = (i + 0.5) / BANDS
            local c = colorAt(grad, reversed and (1 - t) or t)
            local bx = x + math.floor(i * bw)
            local bx2 = x + math.floor((i + 1) * bw)
            pcall(owner.drawRect, owner, bx, y, math.max(1, bx2 - bx), h, c.a == nil and 1 or c.a, c.r, c.g, c.b)
        end
    else
        local bh = h / BANDS
        for i = 0, BANDS - 1 do
            local t = (i + 0.5) / BANDS
            local c = colorAt(grad, reversed and (1 - t) or t)
            local by = y + math.floor(i * bh)
            local by2 = y + math.floor((i + 1) * bh)
            pcall(owner.drawRect, owner, x, by, w, math.max(1, by2 - by), c.a == nil and 1 or c.a, c.r, c.g, c.b)
        end
    end
end

--============================================================
-- Stylesheet parsing
--============================================================

-- kebab-case CSS name -> the internal camelCase key used on computed style
local PROP_ALIAS = {
    ["background"] = "backgroundColor",
    ["background-color"] = "backgroundColor",
    ["background-image"] = "backgroundImage",
    ["border-radius"] = "borderRadius",
    ["border-color"] = "borderColor",
    ["border-width"] = "borderWidth",
    ["box-shadow"] = "boxShadow",
    ["flex-direction"] = "flexDirection",
    ["flex-grow"] = "flexGrow",
    ["justify-content"] = "justifyContent",
    ["align-items"] = "alignItems",
    ["line-height"] = "lineHeight",
    ["text-align"] = "textAlign",
    ["min-width"] = "minWidth",
    ["max-width"] = "maxWidth",
    ["min-height"] = "minHeight",
    ["max-height"] = "maxHeight",
}

local function canonProp(name)
    name = name:match("^%s*(.-)%s*$"):lower()
    return PROP_ALIAS[name] or name:gsub("%-(%l)", function(c) return c:upper() end)
end

--- Expands the few shorthands we accept into the longhand keys the layout
--- and paint code actually reads. Mutates `into`.
local function applyDecl(into, rawName, rawValue)
    local name = canonProp(rawName)
    local value = rawValue:match("^%s*(.-)%s*$")

    if name == "margin" or name == "padding" then
        local nums = {}
        for n in value:gmatch("%-?%d+%.?%d*") do nums[#nums + 1] = tonumber(n) end
        local t, r, b, l
        if #nums == 1 then t, r, b, l = nums[1], nums[1], nums[1], nums[1]
        elseif #nums == 2 then t, r, b, l = nums[1], nums[2], nums[1], nums[2]
        elseif #nums == 3 then t, r, b, l = nums[1], nums[2], nums[3], nums[2]
        elseif #nums >= 4 then t, r, b, l = nums[1], nums[2], nums[3], nums[4] end
        if t then
            into[name .. "Top"] = t; into[name .. "Right"] = r
            into[name .. "Bottom"] = b; into[name .. "Left"] = l
        end
        return
    end

    if name == "border" then
        local px = value:match("(%d+%.?%d*)px") or value:match("^(%d+%.?%d*)%s")
        if px then into.borderWidth = tonumber(px) end
        local col = value:match("(#%x+)") or value:match("(rgba?%([^)]*%))")
                 or value:match("(%a+)%s*$")
        if col and col ~= "solid" and col ~= "none" then
            into.borderColor = KeyasCSS.color(col)
        end
        return
    end

    -- direct value props
    if name == "backgroundColor" then
        if value:match("linear%-gradient") then into.backgroundImage = value
        else into.backgroundColor = KeyasCSS.color(value) end
    elseif name == "backgroundImage" then
        into.backgroundImage = value
    elseif name == "borderColor" then into.borderColor = KeyasCSS.color(value)
    elseif name == "color" then into.color = KeyasCSS.color(value)
    elseif name == "boxShadow" then into.boxShadow = value
    elseif name == "borderWidth" or name == "borderRadius" or name == "gap"
        or name == "flexGrow" or name == "opacity" or name == "lineHeight"
        or name == "minWidth" or name == "maxWidth" or name == "minHeight" or name == "maxHeight" then
        into[name] = tonumber((value:gsub("px", "")))
    elseif name == "width" or name == "height" then
        into[name] = value  -- kept as string: "auto" | "50%" | "120" | "120px"
    else
        into[name] = value  -- display, flexDirection, justifyContent, alignItems, textAlign, font, overflow, position
    end
end

-- Declaration keys that are pixel lengths (scaled by opts.scale in parse).
-- Percentages, "auto", colours, gradients and unit-less numbers (flexGrow,
-- opacity) are deliberately left alone.
local SCALABLE_PX = {
    gap = true, borderWidth = true, borderRadius = true, lineHeight = true,
    minWidth = true, maxWidth = true, minHeight = true, maxHeight = true,
    marginTop = true, marginRight = true, marginBottom = true, marginLeft = true,
    paddingTop = true, paddingRight = true, paddingBottom = true, paddingLeft = true,
}

local function scaleDecls(decls, k)
    for key, v in pairs(decls) do
        if SCALABLE_PX[key] and type(v) == "number" then
            decls[key] = v * k
        elseif (key == "width" or key == "height") and type(v) == "string"
            and not v:find("%%") and v ~= "auto" then
            local n = tonumber((v:gsub("px", "")))
            if n then decls[key] = tostring(n * k) end
        elseif key == "boxShadow" then
            local sh = parseShadow(v)
            if sh then
                sh.x, sh.y, sh.blur = (sh.x or 0) * k, (sh.y or 0) * k, (sh.blur or 0) * k
                decls[key] = sh  -- parseShadow() later passes a table straight through
            end
        end
    end
end

-- A "compound" is one or more simple selectors that must all match the same
-- node: `.a.b`, `div.card`, `#id.on`. A full selector is a whitespace-
-- separated chain of compounds (descendant combinator): `.list .row.sel`.
-- The last compound is the subject; the earlier ones must each match some
-- ancestor, in order. No `>` / `+` / `~` combinators, no pseudo-classes.
local function parseCompound(str)
    if str == "*" then return {{kind = "any"}} end
    local simples = {}
    local tag = str:match("^([%a][%w_-]*)")
    if tag then simples[#simples + 1] = {kind = "tag", name = tag:lower()} end
    for mark, nm in str:gmatch("([.#])([%w_-]+)") do
        simples[#simples + 1] = {kind = mark == "#" and "id" or "class", name = nm}
    end
    if #simples == 0 then simples[1] = {kind = "any"} end
    return simples
end

--- Parses a CSS string into a stylesheet object. Selectors: `tag`,
--- `.class`, `#id`, compounds (`.a.b`, `div.card`), descendant chains
--- (`.list .row`), and comma-separated lists of those. Specificity is the
--- usual 100/10/1 per id/class/tag summed over the whole selector, source
--- order breaking ties.
---
--- @param opts table optional { scale = <number> } - multiplies every px
---   length in the sheet, so you can author at 1x and render at any
---   resolution (percentages, `auto` and colours are untouched). Inline
---   `style` on a node is NOT scaled - keep sizing in the sheet.
function KeyasCSS.parse(css, opts)
    local k = opts and tonumber(opts.scale) or 1
    local rules = {}
    css = css:gsub("/%*.-%*/", "")  -- strip comments
    for selectorList, body in css:gmatch("([^{}]+)%s*{(.-)}") do
        local decls = {}
        for prop, val in body:gmatch("([%w%-]+)%s*:%s*([^;]+)") do
            applyDecl(decls, prop, val)
        end
        if k ~= 1 then scaleDecls(decls, k) end
        for sel in selectorList:gmatch("[^,]+") do
            sel = sel:match("^%s*(.-)%s*$")
            if sel ~= "" then
                local compounds, spec = {}, 0
                for part in sel:gmatch("%S+") do
                    local simples = parseCompound(part)
                    compounds[#compounds + 1] = simples
                    for _, s in ipairs(simples) do
                        if s.kind == "id" then spec = spec + 100
                        elseif s.kind == "class" then spec = spec + 10
                        elseif s.kind == "tag" then spec = spec + 1 end
                    end
                end
                if #compounds > 0 then
                    rules[#rules + 1] = {compounds = compounds, spec = spec, order = #rules, decls = decls}
                end
            end
        end
    end
    return {rules = rules, scale = k}
end

local function simpleMatches(s, node)
    if s.kind == "any" then return true end
    if s.kind == "id" then return node.id == s.name end
    if s.kind == "tag" then return (node.tag or "div") == s.name end
    if s.kind == "class" then
        if not node.class then return false end
        for c in node.class:gmatch("%S+") do if c == s.name then return true end end
        return false
    end
    return false
end

local function compoundMatches(cmp, node)
    for _, s in ipairs(cmp) do
        if not simpleMatches(s, node) then return false end
    end
    return true
end

--- @param ancestors array of nodes, root first, parent last (may be nil)
local function ruleMatches(rule, node, ancestors)
    local comps = rule.compounds
    if not compoundMatches(comps[#comps], node) then return false end
    if #comps == 1 then return true end
    local ai = ancestors and #ancestors or 0
    for ci = #comps - 1, 1, -1 do
        local matched = false
        while ai >= 1 do
            local anc = ancestors[ai]
            ai = ai - 1
            if compoundMatches(comps[ci], anc) then matched = true; break end
        end
        if not matched then return false end
    end
    return true
end

--============================================================
-- Node tree
--============================================================

local Node = {}
Node.__index = Node
KeyasCSS.Node = Node

--- def = {
---   tag = "div", class = "row card", id = "hdr",
---   style = { ... camelCase or kebab keys ... },
---   text = "literal string",
---   children = { <node or def>, ... },
---   onClick = function(node, surface) end,
---   onPaint = function(node, owner, x, y, w, h, opacity) end,  -- content box, local coords
---   key = <any> (opaque, for the consumer's own bookkeeping),
--- }
function KeyasCSS.node(def)
    def = def or {}
    local o = setmetatable({}, Node)
    o.tag = def.tag or "div"
    o.class = def.class
    o.id = def.id
    o.text = def.text
    o.onClick = def.onClick
    o.onPaint = def.onPaint
    o.key = def.key
    o.rawStyle = def.style or {}
    o.children = {}
    for _, ch in ipairs(def.children or {}) do
        o.children[#o.children + 1] = getmetatable(ch) == Node and ch or KeyasCSS.node(ch)
    end
    o.computed = {}
    o.box = {x = 0, y = 0, w = 0, h = 0, cx = 0, cy = 0, cw = 0, ch = 0}
    return o
end

local DEFAULTS = {
    display = "block", flexDirection = "row", gap = 0,
    justifyContent = "flex-start", alignItems = "stretch",
    marginTop = 0, marginRight = 0, marginBottom = 0, marginLeft = 0,
    paddingTop = 0, paddingRight = 0, paddingBottom = 0, paddingLeft = 0,
    borderWidth = 0, borderRadius = 0, flexGrow = 0, opacity = 1,
    width = "auto", height = "auto", textAlign = "left", overflow = "visible",
}

--- Merges DEFAULTS < matching stylesheet rules (by specificity, then order)
--- < inline style, into node.computed. Recurses to children, threading the
--- ancestor chain so descendant selectors can be evaluated.
--- @param ancestors internal - array of ancestor nodes, root first (nil at the top call)
function Node:resolve(stylesheet, ancestors)
    ancestors = ancestors or {}
    local c = {}
    for k, v in pairs(DEFAULTS) do c[k] = v end

    if stylesheet then
        local matched = {}
        for _, rule in ipairs(stylesheet.rules) do
            if ruleMatches(rule, self, ancestors) then matched[#matched + 1] = rule end
        end
        table.sort(matched, function(a, b)
            if a.spec ~= b.spec then return a.spec < b.spec end
            return a.order < b.order
        end)
        for _, rule in ipairs(matched) do
            for k, v in pairs(rule.decls) do c[k] = v end
        end
    end

    -- inline style wins; accept camelCase or kebab keys
    for k, v in pairs(self.rawStyle) do
        local key = canonProp(k)
        if key == "backgroundColor" or key == "borderColor" or key == "color" then
            c[key] = KeyasCSS.color(v)
        elseif key == "margin" or key == "padding" or key == "border" then
            applyDecl(c, k, tostring(v))
        else
            c[key] = v
        end
    end

    -- normalise colour-ish fields that might still be strings
    for _, k in ipairs({"backgroundColor", "borderColor", "color"}) do
        if type(c[k]) == "string" then c[k] = KeyasCSS.color(c[k]) end
    end
    c.gradient = c.backgroundImage and parseGradient(c.backgroundImage) or nil
    c.shadow = c.boxShadow and parseShadow(c.boxShadow) or nil

    self.computed = c
    ancestors[#ancestors + 1] = self
    for _, ch in ipairs(self.children) do ch:resolve(stylesheet, ancestors) end
    ancestors[#ancestors] = nil
end

--============================================================
-- Layout
--============================================================

local function lenPx(v, basis)
    if v == nil or v == "auto" then return nil end
    if type(v) == "number" then return v end
    local pct = v:match("^(%-?%d+%.?%d*)%%$")
    if pct then return (tonumber(pct) / 100) * (basis or 0) end
    local n = v:match("^(%-?%d+%.?%d*)")
    return n and tonumber(n) or nil
end

local function clamp(v, lo, hi)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

local function visibleChildren(node)
    local out = {}
    for _, ch in ipairs(node.children) do
        if (ch.computed.display or "block") ~= "none" then out[#out + 1] = ch end
    end
    return out
end

-- forward decl
local layoutNode

--- Intrinsic main-axis size of a node before flex-grow, given the cross
--- size available. Used to seed flex distribution and block auto-height.
local function intrinsicMain(node, dir, crossAvail)
    local c = node.computed
    local explicit = lenPx(dir == "row" and c.width or c.height,
                           dir == "row" and crossAvail or nil)
    if explicit then
        local pad = dir == "row" and (c.paddingLeft + c.paddingRight) or (c.paddingTop + c.paddingBottom)
        local bd = 2 * c.borderWidth
        return explicit + 0  -- width/height are border-box here
    end
    -- lay it out in a throwaway pass to measure
    local probeW = dir == "row" and 100000 or (crossAvail or 0)
    local probeH = dir == "row" and (crossAvail or 0) or 100000
    layoutNode(node, 0, 0, probeW, probeH, true)
    if dir == "row" then
        -- never let an auto-width child claim more main axis than the
        -- container offers - keeps a stray auto-width div from crowding out
        -- its siblings. (Only meaningful on the row axis; a column's main
        -- axis is height and isn't bounded by the cross width.)
        local m = node.box.w
        if crossAvail and crossAvail > 0 then m = math.min(m, crossAvail) end
        return m
    end
    return node.box.h
end

--- Lays a node (and its subtree) into the margin-box origin (ox, oy) with
--- (availW, availH) offered for its margin box. `measuring` suppresses the
--- flex-grow / justify distribution that needs a final size.
--- Fills node.box: outer x/y/w/h (border box) and cx/cy/cw/ch (content box).
layoutNode = function(node, ox, oy, availW, availH, measuring)
    local c = node.computed
    local mL, mR = c.marginLeft, c.marginRight
    local mT, mB = c.marginTop, c.marginBottom
    local pL, pR, pT, pB = c.paddingLeft, c.paddingRight, c.paddingTop, c.paddingBottom
    local bd = c.borderWidth

    local kids = visibleChildren(node)
    local isTextLeaf = (#kids == 0 and node.text ~= nil and node.text ~= "")

    -- border-box width
    local w = lenPx(c.width, availW)
    if w == nil then
        if isTextLeaf and measuring then
            -- Intrinsic-measurement pass only: shrink-wrap a text leaf to
            -- its longest unwrapped line so a flex-row sibling can size to
            -- content. In a real (non-measuring) pass a text leaf fills its
            -- available width and wraps, like a block <div>.
            local longest = 0
            for _, ln in ipairs(KeyasCSS._wrapLines(node.text, math.huge, c.font)) do
                longest = math.max(longest, (KeyasCSS._measure(ln, c.font)))
            end
            w = math.min(math.max(0, availW - mL - mR), longest + 2 * bd + pL + pR)
        else
            w = math.max(0, availW - mL - mR)      -- auto: fill
        end
    end
    w = clamp(w, lenPx(c.minWidth), lenPx(c.maxWidth))

    local cw = math.max(0, w - 2 * bd - pL - pR)   -- content width
    local contentH                                  -- natural content-box height from children/text
    local bx = ox + mL
    local by = oy + mT
    local inX = bx + bd + pL
    local inY = by + bd + pT

    if #kids == 0 then
        -- text node (or empty box)
        if node.text and node.text ~= "" then
            local lh = c.lineHeight or select(2, KeyasCSS._measure("Mg", c.font)) or 14
            local lines = KeyasCSS._wrapLines(node.text, cw, c.font)
            node._lines = lines
            node._lineH = lh
            contentH = #lines * lh
        else
            contentH = 0
        end
    elseif c.display == "flex" then
        local dir = c.flexDirection == "column" and "column" or "row"
        local gap = c.gap or 0
        local mainAvail = dir == "row" and cw or (lenPx(c.height, availH)
            and (lenPx(c.height, availH) - 2 * bd - pT - pB) or nil)
        -- 1. base main sizes. A child with flex-grow > 0 and no explicit
        --    main size starts from 0 (like CSS `flex: 1` -> flex-basis 0):
        --    it is sized entirely by the free-space distribution below, so
        --    it fills the leftover instead of measuring its content as its
        --    base (which would overflow the row).
        local bases, grows, totalBase, totalGrow = {}, {}, 0, 0
        for i, ch in ipairs(kids) do
            local grow = tonumber(ch.computed.flexGrow) or 0
            local explicitMain = lenPx(dir == "row" and ch.computed.width or ch.computed.height,
                                       dir == "row" and cw or nil)
            local b
            if explicitMain then b = explicitMain
            elseif grow > 0 then b = 0
            else b = intrinsicMain(ch, dir, cw) end
            bases[i] = b
            grows[i] = grow
            totalBase = totalBase + b
            totalGrow = totalGrow + grow
        end
        local freeMain
        if dir == "row" then
            freeMain = cw - totalBase - gap * math.max(0, #kids - 1)
        else
            local avail = mainAvail or (totalBase + gap * math.max(0, #kids - 1))
            freeMain = avail - totalBase - gap * math.max(0, #kids - 1)
        end
        -- 2. distribute
        local sizes = {}
        for i = 1, #kids do
            if totalGrow > 0 and freeMain > 0 then
                sizes[i] = bases[i] + freeMain * (grows[i] / totalGrow)
            else
                sizes[i] = bases[i]
            end
        end
        -- 3. justify (only when not growing to fill)
        local usedMain = 0
        for i = 1, #kids do usedMain = usedMain + sizes[i] end
        usedMain = usedMain + gap * math.max(0, #kids - 1)
        local mainSpan = dir == "row" and cw or (mainAvail or usedMain)
        local slack = math.max(0, mainSpan - usedMain)
        local cursor = 0
        local between = gap
        if totalGrow == 0 then
            if c.justifyContent == "center" then cursor = slack / 2
            elseif c.justifyContent == "flex-end" then cursor = slack
            elseif c.justifyContent == "space-between" and #kids > 1 then
                between = gap + slack / (#kids - 1)
            elseif c.justifyContent == "space-around" and #kids > 0 then
                between = gap + slack / #kids
                cursor = (slack / #kids) / 2
            end
        end
        -- 4. place each child along the main axis at its natural cross size,
        --    tracking the largest cross extent...
        local rowCrossAvail  -- known cross size for a row = explicit height; nil until measured
        if dir == "row" then
            local eh = lenPx(c.height, availH)
            if eh then rowCrossAvail = eh - 2 * bd - pT - pB end
        end
        local placed = {}       -- {node, mainPos, crossMbSize}
        local maxCross = 0
        for i, ch in ipairs(kids) do
            local chC = ch.computed
            local childMain = sizes[i]
            local crossExplicit = lenPx(dir == "row" and chC.height or chC.width,
                                        dir == "row" and (rowCrossAvail) or cw)
            -- stretch (the default): fill the cross axis when it's known
            local stretch = (c.alignItems == "stretch") and not crossExplicit
            local childCross = crossExplicit
            if stretch then
                if dir == "row" then childCross = rowCrossAvail  -- may be nil -> natural, aligned as flex-start
                else childCross = cw end
            end

            if dir == "row" then
                layoutNode(ch, inX + cursor, inY, childMain, childCross or math.huge, measuring)
                local mb = ch.box.h + chC.marginTop + chC.marginBottom
                placed[i] = {node = ch, cross = mb}
                maxCross = math.max(maxCross, mb)
                cursor = cursor + ch.box.w + chC.marginLeft + chC.marginRight + between
            else
                layoutNode(ch, inX, inY + cursor, childCross or cw, childMain, measuring)
                local mb = ch.box.w + chC.marginLeft + chC.marginRight
                local slack = cw - mb
                if c.alignItems == "center" then ch:_shift(slack / 2, 0)
                elseif c.alignItems == "flex-end" then ch:_shift(slack, 0) end
                maxCross = math.max(maxCross, mb)
                cursor = cursor + ch.box.h + chC.marginTop + chC.marginBottom + between
            end
        end

        if dir == "row" then
            -- ...then, now that the row's cross extent is known, align each
            --    child within it (skip for stretch with an unknown height -
            --    those stay top-aligned at natural height, a v1 limitation).
            local crossExtent = rowCrossAvail or maxCross
            for _, p in ipairs(placed) do
                local slack = crossExtent - p.cross
                if slack ~= 0 then
                    if c.alignItems == "center" then p.node:_shift(0, slack / 2)
                    elseif c.alignItems == "flex-end" then p.node:_shift(0, slack) end
                end
            end
            contentH = crossExtent
        else
            contentH = cursor - between  -- last `between` overshoots
            if #kids == 0 then contentH = 0 end
        end
    else
        -- block flow: stack vertically, each child gets full content width
        local yy = inY
        local maxChildW = 0
        for _, ch in ipairs(kids) do
            local chC = ch.computed
            layoutNode(ch, inX, yy, cw, math.huge, measuring)
            yy = yy + ch.box.h + chC.marginTop + chC.marginBottom
            maxChildW = math.max(maxChildW, ch.box.w)
        end
        contentH = yy - inY
    end

    -- border-box height
    local h = lenPx(c.height, availH)
    if h == nil then
        h = contentH + 2 * bd + pT + pB
    end
    h = clamp(h, lenPx(c.minHeight), lenPx(c.maxHeight))

    node.box.x, node.box.y, node.box.w, node.box.h = bx, by, w, h
    node.box.cx, node.box.cy = bx + bd + pL, by + bd + pT
    node.box.cw, node.box.ch = cw, math.max(0, h - 2 * bd - pT - pB)
end

--- Shifts this node's whole laid-out subtree by (dx, dy). Used by flex
--- cross-axis alignment after a child has been realised at origin.
function Node:_shift(dx, dy)
    if dx == 0 and dy == 0 then return end
    local b = self.box
    b.x, b.y, b.cx, b.cy = b.x + dx, b.y + dy, b.cx + dx, b.cy + dy
    for _, ch in ipairs(self.children) do ch:_shift(dx, dy) end
end

--- Public entry: lay the tree into (x, y, w, h).
function Node:layout(x, y, w, h)
    layoutNode(self, x, y, w, h, false)
end

--============================================================
-- Text measuring / wrapping (delegates to KeyasUI's bitmap fonts,
-- falls back to the vanilla text manager)
--============================================================

function KeyasCSS._measure(str, fontId)
    if KeyasUI and KeyasUI.measure and fontId then
        local ok, w, lh = pcall(KeyasUI.measure, str, fontId)
        if ok then return w, lh end
    end
    local w, h = 0, 14
    pcall(function() w = getTextManager():MeasureStringX(UIFont.Small, str) end)
    pcall(function() h = getTextManager():getFontHeight(UIFont.Small) end)
    return w, h
end

function KeyasCSS._wrapLines(str, maxW, fontId)
    local lines = {}
    for paragraph in tostring(str):gmatch("([^\n]*)\n?") do
        if paragraph == "" then
            lines[#lines + 1] = ""
        else
            local cur = ""
            for word in paragraph:gmatch("%S+") do
                local cand = (cur == "") and word or (cur .. " " .. word)
                local w = KeyasCSS._measure(cand, fontId)
                if w > maxW and cur ~= "" then
                    lines[#lines + 1] = cur
                    cur = word
                else
                    cur = cand
                end
            end
            if cur ~= "" then lines[#lines + 1] = cur end
        end
    end
    if #lines == 0 then lines[1] = "" end
    return lines
end

local function drawText(owner, str, x, y, color, fontId)
    color = color or {r = 1, g = 1, b = 1, a = 1}
    if KeyasUI and KeyasUI.text and fontId then
        local ok = pcall(KeyasUI.text, owner, str, x, y, color, fontId)
        if ok then return end
    end
    pcall(owner.drawText, owner, str, x, y, color.r, color.g, color.b, color.a == nil and 1 or color.a, UIFont.Small)
end

--============================================================
-- Paint
--============================================================

local function withAlpha(color, mul)
    if not color then return nil end
    return {r = color.r, g = color.g, b = color.b, a = (color.a == nil and 1 or color.a) * mul}
end

--- Paints this node and its subtree. `parentOpacity` cascades multiplicatively.
function Node:paint(owner, parentOpacity)
    local c = self.computed
    local op = (parentOpacity or 1) * (tonumber(c.opacity) or 1)
    if op <= 0 then return end
    local b = self.box
    local radius = c.borderRadius or 0

    -- 1. drop shadow (outside the border box), faded by the cascaded opacity
    if c.shadow and (c.shadow.color.a or 0) > 0 then
        local sh = {x = c.shadow.x, y = c.shadow.y, blur = c.shadow.blur,
                    color = withAlpha(c.shadow.color, op)}
        KeyasCSS.dropShadow(owner, b.x, b.y, b.w, b.h, radius, sh)
    end

    -- 2. border ring (drawn as a rounded rect in border colour, then the
    --    background inset by borderWidth on top)
    local bw = c.borderWidth or 0
    if bw > 0 and c.borderColor and (c.borderColor.a or 0) > 0 then
        KeyasCSS.roundedRect(owner, b.x, b.y, b.w, b.h, radius, withAlpha(c.borderColor, op))
    end

    -- 3. background fill (inset by border)
    local fx, fy, fw, fh = b.x + bw, b.y + bw, b.w - 2 * bw, b.h - 2 * bw
    local innerRadius = math.max(0, radius - bw)
    if c.gradient then
        KeyasCSS.gradientRect(owner, fx, fy, fw, fh, c.gradient)
    elseif c.backgroundColor and (c.backgroundColor.a or 0) > 0 then
        KeyasCSS.roundedRect(owner, fx, fy, fw, fh, innerRadius, withAlpha(c.backgroundColor, op))
    end

    -- 4. clip subtree / text to the content box if overflow: hidden
    local clipped = (c.overflow == "hidden")
    if clipped then
        pcall(owner.setStencilRect, owner, b.cx, b.cy, b.cw, b.ch)
    end

    -- 5. text
    if self._lines then
        local col = withAlpha(c.color or {r = 0.9, g = 0.9, b = 0.9, a = 1}, op)
        local lh = self._lineH or 14
        local yy = b.cy
        for _, line in ipairs(self._lines) do
            local lx = b.cx
            if c.textAlign == "center" or c.textAlign == "right" then
                local lw = KeyasCSS._measure(line, c.font)
                if c.textAlign == "center" then lx = b.cx + (b.cw - lw) / 2
                else lx = b.cx + (b.cw - lw) end
            end
            drawText(owner, line, math.floor(lx), math.floor(yy), col, c.font)
            yy = yy + lh
        end
    end

    -- 6. custom paint hook - the escape hatch for anything KeyasCSS can't
    --    express declaratively (an icon from a spritesheet, a mini-map, a
    --    sparkline). Called with the CONTENT box in the same local space
    --    the rest of paint() uses, after this node's own bg/text and before
    --    its children, so children still draw on top.
    if self.onPaint then
        pcall(self.onPaint, self, owner, b.cx, b.cy, b.cw, b.ch, op)
    end

    -- 7. children
    for _, ch in ipairs(self.children) do
        if (ch.computed.display or "block") ~= "none" then
            ch:paint(owner, op)
        end
    end

    if clipped then
        pcall(owner.clearStencilRect, owner)
    end
end

--============================================================
-- Hit testing
--============================================================

--- Deepest node whose box contains (px, py) and that has an onClick.
--- Children are tested last-to-first (later siblings paint on top).
function Node:hit(px, py)
    local b = self.box
    if px < b.x or px > b.x + b.w or py < b.y or py > b.y + b.h then return nil end
    for i = #self.children, 1, -1 do
        local ch = self.children[i]
        if (ch.computed.display or "block") ~= "none" then
            local h = ch:hit(px, py)
            if h then return h end
        end
    end
    if self.onClick then return self end
    return nil
end

--- Finds a node in the tree by id (depth-first). Handy for a consumer that
--- keeps one tree and pokes text/style into it between frames.
function Node:find(id)
    if self.id == id then return self end
    for _, ch in ipairs(self.children) do
        local f = ch:find(id)
        if f then return f end
    end
    return nil
end

--============================================================
-- Surface - an ISPanel that hosts a KeyasCSS tree
--============================================================

local Surface = ISPanel:derive("KeyasCSS.Surface")
KeyasCSS.Surface = Surface

--- @param opts { stylesheet = <KeyasCSS.parse result>, root = <node or def>,
---               padding = <px>, background = <color>,
---               onClickMiss = fn,      -- click inside the surface but on no onClick node
---               onClickOutside = fn }  -- click anywhere outside the surface
function Surface:new(x, y, w, h, opts)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    opts = opts or {}
    o.stylesheet = opts.stylesheet
    o.pad = opts.padding or 0
    o.onClickMiss = opts.onClickMiss
    o.onClickOutside = opts.onClickOutside
    o.backgroundColor = KeyasCSS.color(opts.background) or {r = 0, g = 0, b = 0, a = 0}
    o.borderColor = {r = 0, g = 0, b = 0, a = 0}
    o.moveWithMouse = false
    if opts.root then o:setRoot(opts.root) end
    return o
end

--- Swap the tree. Accepts a Node or a node def. Re-resolves styles now;
--- layout happens each render (cheap, and keeps it correct across resize).
function Surface:setRoot(rootOrDef)
    self.root = getmetatable(rootOrDef) == Node and rootOrDef or KeyasCSS.node(rootOrDef)
    if self.stylesheet then self.root:resolve(self.stylesheet)
    else self.root:resolve(nil) end
    self._dirty = true
end

--- Call if you mutated node styles/text after setRoot and need the
--- stylesheet re-applied.
function Surface:refresh()
    if self.root then self.root:resolve(self.stylesheet) end
    self._dirty = true
end

function Surface:prerender()
    ISPanel.prerender(self)
    if not self.root then return end
    self.root:layout(self:getX() + self.pad, self:getY() + self.pad,
                     self:getWidth() - self.pad * 2, self:getHeight() - self.pad * 2)
end

function Surface:render()
    ISPanel.render(self)
    if not self.root then return end
    -- paint in screen space: our draw* are relative to (0,0) = our top-left,
    -- but layout ran in screen coords, so translate back.
    local ok = pcall(function()
        self.root:_shift(-self:getX(), -self:getY())
        self.root:paint(self, 1)
        self.root:_shift(self:getX(), self:getY())
    end)
    if not ok then dprint("KeyasCSS.Surface: paint failed") end
end

function Surface:onMouseUp(x, y)
    ISPanel.onMouseUp(self, x, y)
    if not self.root then return end
    -- x,y are local to the panel; hit() works in the same local space that
    -- render() painted in (we shift to local right before hit-testing).
    self.root:_shift(-self:getX(), -self:getY())
    local hitNode = self.root:hit(x, y)
    self.root:_shift(self:getX(), self:getY())
    if hitNode and hitNode.onClick then
        pcall(hitNode.onClick, hitNode, self)
    elseif self.onClickMiss then
        pcall(self.onClickMiss, self)
    end
end

function Surface:onMouseDown(x, y) return true end  -- claim the click so onMouseUp fires

function Surface:onMouseDownOutside(x, y)
    if self.onClickOutside then pcall(self.onClickOutside, self) end
    if ISPanel.onMouseDownOutside then ISPanel.onMouseDownOutside(self, x, y) end
end

return KeyasCSS
