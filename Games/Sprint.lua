-- AFKade – Spiel „Murloc-Sprint“ (Endlos-Läufer)
--
-- Ein Murloc rennt durchs Brachland: über Kakteen und Termitenhügel
-- springen, unter Geiern wegducken. Das Tempo steigt langsam an.
-- Steuerung: Leertaste/Pfeil hoch = springen, Pfeil runter = ducken
-- (in der Luft: schneller fallen). Maus: links springen, rechts ducken.
-- Die Tastatur wird nur abgefangen, solange ein Lauf aktiv ist.

local _, ns = ...
local L, U = ns.L, ns.U

local G = {
    id = "sprint",
    name = L.GAME_SPRINT,
    icon = ns.MEDIA .. "sprint",
}

-- Spielfeld (Pixel) und Physik (Pixel/Sekunde)
local W, H = 380, 240
local GROUND = 44
local PX, SIZE, DUCK_H = 48, 34, 20
local GRAVITY, JUMP_V, FAST_FALL = 2200, 640, 900
local START_SPEED, ACCEL, MAX_SPEED = 220, 4, 520
local SHRINK = 4          -- Trefferzonen etwas kleiner = fairer
local YARD = 10           -- 10 Pixel = 1 Yard

local GREEN = { 0.27, 0.56, 0.25 }
local BROWN = { 0.55, 0.38, 0.22 }
local BIRD = { 0.30, 0.24, 0.20 }
local BEAK = { 0.95, 0.75, 0.2 }

local function cactus(dx)
    return {
        { dx + 6, 0, 6, 34, GREEN }, { dx + 0, 12, 6, 4, GREEN }, { dx + 0, 12, 4, 12, GREEN },
        { dx + 12, 16, 6, 4, GREEN }, { dx + 14, 16, 4, 12, GREEN },
    }
end

local function birdParts()
    return {
        { 6, 4, 18, 6, BIRD }, { 24, 5, 6, 5, BIRD }, { 30, 6, 3, 2, BEAK },
        { 8, 10, 12, 5, BIRD }, -- Flügel (letzter Eintrag, wird animiert)
    }
end

