# Example spec: the "XCYOS" retro-OS terminal (Last Purpose's computer hub).
# Returns a hashtable. generate_skin.ps1 reads it and bakes chrome.png + zones.lua.
#
# Every key is optional except that panes/railApps decide what zones exist.
# Colours are hex without '#'. Coordinates are in bake space (bakeW x bakeH);
# window-relative for `panes`, canvas-absolute for everything else.

@{
    bakeW = 1920; bakeH = 1080

    # --- desktop + bezel ---
    desktopInner = "232a27"; desktopOuter = "12140f"
    bezel        = "17181a"; bezelRadius = 26
    scanAlpha    = 20;       vignetteAlpha = 70

    # --- left rail: one {LABEL, glyphKind} per app; glyphKind in monitor|page|folder|gear ---
    railApps = @(
        ,@("MISIONES", "monitor")
        ,@("NOTAS",    "page")
        ,@("ARCHIVOS", "folder")
        ,@("SISTEMA",  "gear")
    )
    railX = 22; railW = 128; railTop = 30; railStep = 118
    stripe = @("62b657", "3c9a8b", "e2a021", "d1443a"); stripeY = 300

    # --- XCYOS logo watermark (absolute path to a PNG, or omit) ---
    logo = "$PSScriptRoot\..\..\..\..\Last Purpose\42\media\ui\LastPurpose\xcyos_logo.png"
    logoW = 420; logoAlpha = 0.5; logoMargin = 40

    # --- window ---
    winX = 172; winY = 60; winW = 1372; winH = 918
    winFace   = "b9b6ad"
    titleH    = 32
    titleTop  = "3f5049"; titleBot = "26302d"; titleInk = "eafffb"
    titleText = "LAST PURPOSE // ARCHIVO DE MISIONES"

    # --- panes: {zoneName, x, y, w, h} window-relative. The emitted zone is
    #     the pane interior, inset 14 px, so consumer text starts inside it. ---
    paneFace = "d0cdc4"
    panes = @(
        ,@("listPane",   16,  42, 274, 862)
        ,@("detailPane", 304, 42, 1052, 862)
    )

    # --- status bar text ---
    statusLeft  = "XCYOS v1.0.3  |  LAST PURPOSE TERMINAL"
    statusRight = "12:47  .  14/07/1993"
}
