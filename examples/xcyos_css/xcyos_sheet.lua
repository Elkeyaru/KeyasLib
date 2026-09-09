-- examples/xcyos_css/xcyos_sheet.lua
--
-- The XCYOS terminal mockup (Last Purpose's in-game computer) translated
-- from its HTML/CSS into a KeyasCSS stylesheet.
--
-- WHAT MAPS TO KeyasCSS (this file)
--   the whole application window: title bar (gradient), the list/detail
--   split, every pane, card, badge, reward tile, the CTA button, the rail,
--   the profession dock, the status bar. Colours, spacing, radii, the
--   title gradient, the window drop shadow, flex layout - all 1:1 from the
--   mockup's CSS custom properties and rules.
--
-- WHAT STAYS BAKED ART (a single backdrop PNG behind the Surface)
--   the CRT bezel + its radial gradient, the curved screen vignette, the
--   scanline / bloom FX overlay, the speaker vents, the glowing power
--   knob, the faint "XCYOS" brand watermark. None of these are structural
--   or interactive; they're a picture. Bake at ~2560x1440 (see
--   tools/skin_gen or any exporter) and draw it first, then this Surface
--   on top sized to the screen area.
--
-- FONTS
--   The mockup uses Chakra Petch (UI), Bitter (body) and VT323 (mono) at
--   several sizes. KeyasCSS's `font:` names a bitmap font registered with
--   KeyasUI.registerFont, so each size/role is its own id below. Generate
--   the atlases with tools/font_atlas_gen from those .ttf files. If an id
--   isn't registered, KeyasCSS falls back to a vanilla UIFont automatically
--   (layout still works, only the text metrics are off).
--
-- KeyasCSS v1 gaps worked around here, and how:
--   * grid  -> flex row/column with explicit widths + flex-grow.
--   * position:absolute (brand watermark, stripe, power) -> those are in
--     the baked backdrop; the profession dock is placed as the last child
--     of the rail column instead of absolutely.
--   * inset bevel shadows (90s dialog look) -> approximated with a 1px
--     border in the shadow/highlight colour.
--   * radial gradients -> flat fills (the radial ones are all in the
--     backdrop anyway).
--   * per-side borders / underline rules -> a 1px-high divider child node.

local XCYOS = {}

-- Palette: the mockup's :root custom properties, verbatim.
XCYOS.C = {
    bezel = "#17181a", screen = "#0b0f0d",
    desktop = "#1b201e", desktop2 = "#232a27",
    winFace = "#b9b6ad", winFace2 = "#cbc8bf", winShadow = "#6d6a61", winHi = "#eeece4",
    ink = "#16160f", inkSoft = "#4a473c", screenInk = "#cfd8cf",
    phosphor = "#2fe7c4", phosphorDim = "#1c8f7c",
    amber = "#ffb64a", ok = "#56b45a", lock = "#7c7a70", danger = "#d9463b",
}

