-- examples/xcyos_css/xcyos.lua
--
-- Builds the XCYOS terminal as a KeyasCSS node tree + Surface, driven by
-- the stylesheet in xcyos_sheet.lua. This is the structural reference for
-- migrating Last Purpose's LP_Computer onto KeyasCSS (see KeyasLib
-- MIGRATION.md section 0).
--
-- Run in-game (mod with require=KeyasLib):   XcyosCSS.open()
--
-- The mission/profession data below is copied straight from the mockup so
-- the two can be diffed. In the real mod this comes from LastPurpose's
-- shared state instead.

require "ISUI/ISPanel"

XcyosCSS = XcyosCSS or {}

local SHEET = require "xcyos/xcyos_sheet"   -- examples/xcyos_css/xcyos_sheet.lua on the path

-- status: available | active | claim | locked | done
local HEISTS = {
    { city = "LOUISVILLE", items = {
        { id = "lp1", n = "El último golpe", status = "claim",
          obj = "Preparar y ejecutar el golpe al Knox Bank, el banco más grande de Kentucky. Rumores de cámaras desactivadas y una reserva especial en la cámara acorazada.",
          reward = { {"cash","≈ $25 000","Efectivo"}, {"gold","x5","Lingotes"}, {"crate","+","Suministros"} },
          rewardNote = "5 lingotes de oro · 4 diamantes · 6 fajos · suministros de mid-game · 2 niveles de Destreza" },
        { id = "lp2", n = "La última exposición", status = "available",
          obj = "Recuperar «La dama de carmesí» de la galería del norte antes que nadie. Escape urbano sin alarma audible; la amenaza está en las calles, no en la sala.",
          reward = { {"art","1","Pintura"}, {"gold","x?","Joyería"}, {"crate","+","Precisión"} },
          rewardNote = "Pintura única colocable · diamantes y joyería · herramientas de precisión · 2 niveles de Destreza" },
        { id = "lp3", n = "El cielo tiene dueño", status = "locked",
          req = "Completa «La última exposición».",
          obj = "Recuperar la fortuna escondida de un empresario en su penthouse. El peligro es vertical." },
        { id = "lp4", n = "Cero kilómetros", status = "locked",
          req = "Disponible en una versión futura (necesita el sistema de vehículo persistente).",
          obj = "Robar el deportivo del concesionario Upscale Mobility." },
    }},
    { city = "WEST POINT", hint = "Explora West Point y vuelve a tu refugio para desbloquear estos golpes.", items = {
        { id = "wp1", n = "La nómina desaparecida", status = "locked", req = "Explora West Point y regresa a tu refugio.",
          obj = "Un Knox Bank en miniatura: alarma al salir en vez de al recoger." },
        { id = "wp2", n = "Unidad 27", status = "locked", req = "Explora West Point y regresa a tu refugio.",
          obj = "Almacenamiento privado. Sin alarma, sin zombis generados; carga pesada." },
    }},
    { city = "RIVERSIDE", hint = "Explora Riverside y vuelve a tu refugio para desbloquear estos golpes.", items = {
        { id = "rv1", n = "Cuenta congelada", status = "locked", req = "Explora Riverside y regresa a tu refugio.",
          obj = "El banco de Riverside. Variante tranquila del golpe original." },
        { id = "rv2", n = "El trofeo del fundador", status = "locked", req = "Explora Riverside y regresa a tu refugio.",
          obj = "Country Club. Hay que recoger DOS objetos distintos antes de avanzar de etapa." },
    }},
}

local PROFS = {
    { id = "ladron", n = "Ladrón", unlocked = true,
      obj = "Tu profesión. El archivo lista los golpes: uno se elige por partida." },
    { id = "medico", n = "Médico", skill = "Medicina", unlocked = false,
      req = "Completá el prólogo del Ladrón y alcanzá Medicina Nv. 2." },
    { id = "ingeniero", n = "Ingeniero", skill = "Fabricación", unlocked = false,
      req = "Completá el prólogo del Ladrón y alcanzá Fabricación Nv. 2." },
    { id = "veterano", n = "Veterano", skill = "Puntería", unlocked = false,
      req = "Completá el prólogo del Ladrón y alcanzá Puntería Nv. 2." },
}

local BADGE = {
    available = {"ok", "DISPONIBLE"}, active = {"prog", "EN CURSO"},
    claim = {"claim", "BOTÍN PENDIENTE"}, locked = {"lock", "BLOQUEADA"}, done = {"ok", "ARCHIVADA"},
}
local DOT = { available = "ok", active = "prog", claim = "claim", locked = "lock", done = "ok" }
local REDACTED = "?????????"

