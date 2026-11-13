-- AFKade – Kern: Helfer, Spiele-Registry, Speicherstände,
-- Auslöser (Flug, Schiff, AFK, Tod) und Slash-Befehle
local ADDON, ns = ...
local L = ns.L

ns.BOARD_W, ns.BOARD_H = 380, 280
-- Eigene Icons (64×64 TGA) im Addon-Ordner
ns.MEDIA = "Interface\\AddOns\\AFKade\\Media\\"

local DEFAULTS = {
    taxi = true,
    transport = true,
    queue = true,
    afk = true,
    dead = false,
    closeOnEnd = true,
    hideCombat = true,
    minimap = true,
    photographer = false,
    scale = 1,
}

---------------------------------------------------------------------------
-- Allgemeine Helfer
---------------------------------------------------------------------------

function ns.Print(msg)
    print("|cff66ccff" .. L.TITLE .. ":|r " .. msg)
end

function ns.IsSecret(v)
    return (issecretvalue and issecretvalue(v)) and true or false
end

local function bool(v)
    if ns.IsSecret(v) then return false end
    return v and true or false
end
ns.Bool = bool

-- Zufall (Park-Miller): auf jedem Client identisch -> gleiche Level für alle
function ns.NewRNG(seed)
    local s = math.floor(seed) % 2147483646 + 1
    local r = {}
    function r.next()
        s = (16807 * s) % 2147483647
        return s
    end
    function r.float() return (r.next() - 1) / 2147483646 end
    function r.int(a, b) return a + (r.next() % (b - a + 1)) end
    return r
end

---------------------------------------------------------------------------
-- Stufen (für alle Spiele mit 100 Leveln gleich)
---------------------------------------------------------------------------

ns.TIERS = {
    { last = 10,  color = "ffb4b4b4" },
    { last = 25,  color = "ff1eff00" },
    { last = 45,  color = "ff3d9bff" },
    { last = 65,  color = "ffb05cff" },
    { last = 85,  color = "ffff8000" },
    { last = 100, color = "ffe6cc80" },
}

function ns.TierIndex(level)
    for i, t in ipairs(ns.TIERS) do
        if level <= t.last then return i end
    end
    return #ns.TIERS
end

-- Stufe und Position innerhalb der Stufe (0..1)
function ns.TierProgress(level)
    local ti = ns.TierIndex(level)
    local first = (ti > 1) and (ns.TIERS[ti - 1].last + 1) or 1
    local last = ns.TIERS[ti].last
    return ti, (last > first) and (level - first) / (last - first) or 0
end

function ns.TierName(level)
    local i = ns.TierIndex(level)
    return "|c" .. ns.TIERS[i].color .. L["TIER" .. i] .. "|r"
end

---------------------------------------------------------------------------
-- Spiele
---------------------------------------------------------------------------

ns.games, ns.gameById = {}, {}