local double = cactus(0)
for _, p in ipairs(cactus(22)) do double[#double + 1] = p end

local KINDS = {
    cactusS = { w = 18, h = 34, y = 0, parts = cactus(0) },
    cactusL = { w = 24, h = 46, y = 0, parts = {
        { 8, 0, 8, 46, GREEN }, { 0, 16, 8, 5, GREEN }, { 0, 16, 5, 16, GREEN },
        { 16, 22, 8, 5, GREEN }, { 19, 22, 5, 14, GREEN },
    } },
    cactusDouble = { w = 40, h = 34, y = 0, parts = double },
    mound = { w = 32, h = 22, y = 0, parts = {
        { 0, 0, 32, 12, BROWN }, { 4, 12, 24, 6, BROWN }, { 10, 18, 12, 4, BROWN },
    } },
    vultureHead = { w = 33, h = 15, y = 24, bird = true, parts = birdParts() }, -- ducken!
    vultureLow = { w = 33, h = 15, y = 6, bird = true, parts = birdParts() },   -- springen!
}

---------------------------------------------------------------------------
-- Zustand
---------------------------------------------------------------------------

local pane, canvas, player, overlay
local Wd = {}
local state = "ready" -- ready | running | paused | over
local t, dist, speed = 0, 0, START_SPEED
local py, vy, onGround, downHeld, ducking = 0, 0, true, false, false
local nextSpawn = 0
local obstacles, pool = {}, {}
local scenery = {}
local flash = 0

local function data() return ns.GameData(G.id) end
local function yards() return math.floor(dist / YARD) end

function G.InitData(d)
    d.best = d.best or 0
    d.runs = d.runs or 0
    d.total = d.total or 0
end

-- Spielstände zusammenführen (alte Pro-Charakter-Daten -> Account)
function G.MergeData(dst, src)
    dst.best = math.max(dst.best or 0, src.best or 0)
    dst.runs = (dst.runs or 0) + (src.runs or 0)
    dst.total = (dst.total or 0) + (src.total or 0)
end

function G.StatRows(d)
    return {
        { L.STAT_RECORD, L.STAT_YD_FMT:format(U.fmtInt(d.best or 0)) },
        { L.STAT_RUNS, U.fmtInt(d.runs or 0) },
        { L.STAT_DISTANCE, L.STAT_YD_FMT:format(U.fmtInt(d.total or 0)) },
    }
end

function G.SidebarText(d)
    return L.SPRINT_BEST_FMT:format(U.fmtInt(d.best or 0))
end

---------------------------------------------------------------------------
-- Tastatur: nur während eines Laufs abfangen
---------------------------------------------------------------------------

local function setKeyboard(on)
    if InCombatLockdown() then on = false end
    pcall(canvas.EnableKeyboard, canvas, on)
    if on then pcall(canvas.SetPropagateKeyboardInput, canvas, true) end
end

local function propagate(pass)
    if not InCombatLockdown() then pcall(canvas.SetPropagateKeyboardInput, canvas, pass) end
end

---------------------------------------------------------------------------
-- Hindernisse
---------------------------------------------------------------------------

local function newObstacle()
    local f = CreateFrame("Frame", nil, canvas)
    f:SetFrameLevel(canvas:GetFrameLevel() + 3)
    f.tex = {}
    return f
end

local function spawn()
    local y = yards()
    local choices = { "cactusS", "mound" }
    if y > 120 then
        choices[#choices + 1] = "cactusL"
        choices[#choices + 1] = "cactusDouble"
    end
    local kind
    if y > 300 and math.random() < 0.3 then
        kind = (math.random() < 0.7) and "vultureHead" or "vultureLow"
    else
        kind = choices[math.random(1, #choices)]
    end
    local def = KINDS[kind]

    local o = table.remove(pool) or newObstacle()
    o.kind, o.def, o.x, o.flap = kind, def, W + 4, 0
    o:SetSize(def.w, def.h)
    for i, p in ipairs(def.parts) do
        local tex = o.tex[i] or o:CreateTexture(nil, "ARTWORK")
        o.tex[i] = tex
        tex:ClearAllPoints()
        tex:SetPoint("BOTTOMLEFT", p[1], p[2])
        tex:SetSize(p[3], p[4])
        tex:SetColorTexture(p[5][1], p[5][2], p[5][3], 1)
        tex:Show()
    end
    for i = #def.parts + 1, #o.tex do o.tex[i]:Hide() end
    o.wing = def.bird and o.tex[#def.parts] or nil
    o:Show()
    obstacles[#obstacles + 1] = o

    -- Abstand zum nächsten Hindernis: wächst mit dem Tempo, damit es fair bleibt
    nextSpawn = def.w + speed * (0.75 + math.random() * 0.8) + 70
end

local function clearObstacles()
    for i = #obstacles, 1, -1 do
        obstacles[i]:Hide()
        pool[#pool + 1] = obstacles[i]
        obstacles[i] = nil
    end
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

---------------------------------------------------------------------------
-- Kulisse: Wolken, Hügel, Kiesel (Parallax)
---------------------------------------------------------------------------

local function buildScenery()
    local sky = canvas:CreateTexture(nil, "BACKGROUND", nil, -6)
    sky:SetAllPoints()
    sky:SetColorTexture(0.42, 0.62, 0.84, 1)
    local sun = canvas:CreateTexture(nil, "BACKGROUND", nil, -5)
    sun:SetSize(34, 34)
    sun:SetPoint("TOPRIGHT", -150, -24)
    sun:SetColorTexture(1, 0.9, 0.55, 1)
    U.maskCircle(canvas, sun)

    local function add(layer, sub, w, h, y, color, factor, x)
        local tex = canvas:CreateTexture(nil, layer, nil, sub)
        tex:SetSize(w, h)
        tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        scenery[#scenery + 1] = { tex = tex, x = x, y = y, w = w, factor = factor }
    end
    for i = 1, 3 do
        add("BACKGROUND", -4, 46 + i * 8, 10, 170 - i * 22, { 1, 1, 1, 0.75 }, 0.08, i * 130)
    end
    for i = 1, 5 do
        local h = 18 + (i * 13) % 30
        add("BACKGROUND", -3, 90 + (i * 37) % 60, h, GROUND, { 0.62, 0.5, 0.33 }, 0.25, (i - 1) * 95)
    end

    local ground = canvas:CreateTexture(nil, "BORDER")
    ground:SetPoint("BOTTOMLEFT")
    ground:SetPoint("BOTTOMRIGHT")
    ground:SetHeight(GROUND)
    ground:SetColorTexture(0.74, 0.6, 0.37, 1)
    local edge = canvas:CreateTexture(nil, "BORDER", nil, 1)
    edge:SetPoint("BOTTOMLEFT", 0, GROUND - 2)
    edge:SetPoint("BOTTOMRIGHT", 0, GROUND - 2)
    edge:SetHeight(2)
    edge:SetColorTexture(0.45, 0.34, 0.2, 1)

    for i = 1, 14 do
        add("ARTWORK", -2, 3 + i % 3, 2, 8 + (i * 11) % 30, { 0.5, 0.38, 0.24 }, 1, i * 29)
    end
end

local function updateScenery(dx)
    for _, s in ipairs(scenery) do
        s.x = s.x - dx * s.factor
        if s.x + s.w < 0 then s.x = s.x + W + s.w + 40 end
        s.tex:ClearAllPoints()
        s.tex:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", s.x, s.y)
    end
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

local function drawPlayer()
    local h = ducking and DUCK_H or SIZE
    local bob = 0
    if state == "running" and onGround and not ducking then bob = math.abs(math.sin(t * 16)) * 2 end
    player:SetSize(SIZE, h)
    player:ClearAllPoints()
    player:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", PX, GROUND + py + bob)
end

local function drawScore()
    local d = data()
    Wd.score:SetText(U.fmtInt(yards()) .. " yd")
    Wd.best:SetText(L.SPRINT_BEST_FMT:format(U.fmtInt(d.best)))
    if flash > 0 then
        Wd.score:SetTextColor(1, 0.82, 0)
    else
        Wd.score:SetTextColor(1, 1, 1)
    end
end

local function drawStats()
    local d = data()
    Wd.stats:SetText(L.SPRINT_STATS_FMT:format(d.runs, U.fmtInt(d.total), U.fmtInt(d.best)))
end

local function showOverlay(title, line1, line2, buttonText)
    Wd.ovTitle:SetText(title)
    Wd.ovLine1:SetText(line1 or "")
    Wd.ovLine2:SetText(line2 or "")
    Wd.ovButton:SetText(buttonText)
    overlay:Show()
end

---------------------------------------------------------------------------
-- Ablauf
---------------------------------------------------------------------------

local function reset()
    clearObstacles()
    t, dist, speed = 0, 0, START_SPEED
    py, vy, onGround, downHeld, ducking = 0, 0, true, false, false
    nextSpawn = 260
    flash = 0
    Wd.icon:SetVertexColor(1, 1, 1)
    drawPlayer()
    drawScore()
end

local function run()
    overlay:Hide()
    state = "running"
    setKeyboard(true)
end

local function start()
    reset()
    run()
end

local function pause()
    if state ~= "running" then return end
    state = "paused"
    downHeld, ducking = false, false
    setKeyboard(false)
    showOverlay(L.SPRINT_PAUSED, U.fmtInt(yards()) .. " yd", nil, L.CONTINUE)
end

local function gameOver()
    state = "over"
    downHeld = false
    setKeyboard(false)
    Wd.icon:SetVertexColor(1, 0.4, 0.4)
    local d, y = data(), yards()
    d.runs = d.runs + 1
    d.total = d.total + y
    local record = y > d.best
    if record then d.best = y end
    drawScore()
    drawStats()
    ns.UI.RefreshSidebar()
    U.play("IG_QUEST_FAILED")
    showOverlay(L.SPRINT_OVER, L.SPRINT_DIST_FMT:format(U.fmtInt(y)),
        record and L.SPRINT_NEW_RECORD or L.SPRINT_BEST_FMT:format(U.fmtInt(d.best)), L.SPRINT_AGAIN)
end

local function onOverlayButton()
    if state == "paused" then run() else start() end
end

local function jump()
    if onGround then
        vy, onGround = JUMP_V, false
        ducking = false
    end
end

local function update(_, elapsed)
    if state ~= "running" then return end
    local dt = math.min(elapsed, 0.05) -- bei Rucklern nicht durch Hindernisse "tunneln"
    t = t + dt
    speed = math.min(MAX_SPEED, START_SPEED + ACCEL * t)
    local dx = speed * dt
    local before = yards()
    dist = dist + dx
    if math.floor(yards() / 500) > math.floor(before / 500) then flash = 0.6 end
    flash = math.max(0, flash - dt)

    -- Murloc
    if not onGround then
        if downHeld and vy > -FAST_FALL then vy = -FAST_FALL end
        vy = vy - GRAVITY * dt
        py = py + vy * dt
        if py <= 0 then py, vy, onGround = 0, 0, true end
    end
    ducking = downHeld and onGround
    drawPlayer()

    -- Hindernisse bewegen, Geierflügel schlagen lassen
    nextSpawn = nextSpawn - dx
    if nextSpawn <= 0 then spawn() end
    local ph = ducking and DUCK_H or SIZE
    for i = #obstacles, 1, -1 do
        local o = obstacles[i]
        o.x = o.x - dx
        if o.x + o.def.w < -10 then
            o:Hide()
            pool[#pool + 1] = o
            table.remove(obstacles, i)
        else
            o:ClearAllPoints()
            o:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", o.x, GROUND + o.def.y)
            if o.wing then
                o.flap = o.flap + dt
                o.wing:ClearAllPoints()
                o.wing:SetPoint("BOTTOMLEFT", 8, (math.floor(o.flap / 0.15) % 2 == 0) and 10 or -2)
            end
            if overlaps(PX + SHRINK, py + SHRINK, SIZE - 2 * SHRINK, ph - 2 * SHRINK,
                o.x + SHRINK, o.def.y + SHRINK, o.def.w - 2 * SHRINK, o.def.h - 2 * SHRINK) then
                gameOver()
                return
            end
        end
    end

    updateScenery(dx)
    drawScore()
end

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------

function G.Build(p)
    pane = p

    canvas = CreateFrame("Frame", nil, pane)
    canvas:SetSize(W, H)
    canvas:SetPoint("TOP", 0, -8)
    pcall(canvas.SetClipsChildren, canvas, true)
    U.addBackdrop(canvas, { 0.25, 0.22, 0.32, 1 }, { 0, 0, 0, 1 })
    buildScenery()

    -- Murloc
    player = CreateFrame("Frame", nil, canvas)
    player:SetFrameLevel(canvas:GetFrameLevel() + 5)
    local ring = player:CreateTexture(nil, "BACKGROUND")
    ring:SetPoint("TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", 2, -2)
    ring:SetColorTexture(0.1, 0.2, 0.15, 1)
    U.maskCircle(player, ring)
    local icon = player:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\INV_Misc_Head_Murloc_01") -- der Läufer bleibt ein Murloc
    U.maskCircle(player, icon)
    Wd.icon = icon

    -- Punkte oben rechts
    local hud = CreateFrame("Frame", nil, canvas)
    hud:SetAllPoints()
    hud:SetFrameLevel(canvas:GetFrameLevel() + 10)
    Wd.score = U.text(hud, "GameFontNormalLarge", 1, 1, 1)
    Wd.score:SetPoint("TOPRIGHT", -10, -8)
    Wd.best = U.text(hud, "GameFontHighlightSmall", 0.15, 0.15, 0.2)
    Wd.best:SetShadowColor(0, 0, 0, 0)
    Wd.best:SetPoint("TOPRIGHT", Wd.score, "BOTTOMRIGHT", 0, -2)

    -- Overlay: Start / Pause / Ende
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetSize(270, 132)
    overlay:SetPoint("CENTER", 0, 14)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 20)
    overlay:EnableMouse(true)
    U.addBackdrop(overlay, { 0.42, 0.38, 0.52, 1 }, { 0.05, 0.04, 0.08, 0.92 })
    Wd.ovTitle = U.text(overlay, "GameFontNormalHuge", 1, 0.82, 0)
    Wd.ovTitle:SetPoint("TOP", 0, -12)
    Wd.ovLine1 = U.text(overlay, "GameFontHighlight")
    Wd.ovLine1:SetPoint("TOP", Wd.ovTitle, "BOTTOM", 0, -8)
    Wd.ovLine1:SetWidth(250)
    Wd.ovLine2 = U.text(overlay, "GameFontNormal", 0.4, 1, 0.5)
    Wd.ovLine2:SetPoint("TOP", Wd.ovLine1, "BOTTOM", 0, -4)
    Wd.ovLine2:SetWidth(250)
    Wd.ovButton = U.button(overlay, L.START, 130, 24)
    Wd.ovButton:SetPoint("BOTTOM", 0, 12)
    Wd.ovButton:SetScript("OnClick", onOverlayButton)

    -- Eingabe: Tastatur (nur im Lauf) und Maus
    canvas:SetScript("OnKeyDown", function(_, key)
        local handled = false
        if state == "running" then
            if key == "SPACE" or key == "UP" then
                jump()
                handled = true
            elseif key == "DOWN" then
                downHeld = true
                handled = true
            end
        end
        propagate(not handled)
    end)
    canvas:SetScript("OnKeyUp", function(_, key)
        if key == "DOWN" then downHeld = false end
        propagate(true)
    end)
    canvas:EnableMouse(true)
    canvas:SetScript("OnMouseDown", function(_, button)
        if state == "running" then
            if button == "RightButton" then downHeld = true else jump() end
        elseif button == "LeftButton" then
            onOverlayButton()
        end
    end)
    canvas:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then downHeld = false end
    end)
    canvas:SetScript("OnUpdate", update)

    -- Unter dem Spielfeld: Steuerung und Statistik
    local controls = U.text(pane, "GameFontHighlightSmall", 0.85, 0.85, 0.9)
    controls:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 2, -12)
    controls:SetWidth(W)
    controls:SetJustifyH("LEFT")
    controls:SetText(L.SPRINT_CONTROLS)
    Wd.stats = U.text(pane, "GameFontHighlightSmall", 0.75, 0.75, 0.8)
    Wd.stats:SetPoint("TOPLEFT", controls, "BOTTOMLEFT", 0, -10)

    reset()
    updateScenery(0)
    showOverlay(L.GAME_SPRINT, L.SPRINT_INTRO, nil, L.START)

    -- Fenster zu, Spiel gewechselt oder Kampf: Pause und Tastatur freigeben
    pane:SetScript("OnShow", drawStats)
    pane:SetScript("OnHide", pause)
end

-- Kampfbeginn: sofort pausieren und Tastatur freigeben
function G.OnCombat()
    pause()
    setKeyboard(false)
end

-- Nur für Tests
function G.Debug()
    return { state = state, py = py, onGround = onGround, ducking = ducking, yards = yards(),
             obstacles = obstacles, speed = speed, canvas = canvas, overlay = overlay }
end

ns.RegisterGame(G)
