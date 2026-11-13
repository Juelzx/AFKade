-- AFKade – Baukasten für Level-Spiele
--
-- Jedes Spielmodul liefert nur das Spielbrett und die Regeln. Alles andere
-- ist hier gemeinsam: Kopfzeile mit freier Level-Auswahl, Fortschritt,
-- Ergebnis-Overlay, Zurück/Neustart und Zwischenstand. Ohne Zeitlimit und
-- ohne Sterne – gelöste Level bekommen einfach einen Haken.
--
-- Ein Spielmodul (def) braucht:
--   id, name, icon, hint, maxLevel
--   Create(kit, board)                einmalig, Brett-Elemente anlegen
--   Load(kit, level, saved) -> bool   Level aufbauen (saved akzeptiert?)
--   Serialize() -> Daten              für den Zwischenstand
--   Undo(kit, entry)                  einen Zug rückgängig machen
--   IsSolved() -> bool                ShowSolved(kit)
--   Update(kit, elapsed), OnPause(kit) (optional)
-- Während des Spiels ruft das Modul kit:CanPlay(), kit:Moved(entry),
-- kit:CheckSolved() und kit:SetStatus(text, ok) auf.

local _, ns = ...
local L = ns.L
local BW, BH = ns.BOARD_W, ns.BOARD_H

---------------------------------------------------------------------------
-- Gemeinsame UI-Helfer
---------------------------------------------------------------------------

local U = {}
ns.U = U

-- WoW-Icons haben einen eingebauten Rand, der abgeschnitten wird; eigene Icons nicht
function U.iconCoords(tex, path)
    if type(path) == "string" and path:find(ns.MEDIA, 1, true) == 1 then
        tex:SetTexCoord(0, 1, 0, 1)
    else
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end
U.BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
U.MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
U.CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"

function U.styleText(fs, r, g, b)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

function U.text(parent, template, r, g, b)
    return U.styleText(parent:CreateFontString(nil, "OVERLAY", template), r, g, b)
end

function U.addBackdrop(f, border, bg)
    local b = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    b:SetPoint("TOPLEFT", -1, 1)
    b:SetPoint("BOTTOMRIGHT", 1, -1)
    b:SetColorTexture(border[1], border[2], border[3], border[4])
    local t = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    t:SetAllPoints()
    t:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
end