-- Author the sheet at the mockup's own pixel sizes (screen ~1200x705).
-- KeyasCSS.parse(css, { scale = k }) multiplies every px here at load time,
-- so the consumer renders it at whatever the screen calls for.
XCYOS.CSS = [[
  /* ---- desktop + rail ------------------------------------------- */
  .desktop {
    display: flex; flex-direction: row; gap: 14px;
    padding: 16px; background: #1b201e;
  }
  .rail { width: 96px; display: flex; flex-direction: column; gap: 6px; padding-top: 4px; }
  .app-icon {
    display: flex; flex-direction: column; align-items: center; gap: 5px;
    padding: 8px 4px 6px; border-radius: 6px;
    border: 1px solid transparent;
    color: #cfd8cf; font: xcyos_ui_11;
  }
  .app-icon.is-active {
    background: rgba(47,231,196,0.12);
    border: 1px solid #1c8f7c;
    color: #eafffb;
  }
  .app-glyph { width: 34px; height: 34px; }   /* icon art slot (drawn by the consumer) */

  /* ---- profession dock (last child of the rail) ---------------- */
  .prof-dock {
    width: 92px; display: flex; flex-direction: column; align-items: center; gap: 5px;
    margin-top: 14px;
    padding: 7px 6px 8px;
    background: #232a27; border: 1px solid #000000;
  }
  .pd-label { font: xcyos_ui_11; color: #8fa39b; }
  .pd-icon {
    width: 100%; padding: 7px 0 6px;
    background: #0b0f0d; border: 1px solid #12100e;
  }
  .pd-glyph { width: 30px; height: 30px; }
  .pd-name { font: xcyos_ui_11; color: #eafffb; text-align: center; }
  .pd-name.is-locked { color: #7c7a70; }
  .pd-nav { display: flex; flex-direction: row; gap: 4px; width: 100%; }
  .pd-nav button {
    flex-grow: 1; padding: 2px 0 3px; text-align: center;
    background: #1b201e; border: 1px solid #000000; color: #2fe7c4; font: xcyos_ui_13;
  }
  .pd-status { font: xcyos_mono_15; color: #1c8f7c; text-align: center; }
  .pd-status.locked { color: #ffb64a; }

  /* ---- window frame ------------------------------------------- */
  .window {
    flex-grow: 1; display: flex; flex-direction: column;
    background: #b9b6ad;
    border: 1px solid #000000;
    box-shadow: 6px 8px 26px rgba(0,0,0,0.6);
  }
  .titlebar {
    display: flex; flex-direction: row; align-items: center; gap: 9px;
    padding: 6px 6px 6px 10px;
    background: linear-gradient(180deg, #3a4a45 0%, #26302d 100%);
    color: #eafffb; font: xcyos_ui_13;
  }
  .folder { width: 18px; height: 18px; }
  .t-name { flex-grow: 1; }
  .win-btns { display: flex; flex-direction: row; gap: 4px; }
  .win-btn {
    width: 22px; height: 20px; text-align: center;
    background: #b9b6ad; border: 1px solid #000000; color: #16160f; font: xcyos_ui_13;
  }
  .win-btn.close { color: #d9463b; }

  .window-body {
    flex-grow: 1; display: flex; flex-direction: row; gap: 12px;
    padding: 12px; background: #b9b6ad;
  }

  /* ---- panes -------------------------------------------------- */
  .pane {
    background: #cbc8bf; border: 1px solid #6d6a61; overflow: hidden; color: #16160f;
  }
  .list-pane { width: 300px; padding: 10px 0 10px 0; display: flex; flex-direction: column; }
  .detail-pane { flex-grow: 1; padding: 18px 20px; display: flex; flex-direction: column; }

  .lp-head {
    display: flex; flex-direction: row; align-items: center; gap: 8px;
    padding: 2px 10px 9px; font: xcyos_ui_13; color: #4a473c;
  }
  .lp-head .app-glyph { width: 18px; height: 18px; }
  .divider { height: 1px; background: #6d6a61; }

  .city { display: flex; flex-direction: column; padding: 0 10px; margin-top: 12px; }
  .city-title { font: xcyos_ui_13; color: #16160f; padding-bottom: 3px; }
  .city-rule { height: 2px; background: #16160f; margin-top: 1px; }
  .city-hint { font: xcyos_body_13; color: #7c7a70; margin-top: 6px; }

  .missions { display: flex; flex-direction: column; margin-top: 2px; }
  .m-row {
    display: flex; flex-direction: row; align-items: center; gap: 8px;
    padding: 4px 10px 4px 9px;
    border: 1px solid transparent;
    font: xcyos_body_13; color: #16160f;
  }
  .m-row .num { width: 14px; font: xcyos_mono_15; color: #4a473c; }
  .m-row .m-name { flex-grow: 1; }
  .m-row .dot { width: 8px; height: 8px; border-radius: 4px; }
  .dot.ok    { background: #56b45a; }
  .dot.prog  { background: #ffb64a; }
  .dot.lock  { background: #7c7a70; }
  .dot.claim { background: #2fe7c4; }
  .m-row.is-locked { color: #7c7a70; }
  .m-row.is-locked .num { color: #7c7a70; }
  .m-row.is-current {
    background: #2f3f3a; color: #eafffb; border: 1px solid #2fe7c4;
  }
  .m-row.is-current .num { color: #2fe7c4; }

  /* ---- detail pane ----------------------------------------------- */
  .d-head { display: flex; flex-direction: row; align-items: flex-start; gap: 12px; }
  .d-title { flex-grow: 1; display: flex; flex-direction: column; gap: 4px; }
  .d-title h2 { font: xcyos_ui_27; color: #16160f; }
  .d-city { font: xcyos_ui_11; color: #4a473c; }
  .badge {
    font: xcyos_ui_11; padding: 4px 9px; border: 1px solid #16160f;
  }
  .badge.ok    { color: #2f7a33; background: #d6ecd0; }
  .badge.prog  { color: #8a5300; background: #f6e2bf; }
  .badge.lock  { color: #5f5d54; background: #c7c4ba; }
  .badge.claim { color: #0c5e50; background: #bff2e8; }

  .d-sec { margin-top: 20px; display: flex; flex-direction: column; }
  .d-sec h4 { font: xcyos_ui_11; color: #16160f; padding-bottom: 4px; }
  .d-sec .divider { margin-bottom: 7px; }
  .d-grid { display: flex; flex-direction: row; gap: 18px; align-items: flex-start; }
  .d-body { font: xcyos_body_14; color: #16160f; line-height: 21px; flex-grow: 1; }

  .map { width: 220px; height: 220px; border: 1px solid #16160f; background: #d7d4cb; }

  .reward { display: flex; flex-direction: row; gap: 10px; margin-top: 4px; }
  .r-tile {
    width: 92px; padding: 8px 6px 6px; text-align: center;
    border: 1px solid #16160f; background: #b9b6ad;
    display: flex; flex-direction: column; align-items: center; gap: 2px;
  }
  .r-tile .app-glyph { width: 40px; height: 34px; }
  .r-tile b { font: xcyos_mono_16; color: #16160f; }
  .r-tile span { font: xcyos_ui_11; color: #4a473c; }
  .reward-note { font: xcyos_body_13; color: #4a473c; margin-top: 8px; }

  .action-row { display: flex; flex-direction: row; align-items: center; gap: 14px; margin-top: 18px; }
  .cta {
    display: flex; flex-direction: row; align-items: center; gap: 12px;
    padding: 10px 16px 10px 10px;
    border: 2px solid #16160f; background: #b9b6ad;
    box-shadow: 3px 3px 0 rgba(22,22,15,1);
    font: xcyos_ui_13; color: #16160f;
  }
  .cta.claim { background: #bff2e8; }
  .cta.is-disabled { opacity: 0.5; }
  .cta .app-glyph { width: 40px; height: 40px; }

  .req {
    margin-top: 14px; display: flex; flex-direction: row; gap: 10px; align-items: flex-start;
    border: 1px solid #7c7a70; background: #c9c6bc;
    padding: 10px 12px; font: xcyos_body_13; color: #16160f;
  }
  .req .app-glyph { width: 20px; height: 20px; }
  .toast { margin-top: 12px; font: xcyos_mono_16; color: #1c8f7c; }

  /* ---- simple apps (Notas / Archivos / Sistema) --------------- */
  .simple-pane { flex-grow: 1; padding: 20px 24px; overflow: hidden; color: #16160f;
                 display: flex; flex-direction: column; }
  .simple-pane h2 { font: xcyos_ui_20; color: #16160f; }
  .simple-pane .lede { font: xcyos_body_13; color: #4a473c; margin-top: 4px; margin-bottom: 18px; }
  .doc-list { display: flex; flex-direction: column; gap: 8px; }
  .doc-item {
    display: flex; flex-direction: row; gap: 12px; align-items: flex-start;
    border: 1px solid #6d6a61; background: #b9b6ad; padding: 10px 12px;
  }
  .doc-item .app-glyph { width: 22px; height: 22px; }
  .doc-item .doc-text { flex-grow: 1; display: flex; flex-direction: column; gap: 3px; }
  .doc-item b { font: xcyos_ui_13; }
  .doc-item p { font: xcyos_body_13; color: #4a473c; }
  .opt-row {
    display: flex; flex-direction: row; align-items: center; justify-content: space-between;
    gap: 16px; padding: 9px 0; font: xcyos_body_13; color: #16160f;
  }
  .opt-row .divider { }
  .opt-key { font: xcyos_mono_15; border: 1px solid #16160f; background: #b9b6ad; padding: 1px 10px; }
  .opt-sw { width: 42px; height: 20px; border: 1px solid #16160f; background: #9c998f; }
  .opt-sw.on { background: #1c8f7c; }
  .note-card {
    margin-top: 18px; border: 1px solid #1c8f7c; background: #c9c6bc;
    padding: 12px 14px; font: xcyos_body_13; color: #16160f; line-height: 20px;
  }

  /* ---- status bar ------------------------------------------------ */
  .statusbar {
    display: flex; flex-direction: row; align-items: center; gap: 14px;
    padding: 5px 16px; background: #05221c;
    font: xcyos_mono_16; color: #1c8f7c;
  }
  .statusbar .clock { flex-grow: 1; text-align: right; color: #2fe7c4; }
]]

--- Registers the seven bitmap fonts the sheet references. Point these at
--- atlases you built from Chakra Petch / Bitter / VT323 with
--- tools/font_atlas_gen. Safe to call more than once. If KeyasUI isn't
--- present, this is a no-op and KeyasCSS uses vanilla fonts.
function XCYOS.registerFonts(atlasDir)
    if not (KeyasUI and KeyasUI.registerFont) then return end
    atlasDir = atlasDir or "media/ui/xcyos"
    local function reg(id, file, size, fallback)
        local ok, metrics = pcall(require, "xcyos/" .. file .. "_metrics")
        if not ok then return end
        KeyasUI.registerFont(id, {
            atlasPath = atlasDir .. "/" .. file .. ".png",
            metrics = metrics, size = size, fallbackFont = fallback,
        })
    end
    reg("xcyos_ui_11",   "chakra_11", 11, UIFont and UIFont.Small)
    reg("xcyos_ui_13",   "chakra_13", 13, UIFont and UIFont.Small)
    reg("xcyos_ui_20",   "chakra_20", 20, UIFont and UIFont.Medium)
    reg("xcyos_ui_27",   "chakra_27", 27, UIFont and UIFont.Large)
    reg("xcyos_body_13", "bitter_13", 13, UIFont and UIFont.Small)
    reg("xcyos_body_14", "bitter_14", 14, UIFont and UIFont.Small)
    reg("xcyos_mono_15", "vt323_15",  15, UIFont and UIFont.Small)
    reg("xcyos_mono_16", "vt323_16",  16, UIFont and UIFont.Small)
end

return XCYOS
