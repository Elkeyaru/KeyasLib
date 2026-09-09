-- examples/css_demo/demo.lua
--
-- A stand-alone KeyasCSS demo: a rounded, shadowed card with a gradient
-- header and a flex-column list of clickable rows - none of which ISUI can
-- draw on its own. Nothing here depends on Last Purpose.
--
-- To try it in-game, drop this file into a mod that has `require=KeyasLib`
-- (anywhere under 42/media/lua/client/) and run  KeyasCSSDemo.open()  from
-- the debug console, or wire it to a key.

require "ISUI/ISPanel"

KeyasCSSDemo = KeyasCSSDemo or {}

-- A plain CSS string. Selectors are flat: tag / .class / #id.
local SHEET = [[
  .card {
    width: 420px;
    background: #14161d;
    border: 1px solid #2b2f3a;
    border-radius: 14px;
    box-shadow: 0 10px 30px rgba(0,0,0,0.55);
    padding: 0;
    overflow: hidden;
  }
  .header {
    height: 64px;
    background: linear-gradient(180deg, #3a4a7a 0%, #26305a 100%);
    padding: 0 18px;
    display: flex;
    flex-direction: row;
    align-items: center;
    justify-content: space-between;
  }
  .title { color: #eef1ff; font: klib_demo_16; }
  .badge {
    background: #7b5cff; color: #ffffff; font: klib_demo_12;
    border-radius: 999px; padding: 4px 10px;
  }
  .body { padding: 14px; display: flex; flex-direction: column; gap: 8px; }
  .row {
    background: #1b1e27; border-radius: 10px; padding: 12px 14px;
    display: flex; flex-direction: row; justify-content: space-between; align-items: center;
  }
  .row-name { color: #cdd3e1; font: klib_demo_14; }
  .row-val  { color: #8b93a7; font: klib_demo_12; }
  .row.sel  { background: #2a2f6a; border: 1px solid #6f7bff; }
]]

local function buildTree(selectedIdx)
    local rows = {
        {name = "Objetivo: Knox Bank", val = "bloqueado"},
        {name = "Ruta de entrada", val = "3 opciones"},
        {name = "Reparto", val = "$ 0"},
        {name = "Ventana horaria", val = "20:00 - 04:00"},
    }
    local rowNodes = {}
    for i, r in ipairs(rows) do
        rowNodes[i] = {
            tag = "div", class = i == selectedIdx and "row sel" or "row",
            key = i,
            onClick = function(_, surface)
                KeyasCSSDemo._sel = i
                surface:setRoot(buildTree(i))
            end,
            children = {
                {tag = "div", class = "row-name", text = r.name},
                {tag = "div", class = "row-val", text = r.val},
            },
        }
    end
    return {
        tag = "div", class = "card",
        children = {
            {tag = "div", class = "header", children = {
                {tag = "div", class = "title", text = "ARCHIVO DE MISIONES"},
                {tag = "div", class = "badge", text = "v1"},
            }},
            {tag = "div", class = "body", children = rowNodes},
        },
    }
end

function KeyasCSSDemo.open()
    -- Register a bitmap font for the demo if the consumer shipped one;
    -- otherwise KeyasCSS falls back to vanilla UIFont automatically and the
    -- `font:` declarations above are simply ignored.
    -- KeyasUI.registerFont("klib_demo_16", { atlasPath = "...", metrics = ... })

    local sheet = KeyasCSS.parse(SHEET)
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w, h = 460, 380

    KeyasCSSDemo._sel = KeyasCSSDemo._sel or 1
    local surface = KeyasCSS.Surface:new((sw - w) / 2, (sh - h) / 2, w, h, {
        stylesheet = sheet,
        padding = 20,
        background = "rgba(0,0,0,0.35)",
        root = buildTree(KeyasCSSDemo._sel),
        onClickMiss = function(s) s:removeFromUIManager() end,
    })
    surface:initialise()
    surface:addToUIManager()
    KeyasCSSDemo._surface = surface
end

function KeyasCSSDemo.close()
    if KeyasCSSDemo._surface then
        KeyasCSSDemo._surface:removeFromUIManager()
        KeyasCSSDemo._surface = nil
    end
end