function U.button(parent, label, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(label)
    return b
end

function U.play(key)
    if SOUNDKIT and SOUNDKIT[key] then pcall(PlaySound, SOUNDKIT[key]) end
end

function U.copy(t)
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    return c
end

function U.maskCircle(owner, tex)
    local m = owner:CreateMaskTexture()
    m:SetAllPoints(tex)
    m:SetTexture(U.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(m)
end

-- 12345 -> "12,345" bzw. "12.345"
function U.fmtInt(n)
    local sep = L.THOUSANDS
    local out = tostring(math.floor(n or 0)):reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
    if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
    return out
end

---------------------------------------------------------------------------
-- Kit
---------------------------------------------------------------------------

local Kit = {}
ns.LevelKit = Kit
local K = {}
K.__index = K

function Kit.New(pane, def)
    local k = setmetatable({ pane = pane, def = def, W = {} }, K)
    k:Build()
    pane:SetScript("OnShow", function() k:OnShow() end)
    pane:SetScript("OnHide", function() k:OnHide() end)
    return k
end

function K:Data()
    return ns.GameData(self.def.id)
end

function K:Build()
    local pane, W, def = self.pane, self.W, self.def
    local text, button = U.text, U.button

    -- Kopfzeile: Stufe | < Level > | gelöst-Haken
    W.tier = text(pane, "GameFontNormal")
    W.tier:SetPoint("TOPLEFT", 2, -5)
    W.solved = text(pane, "GameFontNormal", 0.4, 1, 0.5)
    W.solved:SetPoint("TOPRIGHT", -2, -5)
    W.level = text(pane, "GameFontHighlight")
    W.level:SetPoint("TOP", 0, -5)
    W.prev = button(pane, "<", 26, 20)
    W.prev:SetPoint("RIGHT", W.level, "LEFT", -8, 0)
    W.prev:SetScript("OnClick", function() self:LoadLevel(self.state.level - 1) end)
    W.next = button(pane, ">", 26, 20)
    W.next:SetPoint("LEFT", W.level, "RIGHT", 8, 0)
    W.next:SetScript("OnClick", function() self:LoadLevel(self.state.level + 1) end)

    local pb = CreateFrame("StatusBar", nil, pane)
    pb:SetSize(BW - 120, 6)
    pb:SetPoint("TOPLEFT", 6, -29)
    pb:SetStatusBarTexture(U.BAR_TEX)
    pb:SetStatusBarColor(0.58, 0.0, 0.55)
    pb:SetMinMaxValues(0, def.maxLevel)
    U.addBackdrop(pb, { 0, 0, 0, 1 }, { 0.15, 0.14, 0.18, 1 })
    W.progress = pb
    W.progressText = text(pane, "GameFontHighlightSmall", 0.8, 0.8, 0.85)
    W.progressText:SetPoint("LEFT", pb, "RIGHT", 8, 0)

    -- Spielbrett
    local board = CreateFrame("Frame", nil, pane)
    board:SetSize(BW, BH)
    board:SetPoint("TOP", 0, -42)
    U.addBackdrop(board, { 0.25, 0.22, 0.32, 1 }, { 0.07, 0.06, 0.11, 1 })
    board:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
    self.board = board
    def.Create(self, board)

    -- Ergebnis
    local ov = CreateFrame("Frame", nil, board)
    ov:SetAllPoints()
    ov:SetFrameLevel(board:GetFrameLevel() + 30)
    ov:EnableMouse(true)
    local shade = ov:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.62)
    local title = text(ov, "GameFontNormalHuge", 0.4, 1, 0.5)
    title:SetPoint("CENTER", 0, 50)
    title:SetText(L.SOLVED)
    W.ovStats = text(ov, "GameFontHighlight")
    W.ovStats:SetPoint("CENTER", 0, 16)
    W.ovExtra = text(ov, "GameFontNormal", 1, 0.82, 0)
    W.ovExtra:SetPoint("CENTER", 0, -8)
    W.ovExtra:SetWidth(BW - 40)
    W.ovReplay = button(ov, L.REPLAY, 120, 24)
    W.ovReplay:SetPoint("CENTER", -66, -50)
    W.ovReplay:SetScript("OnClick", function() self:Restart() end)
    W.ovNext = button(ov, L.NEXT_LEVEL, 120, 24)
    W.ovNext:SetPoint("CENTER", 66, -50)
    W.ovNext:SetScript("OnClick", function() self:LoadLevel(self:NextLevel(self.state.level)) end)
    ov:Hide()
    self.overlay = ov

    -- Zeile 1: Status | Züge
    W.status = text(pane, "GameFontHighlight")
    W.status:SetPoint("TOPLEFT", board, "BOTTOMLEFT", 2, -10)
    W.moves = text(pane, "GameFontHighlight", 0.85, 0.85, 0.9)
    W.moves:SetPoint("TOPRIGHT", board, "BOTTOMRIGHT", -2, -10)

    -- Zeile 2: Überspringen, Zurück, Neustart
    W.restart = button(pane, L.RESTART, 104)
    W.restart:SetPoint("TOPRIGHT", board, "BOTTOMRIGHT", 0, -32)
    W.restart:SetScript("OnClick", function() self:Restart() end)
    W.undo = button(pane, L.UNDO, 104)
    W.undo:SetPoint("RIGHT", W.restart, "LEFT", -4, 0)
    W.undo:SetScript("OnClick", function() self:Undo() end)
    W.skip = button(pane, L.SKIP_LEVEL, 104)
    W.skip:SetPoint("RIGHT", W.undo, "LEFT", -4, 0)
    W.skip:SetScript("OnClick", function() self:Skip() end)

    local hint = text(pane, "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", board, "BOTTOMLEFT", 2, -64)
    hint:SetWidth(BW)
    hint:SetJustifyH("LEFT")
    hint:SetText(def.hint)
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

local function isSolvedRec(rec)
    return rec ~= nil and (rec.solved or (rec.stars or 0) > 0)
end
Kit.IsSolvedRec = isSolvedRec

function K:UpdateStatus()
    local st, W = self.state, self.W
    W.moves:SetText(L.MOVES_FMT:format(st.moves))
    W.undo:SetEnabled(#st.history > 0 and not st.solved)
    W.restart:SetEnabled(st.moves > 0 and not st.solved)
    W.skip:SetEnabled(not st.solved and st.level < self.def.maxLevel)
end

function K:UpdateHeader()
    local d, lvl, W = self:Data(), self.state.level, self.W
    W.level:SetText(L.LEVEL_FMT:format(lvl, self.def.maxLevel))
    W.tier:SetText(ns.TierName(lvl))
    if isSolvedRec(d.levels[lvl]) then
        W.solved:SetText(U.CHECK .. " " .. L.SOLVED_BADGE)
    elseif d.skipped and d.skipped[lvl] then
        W.solved:SetText("|cff9d9d9d" .. L.SKIPPED_BADGE .. "|r")
    else
        W.solved:SetText("")
    end
    -- Vor und zurück nur innerhalb der erreichten Level
    W.prev:SetEnabled(lvl > 1)
    W.next:SetEnabled(lvl < self:Unlocked())
    W.progress:SetValue(d.solved or 0)
    W.progressText:SetText(L.CAMPAIGN_FMT:format(d.solved or 0, self.def.maxLevel))
end

function K:SetStatus(msg, ok)
    self.W.status:SetText(msg)
    if ok then
        self.W.status:SetTextColor(0.4, 1, 0.5)
    else
        self.W.status:SetTextColor(1, 0.45, 0.45)
    end
end

---------------------------------------------------------------------------
-- Ablauf
---------------------------------------------------------------------------

-- Höchstes erreichtes Level (durch Lösen oder Überspringen freigeschaltet).
-- Ältere Spielstände: einmalig aus gelösten Leveln und letztem Level berechnen.
function K:Unlocked()
    local d, max = self:Data(), self.def.maxLevel
    if (d.progress or 0) < 2 then
        local u = d.unlocked or 1
        for l, rec in pairs(d.levels) do
            if isSolvedRec(rec) then u = math.max(u, l + 1) end
        end
        if d.lastLevel then u = math.max(u, d.lastLevel) end
        d.unlocked, d.progress = math.min(u, max), 2
    end
    return math.max(1, math.min(d.unlocked or 1, max))
end

function K:Unlock(level)
    local d = self:Data()
    d.unlocked = math.max(self:Unlocked(), math.min(level, self.def.maxLevel))
end

-- Level offen lassen und zum nächsten
function K:Skip()
    local st = self.state
    if not st or st.busy or st.solved or st.level >= self.def.maxLevel then return end
    local d = self:Data()
    if not isSolvedRec(d.levels[st.level]) then
        d.skipped = d.skipped or {}
        d.skipped[st.level] = true
    end
    self:Unlock(st.level + 1)
    self:LoadLevel(st.level + 1)
end

function K:FirstUnsolved()
    local d = self:Data()
    for l = 1, self.def.maxLevel do
        if not isSolvedRec(d.levels[l]) then return l end
    end
    return 1
end

-- Kampagne: nächstes offenes Level nach `level` (gelöste werden übersprungen)
function K:NextLevel(level)
    local d, top = self:Data(), self:Unlocked()
    for l = level + 1, top do
        if not isSolvedRec(d.levels[l]) then return l end
    end
    for l = 1, level - 1 do
        if not isSolvedRec(d.levels[l]) then return l end
    end
    return math.min(level + 1, top)
end

-- Wo geht's beim Öffnen weiter? Zuletzt gespieltes Level – war das schon
-- gelöst (und nicht angefangen), dann das nächste offene.
function K:ResumeLevel()
    local d = self:Data()
    local l = d.lastLevel
    if not l then return self:FirstUnsolved() end
    if isSolvedRec(d.levels[l]) and not (d.current and d.current.level == l) then
        return self:NextLevel(l)
    end
    return l
end

function K:SaveCurrent()
    local st = self.state
    if not st then return end
    local d = self:Data()
    if st.solved or st.moves == 0 then
        if d.current and d.current.level == st.level then d.current = nil end
        return
    end
    d.current = { level = st.level, data = self.def.Serialize(), moves = st.moves, time = st.time }
end

function K:LoadLevel(level)
    self:SaveCurrent()
    local d = self:Data()
    level = math.max(1, math.min(level or 1, self:Unlocked()))
    local st = { level = level, moves = 0, time = 0, history = {}, solved = false }
    self.state = st
    local cur = d.current
    local saved
    if cur and cur.level == level then
        saved, st.moves, st.time = cur.data, cur.moves or 0, cur.time or 0
    end
    d.lastLevel = level
    if not self.def.Load(self, level, saved) then
        st.moves, st.time = 0, 0
    end
    self.overlay:Hide()
    self:UpdateHeader()
    self:UpdateStatus()
end

function K:CanPlay()
    local st = self.state
    return st ~= nil and not st.solved and not st.busy
end

function K:Moved(entry)
    local st = self.state
    st.history[#st.history + 1] = entry
    st.moves = st.moves + 1
    self:UpdateStatus()
end

function K:CheckSolved()
    local st = self.state
    if st and not st.solved and self.def.IsSolved() then self:Solved() end
end

function K:Solved()
    local st, W, def = self.state, self.W, self.def
    st.solved = true
    -- Statistik abgesichert: ein Fehler darf das Brett nicht blockieren
    local ok, _, improved = pcall(ns.RecordSolve, def.id, st.level, st.moves, st.time)
    local err = not ok and _ or nil
    local d = self:Data()
    if d.skipped then d.skipped[st.level] = nil end
    self:Unlock(st.level + 1)
    local nextLevel = self:NextLevel(st.level)
    d.lastLevel = nextLevel -- beim nächsten Öffnen geht's hier weiter
    pcall(def.ShowSolved, self)
    self:UpdateHeader()
    self:UpdateStatus()
    W.ovStats:SetText(L.SOLVED_MOVES:format(st.moves))
    local extra = ""
    if (d.solved or 0) >= def.maxLevel then
        extra = L.ALL_DONE
    elseif improved then
        extra = L.NEW_BEST
    end
    W.ovExtra:SetText(extra)
    W.ovNext:SetShown(nextLevel ~= st.level)
    self.overlay:Show()
    U.play("IG_QUEST_LIST_COMPLETE")
    self:SaveCurrent()
    ns.UI.RefreshSidebar()
    if err and geterrorhandler then geterrorhandler()(err) end
end

function K:Undo()
    if not self:CanPlay() then return end
    local entry = table.remove(self.state.history)
    if not entry then return end
    self.def.Undo(self, entry)
    self:UpdateStatus()
end

function K:Restart()
    local old = self.state
    if not old or old.busy then return end
    self.state = { level = old.level, moves = 0, time = 0, history = {}, solved = false }
    self:Data().lastLevel = old.level -- bewusst nochmal: hier bleiben
    self.def.Load(self, old.level, nil)
    self.overlay:Hide()
    self:UpdateHeader()
    self:UpdateStatus()
    self:SaveCurrent()
end

function K:OnShow()
    local st, d = self.state, self:Data()
    -- Erster Start oder Level zuletzt gelöst: direkt mit dem nächsten weitermachen
    if not st or (st.solved and d.lastLevel and d.lastLevel ~= st.level) then
        self:LoadLevel(self:ResumeLevel())
        return
    end
    self:UpdateHeader()
end

function K:OnHide()
    if self.def.OnPause then self.def.OnPause(self) end
    self:SaveCurrent()
end

-- Spielzeit läuft nur still für die Statistik mit
function K:OnUpdate(elapsed)
    local st = self.state
    if not st then return end
    if not st.solved then st.time = st.time + elapsed end
    if self.def.Update then self.def.Update(self, elapsed) end
end