function ns.RegisterGame(def)
    ns.games[#ns.games + 1] = def
    ns.gameById[def.id] = def
end

function ns.GameData(id)
    return ns.char.games[id]
end

-- Nur Level-Spiele zählen für "gelöst" (Murloc-Sprint hat keine Level)
function ns.MaxSolved()
    local n = 0
    for _, g in ipairs(ns.games) do n = n + (g.maxLevel or 0) end
    return n
end

local function isSolved(rec)
    return rec ~= nil and (rec.solved or (rec.stars or 0) > 0)
end

function ns.RecalcTotals()
    local total = 0
    for _, g in ipairs(ns.games) do
        if g.maxLevel then
            local d = ns.char.games[g.id]
            local s = 0
            for _, rec in pairs(d.levels) do
                if isSolved(rec) then s = s + 1 end
            end
            d.solved = s
            total = total + s
        end
    end
    ns.char.solved = total
end

-- Rätselzeit eines Spiels; ältere Spielstände ohne Zähler: Summe der Bestzeiten
function ns.GameTime(d)
    if not d.time then
        local t = 0
        for _, rec in pairs(d.levels or {}) do t = t + (rec.bestTime or 0) end
        d.time = t
    end
    return d.time
end

-- Gibt zurück: erstmals gelöst?, weniger Züge als bisher?
function ns.RecordSolve(id, level, moves, seconds)
    local d = ns.char.games[id]
    local rec = d.levels[level]
    local first = not isSolved(rec)
    rec = rec or {}
    d.levels[level] = rec
    local improved = not first and rec.bestMoves ~= nil and moves < rec.bestMoves
    rec.solved, rec.stars = true, nil
    rec.bestMoves = math.min(rec.bestMoves or moves, moves)
    d.time = ns.GameTime(d) + seconds
    rec.bestTime = math.min(rec.bestTime or seconds, seconds)

    local st = ns.char.stats
    st.solves = st.solves + 1
    st.moves = st.moves + moves
    st.time = st.time + seconds
    if bool(UnitOnTaxi("player")) then st.airSolves = st.airSolves + 1 end

    ns.RecalcTotals()
    return first, improved
end

local function normalize(c)
    c.games = c.games or {}
    for _, g in ipairs(ns.games) do
        local d = c.games[g.id] or {}
        if g.maxLevel then d.levels = d.levels or {} end
        if g.InitData then g.InitData(d) end
        c.games[g.id] = d
    end
    c.stats = c.stats or {}
    for _, k in ipairs({ "solves", "airSolves", "flights", "moves", "time" }) do
        c.stats[k] = c.stats[k] or 0
    end
    return c
end

-- Rätselspiel: gelöste Level vereinen, jeweils die besseren Werte behalten
local function mergeLevels(dst, src)
    dst.time = ns.GameTime(dst) + ns.GameTime(src)
    for l, rec in pairs(src.levels) do
        local mine = dst.levels[l]
        if not mine then
            dst.levels[l] = rec
        else
            mine.solved = (isSolved(mine) or isSolved(rec)) or nil
            if mine.solved then mine.stars = nil end
            mine.bestMoves = math.min(mine.bestMoves or rec.bestMoves or 0, rec.bestMoves or mine.bestMoves or 0)
            mine.bestTime = math.min(mine.bestTime or rec.bestTime or 0, rec.bestTime or mine.bestTime or 0)
        end
    end
    dst.unlocked = math.max(dst.unlocked or 1, src.unlocked or 1)
    dst.progress = nil -- erreichtes Level neu berechnen
    if (src.lastLevel or 0) > (dst.lastLevel or 0) then dst.lastLevel = src.lastLevel end
    dst.current = dst.current or src.current
    if src.skipped then
        dst.skipped = dst.skipped or {}
        for l, v in pairs(src.skipped) do dst.skipped[l] = v end
    end
end

local function mergeProgress(dst, src)
    for _, g in ipairs(ns.games) do
        local a, b = dst.games[g.id], src.games[g.id]
        if g.maxLevel then
            mergeLevels(a, b)
        elseif g.MergeData then
            g.MergeData(a, b)
        end
    end
    for k, v in pairs(src.stats) do
        if type(v) == "number" then dst.stats[k] = (dst.stats[k] or 0) + v end
    end
end

local function initDB()
    AFKadeDB = AFKadeDB or {}
    local db = AFKadeDB
    db.settings = db.settings or {}
    for k, v in pairs(DEFAULTS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    db.photos = db.photos or {}
    ns.db = db

    -- Fortschritt gilt für den ganzen Account (alle Charaktere teilen ihn)
    db.progress = db.progress or {}
    local c = normalize(db.progress)
    -- Ältere Versionen speicherten pro Charakter: einmalig übernehmen
    local old = AFKadeCharDB
    if type(old) == "table" and type(old.games) == "table" and not old.movedToAccount then
        mergeProgress(c, normalize(old))
        old.movedToAccount = true
    end
    ns.char = c
    ns.RecalcTotals()
end

---------------------------------------------------------------------------
-- Auslöser: Flug, Schiff/Zeppelin, AFK, Tod
---------------------------------------------------------------------------

local trig = { active = false, autoOpened = false, taxi = false }
local transport = { on = false, moving = 0, still = 0 }
local hiddenByCombat

-- Schiff/Zeppelin: Es gibt keine API dafür. Erkennung über die Position:
-- Du bewegst dich über die Karte, ohne selbst zu laufen oder zu fliegen.
local function updateTransport()
    local ok, y, x, _, inst = pcall(UnitPosition, "player")
    if not ok or x == nil or ns.IsSecret(x) or ns.IsSecret(y) then
        transport.on, transport.lastX = false, nil
        return
    end
    local now = GetTime()
    if transport.lastX and transport.inst == inst then
        local dt = now - transport.t
        if dt > 0 then
            local dx, dy = x - transport.lastX, y - transport.lastY
            local speed = math.sqrt(dx * dx + dy * dy) / dt
            local sOk, unitSpeed = pcall(GetUnitSpeed, "player")
            local selfMoving = (sOk and not ns.IsSecret(unitSpeed) and (unitSpeed or 0) > 0)
                or bool(IsFalling and IsFalling()) or bool(UnitOnTaxi("player"))
            if not selfMoving and speed > 2.5 and speed < 80 then
                transport.moving, transport.still = transport.moving + 1, 0
            elseif speed < 0.3 then
                transport.still, transport.moving = transport.still + 1, 0
            else
                transport.moving = 0
            end
            if not transport.on and transport.moving >= 3 then
                transport.on = true
            elseif transport.on and transport.still >= 4 then
                transport.on = false
            end
        end
    else
        transport.moving, transport.still = 0, 0
    end
    transport.lastX, transport.lastY, transport.inst, transport.t = x, y, inst, now
end

-- Schlachtfeld-Warteschlange: "queued" = wartet, "confirm" = Einladung liegt vor
local function battlefieldState()
    if type(GetBattlefieldStatus) ~= "function" then return false, false end
    local queued, invite = false, false
    for i = 1, (MAX_BATTLEFIELD_QUEUES or 3) do
        local ok, status = pcall(GetBattlefieldStatus, i)
        if ok and not ns.IsSecret(status) then
            if status == "queued" then queued = true end
            if status == "confirm" then invite = true end
        end
    end
    return queued, invite
end

local function evaluateTriggers()
    if not ns.db then return end
    local s = ns.db.settings

    local taxi = bool(UnitOnTaxi("player"))
    if taxi and not trig.taxi then ns.char.stats.flights = ns.char.stats.flights + 1 end
    trig.taxi = taxi

    local afk = bool(UnitIsAFK("player"))
    local dead = bool(UnitIsDead("player")) and not bool(UnitIsGhost("player"))
    local queued, invite = battlefieldState()
    local active = (s.taxi and taxi) or (s.transport and transport.on)
        or (s.afk and afk) or (s.dead and dead) or (s.queue and queued) or false

    -- Einladung ins Schlachtfeld: automatisch geöffnetes Fenster sofort schließen,
    -- damit das Einladungsfenster frei ist (Fortschritt bleibt)
    if invite and trig.autoOpened and ns.UI.IsShown() then
        ns.UI.Close()
        trig.autoOpened = false
    end

    if active and not trig.active then
        if not ns.UI.IsShown() and not (s.hideCombat and InCombatLockdown()) then
            trig.autoOpened = true
            ns.UI.Open(ns.UI.LastGame())
        end
    elseif not active and trig.active then
        if trig.autoOpened and s.closeOnEnd then ns.UI.Close() end
        trig.autoOpened = false
    end
    trig.active = active
end

local function tick()
    if ns.db.settings.transport then
        updateTransport()
    else
        transport.on = false
    end
    evaluateTriggers()
end

-- Vom Spieler geschlossen (X, ESC, Slash): nicht automatisch wieder öffnen
function ns.OnUserClosed()
    trig.autoOpened = false
    hiddenByCombat = nil
end

local function onCombatStart()
    for _, g in ipairs(ns.games) do
        if g.OnCombat then g.OnCombat() end
    end
    if ns.db.settings.hideCombat and ns.UI.IsShown() then
        hiddenByCombat = { auto = trig.autoOpened }
        ns.UI.Close()
    end
end

local function onCombatEnd()
    if not hiddenByCombat then return end
    local wasAuto = hiddenByCombat.auto
    hiddenByCombat = nil
    if wasAuto and not trig.active then return end
    trig.autoOpened = wasAuto
    ns.UI.Open()
end

---------------------------------------------------------------------------
-- Events & Slash-Befehle
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON then initDB() end
    elseif event == "PLAYER_LOGIN" then
        ns.UI.Create()
        ns.MinimapButton.Create()
        for _, e in ipairs({
            "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
            "PLAYER_FLAGS_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
            "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "UPDATE_BATTLEFIELD_STATUS",
            "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED",
        }) do
            self:RegisterEvent(e)
        end
        C_Timer.NewTicker(1, tick)
    elseif event == "PLAYER_REGEN_DISABLED" then
        onCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        onCombatEnd()
    elseif event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
        ns.Photographer.OnEvent(event)
    else
        evaluateTriggers()
    end
end)

SLASH_AFKADE1 = "/afkade"
SLASH_AFKADE2 = "/ade"
SlashCmdList.AFKADE = function(input)
    local msg, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if msg == "reset" then
        ns.UI.ResetPosition()
    elseif msg == "scale" or msg == "size" or msg == "groesse" or msg == "größe" then
        local n = tonumber((arg or ""):gsub("%%", "")
            :gsub(",", "."):match("[%d%.]+") or "")
        if n then
            if n > 3 then n = n / 100 end -- "120" oder "1.2"
            ns.UI.SetScale(n)
        end
        ns.Print(L.SCALE_FMT:format(math.floor((ns.db.settings.scale or 1) * 100 + 0.5)))
    elseif msg == "settings" or msg == "config" then
        ns.UI.Open("settings")
    elseif msg == "stats" or msg == "statistik" then
        ns.UI.Open("stats")
    elseif msg == "photo" or msg == "foto" then
        ns.Photographer.Toggle()
    elseif msg == "snap" then
        ns.Photographer.Snap()
    elseif msg == "quizcheck" and ns.gameById.quiz then
        ns.gameById.quiz.Check()
    elseif msg == "hitbox" and ns.gameById.hunt then
        ns.gameById.hunt.ToggleHitbox()
    elseif msg == "minimap" then
        ns.db.settings.minimap = not ns.db.settings.minimap
        ns.MinimapButton.Refresh()
    elseif ns.gameById[msg] then
        ns.UI.Open(msg)
    elseif msg == "help" then
        ns.Print(L.HELP)
    else
        ns.UI.Toggle()
    end
end