local APPS = { {"misiones","Misiones"}, {"notas","Notas"}, {"archivos","Archivos"}, {"sistema","Sistema"} }

--============================================================
-- tree builders
--============================================================

local function findMission(state, id)
    for _, g in ipairs(HEISTS) do
        for _, m in ipairs(g.items) do if m.id == id then return m, g end end
    end
    for _, p in ipairs(PROFS) do if p.id == id then return p end end
end

local function statusOf(state, m)
    if state.claimed[m.id] then return "done" end
    return m.status
end

local function railNode(state, rebuild)
    local icons = {}
    for _, a in ipairs(APPS) do
        local active = state.app == a[1]
        icons[#icons + 1] = {
            tag = "div", class = active and "app-icon is-active" or "app-icon",
            onClick = function() state.app = a[1]; state.sel = state.sel; rebuild() end,
            children = {
                { tag = "div", class = "app-glyph", key = "app:" .. a[1] },
                { tag = "div", text = a[2] },
            },
        }
    end

    local p = PROFS[state.prof]
    icons[#icons + 1] = {
        tag = "div", class = "prof-dock",
        children = {
            { tag = "div", class = "pd-label", text = "PERFIL" },
            { tag = "div", class = "pd-icon", key = "prof:" .. p.id,
              onClick = function() cyclesProf(state, 1, rebuild) end,
              children = { { tag = "div", class = "pd-glyph" } } },
            { tag = "div", class = p.unlocked and "pd-name" or "pd-name is-locked", text = string.upper(p.n) },
            { tag = "div", class = "pd-nav", children = {
                { tag = "div", text = "<", onClick = function() cyclesProf(state, -1, rebuild) end },
                { tag = "div", text = ">", onClick = function() cyclesProf(state, 1, rebuild) end },
            }},
            { tag = "div", class = p.unlocked and "pd-status" or "pd-status locked",
              text = p.unlocked and "ACTIVO" or "BLOQUEADO" },
        },
    }
    return { tag = "div", class = "rail", children = icons }
end

function cyclesProf(state, dir, rebuild)
    state.prof = ((state.prof - 1 + dir) % #PROFS) + 1
    local p = PROFS[state.prof]
    state.sel = p.unlocked and "lp1" or p.id
    rebuild()
end

local function missionRow(state, m, index, rebuild)
    local st = statusOf(state, m)
    local cls = "m-row"
    if st == "locked" then cls = cls .. " is-locked" end
    if state.sel == m.id then cls = cls .. " is-current" end
    return { tag = "div", class = cls,
        onClick = function() state.sel = m.id; rebuild() end,
        children = {
            { tag = "div", class = "num", text = tostring(index) },
            { tag = "div", class = "m-name", text = (st == "locked") and REDACTED or m.n },
            { tag = "div", class = "dot " .. DOT[st] },
        },
    }
end

local function listPane(state, rebuild)
    local p = PROFS[state.prof]
    local children = {
        { tag = "div", class = "lp-head", children = {
            { tag = "div", class = "app-glyph" },
            { tag = "div", text = string.upper(p.n) .. (p.unlocked and " — GOLPES" or " — BLOQUEADA") },
        }},
        { tag = "div", class = "divider" },
    }

    if not p.unlocked then
        children[#children + 1] = { tag = "div", class = "city", children = {
            { tag = "div", class = "city-title", text = "LÍNEA BLOQUEADA" },
            { tag = "div", class = "city-rule" },
            { tag = "div", class = "city-hint", text = p.req or "" },
            { tag = "div", class = "missions", children = {
                { tag = "div", class = "m-row is-locked is-current", children = {
                    { tag = "div", class = "num", text = "•" },
                    { tag = "div", class = "m-name", text = REDACTED },
                    { tag = "div", class = "dot lock" },
                }},
            }},
        }}
    else
        for _, g in ipairs(HEISTS) do
            local rows = {}
            for i, m in ipairs(g.items) do rows[#rows + 1] = missionRow(state, m, i, rebuild) end
            local kids = {
                { tag = "div", class = "city-title", text = g.city },
                { tag = "div", class = "city-rule" },
            }
            if g.hint then kids[#kids + 1] = { tag = "div", class = "city-hint", text = g.hint } end
            kids[#kids + 1] = { tag = "div", class = "missions", children = rows }
            children[#children + 1] = { tag = "div", class = "city", children = kids }
        end
    end
    return { tag = "div", class = "pane list-pane", children = children }
end

local function detailPane(state, rebuild)
    local m, g = findMission(state, state.sel)
    if not m then return { tag = "div", class = "pane detail-pane" } end
    local isProf = (g == nil)
    local st = isProf and "locked" or statusOf(state, m)
    local b = BADGE[st]
    local cityLabel = m.skill and ("PROFESIÓN · " .. string.upper(m.skill))
        or (g and g.city or "")

    local head = { tag = "div", class = "d-head", children = {
        { tag = "div", class = "d-title", children = {
            { tag = "div", text = (st == "locked") and REDACTED or m.n, class = "d-title-h2", style = { font = "xcyos_ui_27" } },
            { tag = "div", class = "d-city", text = (st == "locked") and "EXPEDIENTE CLASIFICADO" or cityLabel },
        }},
        { tag = "div", class = "badge " .. b[1], text = b[2] },
    }}

    local secs = { head }

    if st == "locked" then
        secs[#secs + 1] = { tag = "div", class = "d-sec", children = {
            { tag = "div", class = "d-sec-h4", text = "OBJETIVO", style = { font = "xcyos_ui_11" } },
            { tag = "div", class = "divider" },
            { tag = "div", class = "d-body", text = "Nombre y detalles ocultos. Cumplí el requisito para que el expediente se abra." },
        }}
        secs[#secs + 1] = { tag = "div", class = "req", children = {
            { tag = "div", class = "app-glyph" },
            { tag = "div", class = "d-body", text = "Requisito. " .. (m.req or "") },
        }}
        secs[#secs + 1] = { tag = "div", class = "action-row", children = {
            { tag = "div", class = "cta is-disabled", children = {
                { tag = "div", class = "app-glyph" }, { tag = "div", text = "Bloqueada" },
            }},
        }}
        return { tag = "div", class = "pane detail-pane", children = secs }
    end

    secs[#secs + 1] = { tag = "div", class = "d-sec", children = {
        { tag = "div", class = "d-sec-h4", text = "OBJETIVO", style = { font = "xcyos_ui_11" } },
        { tag = "div", class = "divider" },
        { tag = "div", class = "d-grid", children = {
            { tag = "div", class = "d-body", text = m.obj },
            { tag = "div", class = "map", key = "map:" .. (cityLabel or "") },
        }},
    }}

    if m.reward then
        local tiles = {}
        for _, r in ipairs(m.reward) do
            tiles[#tiles + 1] = { tag = "div", class = "r-tile", children = {
                { tag = "div", class = "app-glyph", key = "ic:" .. r[1] },
                { tag = "div", text = r[2], style = { font = "xcyos_mono_16" } },
                { tag = "div", text = r[3], style = { font = "xcyos_ui_11" } },
            }}
        end
        local rewChildren = {
            { tag = "div", class = "d-sec-h4", text = "RECOMPENSA ESTIMADA", style = { font = "xcyos_ui_11" } },
            { tag = "div", class = "divider" },
            { tag = "div", class = "reward", children = tiles },
        }
        if m.rewardNote then
            rewChildren[#rewChildren + 1] = { tag = "div", class = "reward-note", text = m.rewardNote }
        end
        secs[#secs + 1] = { tag = "div", class = "d-sec", children = rewChildren }
    end

    -- action row
    local action
    if st == "available" then
        action = { tag = "div", class = "action-row", children = {
            { tag = "div", class = "cta", onClick = function() m.status = "active"; rebuild() end,
              children = { { tag = "div", class = "app-glyph" }, { tag = "div", text = "Seleccionar" } } },
            { tag = "div", class = "cta", onClick = function() rebuild() end,
              children = { { tag = "div", text = "Otra pista" } } },
        }}
    elseif st == "active" then
        action = { tag = "div", class = "action-row", children = {
            { tag = "div", class = "cta is-disabled", children = { { tag = "div", text = "Sigue en el diario (J)" } } },
        }}
    elseif st == "claim" then
        action = { tag = "div", class = "action-row", children = {
            { tag = "div", class = "cta claim", onClick = function() state.claimed[m.id] = true; rebuild() end,
              children = { { tag = "div", class = "app-glyph" }, { tag = "div", text = "Entregar botín" } } },
        }}
    else
        action = { tag = "div", class = "action-row", children = {
            { tag = "div", class = "cta is-disabled", children = { { tag = "div", text = "Archivada" } } },
        }}
    end
    secs[#secs + 1] = action
    if state.claimed[m.id] then
        secs[#secs + 1] = { tag = "div", class = "toast", text = "> BOTÍN ENTREGADO. Misión archivada." }
    end

    return { tag = "div", class = "pane detail-pane", children = secs }
end

local function simplePane(title, lede, items)
    local docs = {}
    for _, it in ipairs(items) do
        docs[#docs + 1] = { tag = "div", class = "doc-item", children = {
            { tag = "div", class = "app-glyph" },
            { tag = "div", class = "doc-text", children = {
                { tag = "div", text = it[1], style = { font = "xcyos_ui_13" } },
                { tag = "div", text = it[2], style = { font = "xcyos_body_13", color = "#4a473c" } },
            }},
        }}
    end
    return { tag = "div", class = "simple-pane", children = {
        { tag = "div", text = title, style = { font = "xcyos_ui_20" } },
        { tag = "div", class = "lede", text = lede },
        { tag = "div", class = "doc-list", children = docs },
    }}
end

local function windowBody(state, rebuild)
    if state.app == "misiones" then
        return { listPane(state, rebuild), detailPane(state, rebuild) }
    elseif state.app == "notas" then
        return { simplePane("Notas",
            "Las notas cifradas y los papeles que fuiste recogiendo en el mundo.", {
            {"Nota del punto de reunión", "«Los documentos siguen escondidos en el punto que marcamos en Louisville.»"},
            {"Transmisión interceptada", "Seis líneas de un contacto que repite el mensaje cada media hora."},
            {"Recorte de prensa — Knox Bank", "«El banco más grande de Kentucky cierra sus puertas.»"},
        }) }
    elseif state.app == "archivos" then
        return { simplePane("Archivos",
            "Intel acumulada. Planos parciales, contactos y todo lo que sobrevivió a la evacuación.", {
            {"Knox Bank — planta y perímetro", "Coordenadas validadas en partida. Puertas y ventanas selladas hasta que empieza el golpe."},
            {"Contacto — «la voz de la radio»", "Sin nombre. Llama en la banda de bandidos."},
            {"Catálogo de golpes — Louisville", "Cuatro objetivos. Uno se elige por partida."},
        }) }
    else
        return { simplePane("Sistema",
            "Opciones del mod. Se reflejan en Opciones → Mods → Last Purpose.", {
            {"Tecla para abrir el diario", "J"},
            {"Registro de depuración", "Desactivado"},
            {"Líneas de escaneo del terminal", "Activado"},
        }) }
    end
end

local function buildTree(state, rebuild)
    local winTitle = "LAST PURPOSE // " .. ({
        misiones = "ARCHIVO DE MISIONES", notas = "NOTAS",
        archivos = "ARCHIVOS", sistema = "SISTEMA",
    })[state.app]

    return { tag = "div", class = "screen", style = { display = "flex", flexDirection = "column" }, children = {
        { tag = "div", class = "desktop", style = { flexGrow = 1 }, children = {
            railNode(state, rebuild),
            { tag = "div", class = "window", children = {
                { tag = "div", class = "titlebar", children = {
                    { tag = "div", class = "folder" },
                    { tag = "div", class = "t-name", text = winTitle },
                    { tag = "div", class = "win-btns", children = {
                        { tag = "div", class = "win-btn", text = "_" },
                        { tag = "div", class = "win-btn", text = "[]" },
                        { tag = "div", class = "win-btn close", text = "X",
                          onClick = function() XcyosCSS.close() end },
                    }},
                }},
                { tag = "div", class = "window-body", children = windowBody(state, rebuild) },
            }},
        }},
        { tag = "div", class = "statusbar", children = {
            { tag = "div", text = "XCYOS v1.0.3" },
            { tag = "div", text = "|" },
            { tag = "div", text = "LAST PURPOSE TERMINAL" },
            { tag = "div", class = "clock", text = "12:47 · 14/07/1993" },
        }},
    }}
end

--============================================================
-- open / close
--============================================================

function XcyosCSS.open()
    SHEET.registerFonts()

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()

    -- The mockup's screen area is ~1200 x 705. Fit it into 92% of the game
    -- window and scale the whole sheet to match (author 1x, render Nx).
    local DESIGN_W, DESIGN_H = 1200, 705
    local scale = math.min(sw * 0.92 / DESIGN_W, sh * 0.92 / DESIGN_H)
    local w = math.floor(DESIGN_W * scale)
    local h = math.floor(DESIGN_H * scale)

    local sheet = KeyasCSS.parse(SHEET.CSS, { scale = scale })

    local state = { app = "misiones", prof = 1, sel = "lp1", claimed = {} }

    local surface
    local function rebuild()
        if surface then surface:setRoot(buildTree(state, rebuild)) end
    end

    surface = KeyasCSS.Surface:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h, {
        stylesheet = sheet,
        background = "#0b0f0d",   -- stand-in for the baked CRT backdrop
        root = buildTree(state, rebuild),
        onClickMiss = function() end,
    })
    surface:initialise()
    surface:instantiate()
    surface:addToUIManager()
    XcyosCSS._surface = surface
end

function XcyosCSS.close()
    if XcyosCSS._surface then
        XcyosCSS._surface:removeFromUIManager()
        XcyosCSS._surface = nil
    end
end
