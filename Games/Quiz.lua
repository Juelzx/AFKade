-- AFKade – Spiel „Azeroth-Quiz“
--
-- Runden zu 10 Fragen, ohne Zeitlimit. Drei Fragetypen:
--   Bosse:        3D-Modell eines Bosses -> richtigen Dungeon/Raid wählen
--   Gegenstände:  echter Tooltip eines Classic-Gegenstands, eine Zahl fehlt
--   Wissen:       handgeschriebene Fragen über Azeroth
-- Bosse und Gegenstände kommen live aus dem Spiel (Modelle, Tooltips).
-- /ade quizcheck prüft, welche Bosse und Gegenstände der Client kennt.

local _, ns = ...
local L, U = ns.L, ns.U
local QD = ns.QuizData

local G = {
    id = "quiz",
    name = L.GAME_QUIZ,
    icon = ns.MEDIA .. "quiz",
}

local ROUND = 10
local RECENT = 40
local MODES = { "mixed", "boss", "tooltip", "lore" }
local BLANK = "|cffffd100?|r"

local isDE = GetLocale and GetLocale() == "deDE"
local GetItemInfoF = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local pane, W = nil, {}
local mode = "mixed"
local round -- { n, correct, streak, best, done }
local q     -- aktuelle Frage
local recent, recentSet = {}, {}

local function data() return ns.GameData(G.id) end

function G.InitData(d)
    d.answered = d.answered or 0
    d.correct = d.correct or 0
    d.bestStreak = d.bestStreak or 0
    d.rounds = d.rounds or 0
    d.perfect = d.perfect or 0
end

function G.MergeData(dst, src)
    for _, k in ipairs({ "answered", "correct", "rounds", "perfect" }) do
        dst[k] = (dst[k] or 0) + (src[k] or 0)
    end
    dst.bestStreak = math.max(dst.bestStreak or 0, src.bestStreak or 0)
end

local function accuracy(d)
    return d.answered > 0 and math.floor(d.correct / d.answered * 100 + 0.5) or 0
end

function G.SidebarText(d)
    return L.QUIZ_SIDEBAR_FMT:format(d.bestStreak or 0)
end

function G.StatRows(d)
    return {
        { L.STAT_ACCURACY, L.STAT_PCT_FMT:format(accuracy(d)) },
        { L.STAT_STREAK, U.fmtInt(d.bestStreak) },
        { L.STAT_ANSWERED, U.fmtInt(d.answered) },
        { L.STAT_PERFECT, U.fmtInt(d.perfect) },
    }
end

---------------------------------------------------------------------------
-- Hilfen
---------------------------------------------------------------------------

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function remember(key)
    recent[#recent + 1] = key
    recentSet[key] = true
    if #recent > RECENT then
        recentSet[table.remove(recent, 1)] = nil
    end
end

local function instName(key)
    local inst = QD.instances[key]
    return inst and (isDE and inst.de or inst.en) or key
end

-- Antworten mischen; liefert Optionen und Index der richtigen
local function options(correct, wrong)
    local list = { correct }
    for i = 1, 3 do list[#list + 1] = wrong[i] end
    shuffle(list)
    for i, v in ipairs(list) do
        if v == correct then return list, i end
    end
end

---------------------------------------------------------------------------
-- Gegenstände: Tooltip lesen (eigener, unsichtbarer Tooltip)
---------------------------------------------------------------------------

local scan
local function requestItem(id)
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
    else
        pcall(GetItemInfoF, id)
    end
end

-- Liefert { name, icon, lines = { {left, right, lc, rc}, ... } } oder nil (noch nicht geladen)
function G.ReadItem(id)
    local ok, name = pcall(GetItemInfoF, id)
    if not ok or not name or ns.IsSecret(name) then
        requestItem(id)
        return nil
    end
    if not scan then
        scan = CreateFrame("GameTooltip", "AFKadeScanTooltip", nil, "GameTooltipTemplate")
    end
    scan:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
    scan:ClearLines()
    if not pcall(scan.SetHyperlink, scan, "item:" .. id) then return nil end
    local lines = {}
    for i = 1, (scan:NumLines() or 0) do
        local l, r = _G["AFKadeScanTooltipTextLeft" .. i], _G["AFKadeScanTooltipTextRight" .. i]
        local lt = l and l:GetText()
        if lt and not ns.IsSecret(lt) and lt ~= "" then
            local rt = r and r:IsShown() and r:GetText() or nil
            if rt and (ns.IsSecret(rt) or rt == "") then rt = nil end
            local lr, lg, lb = l:GetTextColor()
            local rr, rg, rb = 1, 1, 1
            if r then rr, rg, rb = r:GetTextColor() end
            lines[#lines + 1] = { left = lt, right = rt, lc = { lr or 1, lg or 1, lb or 1 }, rc = { rr or 1, rg or 1, rb or 1 } }
        end
    end
    scan:Hide()
    if #lines < 2 then return nil end
    local icon
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if info then
        local okI, _, _, _, _, ic = pcall(info, id)
        if okI then icon = ic end
    end
    return { name = name, icon = icon, lines = lines }
end

-- Zeilen, deren Zahlen keine guten Fragen sind (Haltbarkeit, Preis, Gegenstandsstufe …)
local SKIP = { "Durability", "Haltbarkeit", "Sell Price", "Verkaufspreis", "Item Level", "Gegenstandsstufe" }
local function skipLine(text)
    for _, g in ipairs({ DURABILITY_TEMPLATE, ITEM_LEVEL, SELL_PRICE }) do
        local prefix = type(g) == "string" and g:match("^([^%%]+)")
        if prefix and #prefix > 2 and text:find(prefix, 1, true) then return true end
    end
    for _, w in ipairs(SKIP) do
        if text:find(w, 1, true) then return true end
    end
    return false
end

-- Drei falsche Werte, die deutlich vom richtigen abweichen (mind. ~25 %),
-- damit man mit etwas Spielwissen raten kann. Gleiche Nachkommastellen,
-- Vielfache von 5 bleiben Vielfache von 5.
function G.Distractors(str)
    local v = tonumber(str)
    local dec = str:match("%.(%d+)$")
    local seen, cands = { [str] = true }, {}
    local function add(nv)
        if nv and not seen[nv] then
            seen[nv] = true
            cands[#cands + 1] = nv
        end
    end
    if dec then
        for _, m in ipairs({ 0.6, 0.75, 1.3, 1.5, 1.8 }) do
            add(("%." .. #dec .. "f"):format(math.max(0.1, v * m)))
        end
    elseif v <= 4 then
        for _, d in ipairs({ 1, 2, 3, -1, -2 }) do
            if v + d >= 1 then add(tostring(v + d)) end
        end
    else
        local step = (v % 5 == 0) and 5 or 1
        for _, m in ipairs({ 0.5, 0.75, 1.3, 1.5, 2 }) do
            -- vom richtigen Wert weg runden, damit der Abstand groß bleibt
            local x = v * m / step
            local n = ((m < 1) and math.floor(x) or math.ceil(x)) * step
            add(tostring(math.max(1, n)))
        end
    end
    shuffle(cands)
    local out = { cands[1], cands[2], cands[3] }
    local k = 1
    while #out < 3 do
        local nv = dec and ("%." .. #dec .. "f"):format(v + k) or tostring(v + k * 2)
        if not seen[nv] then seen[nv] = true out[#out + 1] = nv end
        k = k + 1
    end
    return out
end

-- Zeilen, die zu schwer sind: Rüstung, Schadensbereich, Schaden pro Sekunde
local HARD = { "Armor", "Rüstung", "per second", "pro Sekunde" }
local function hardLine(text)
    if text:find("%d+ %- %d+") then return true end
    for _, w in ipairs(HARD) do
        if text:find(w, 1, true) then return true end
    end
    return false
end

-- Bevorzugt: Bonuswerte ("+15 Stärke") und Effekte ("Equip:", "Use:", "Chance on hit:")
local function niceLine(text)
    return text:find("^%+") ~= nil or text:find(":", 1, true) ~= nil
end

local function blankNumber(cands)
    return cands[math.random(1, #cands)]
end

local function makeItem()
    local pool = shuffle(U.copy(QD.items))
    for _, id in ipairs(pool) do
        local key = "i" .. id
        if not recentSet[key] then
            local item = G.ReadItem(id)
            if item then
                -- Kandidaten: jede Zahl in einer Zeile ab Zeile 2 (Zeile 1 = Name)
                local cands, nice = {}, {}
                for li = 2, #item.lines do
                    local line = item.lines[li]
                    for _, side in ipairs({ "left", "right" }) do
                        local text = line[side]
                        if text and not skipLine(text) and not hardLine(text) then
                            for s, num, e in text:gmatch("()(%d+%.?%d*)()") do
                                if not (num:find("%.$")) then
                                    local c = { li = li, side = side, s = s, e = e, num = num }
                                    cands[#cands + 1] = c
                                    if niceLine(text) then nice[#nice + 1] = c end
                                end
                            end
                        end
                    end
                end
                if #nice > 0 then cands = nice end
                if #cands > 0 then
                    local c = blankNumber(cands)
                    local lines = {}
                    for li, line in ipairs(item.lines) do
                        local copy = { left = line.left, right = line.right, lc = line.lc, rc = line.rc }
                        if li == c.li then
                            local t = line[c.side]
                            copy[c.side] = t:sub(1, c.s - 1) .. BLANK .. t:sub(c.e)
                        end
                        lines[li] = copy
                    end
                    local opts, correct = options(c.num, G.Distractors(c.num))
                    remember(key)
                    return { kind = "item", key = key, prompt = L.QUIZ_PROMPT_ITEM, options = opts, correct = correct,
                             item = { name = item.name, icon = item.icon, lines = lines }, reveal = item.name }
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Zauber: Beschreibung live aus dem Spiel
---------------------------------------------------------------------------

local function requestSpell(id)
    if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, id) end
end

-- Liefert { name, icon, rank, desc } oder nil
function G.ReadSpell(id)
    local name, rank, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" then name, icon = info.name, info.iconID end
    end
    if not name and GetSpellInfo then
        local ok, n, r, ic = pcall(GetSpellInfo, id)
        if ok then name, rank, icon = n, r, ic end
    end
    if not name or ns.IsSecret(name) then requestSpell(id) return nil end
    local getDesc = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    if not getDesc then return nil end
    local ok, desc = pcall(getDesc, id)
    if not ok or type(desc) ~= "string" or ns.IsSecret(desc) or desc == "" then requestSpell(id) return nil end
    if not rank or rank == "" then
        local getSub = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
        if getSub then
            local okS, sub = pcall(getSub, id)
            if okS and type(sub) == "string" and not ns.IsSecret(sub) then rank = sub end
        end
    end
    return { name = name, icon = icon, rank = (rank ~= "" and rank) or nil, desc = desc }
end

local function makeSpell()
    local pool = shuffle(U.copy(QD.spells))
    for _, id in ipairs(pool) do
        local key = "s" .. id
        if not recentSet[key] then
            local sp = G.ReadSpell(id)
            if sp then
                local cands = {}
                for s, num, e in sp.desc:gmatch("()(%d+%.?%d*)()") do
                    if not num:find("%.$") then cands[#cands + 1] = { s = s, e = e, num = num } end
                end
                if #cands > 0 then
                    local c = blankNumber(cands)
                    local desc = sp.desc:sub(1, c.s - 1) .. BLANK .. sp.desc:sub(c.e)
                    local lines = { { left = sp.name, right = sp.rank, lc = { 1, 1, 1 }, rc = { 0.6, 0.6, 0.6 } },
                                    { left = desc, lc = { 1, 0.82, 0 }, rc = { 1, 1, 1 } } }
                    local opts, correct = options(c.num, G.Distractors(c.num))
                    remember(key)
                    return { kind = "spell", key = key, prompt = L.QUIZ_PROMPT_SPELL, options = opts, correct = correct,
                             item = { name = sp.name, icon = sp.icon, lines = lines }, reveal = sp.name }
                end
            end
        end
    end
end

-- Tooltips: meistens Zauber, sonst Gegenstände
local function makeTooltip()
    if math.random() < 0.6 then return makeSpell() or makeItem() end
    return makeItem() or makeSpell()
end

---------------------------------------------------------------------------
-- Bosse und Wissen
---------------------------------------------------------------------------

local function makeBoss()
    local pool = shuffle(U.copy(QD.bosses))
    for _, b in ipairs(pool) do
        local key = "b" .. b[1]
        if not recentSet[key] then
            local raid = QD.instances[b[3]].r or false
            local wrong = {}
            local keys = {}
            for k, inst in pairs(QD.instances) do
                if k ~= b[3] and (inst.r or false) == raid then keys[#keys + 1] = k end
            end
            table.sort(keys)
            shuffle(keys)
            for i = 1, 3 do wrong[i] = instName(keys[i]) end
            local opts, correct = options(instName(b[3]), wrong)
            remember(key)
            return { kind = "boss", key = key, prompt = L.QUIZ_PROMPT_BOSS, options = opts, correct = correct,
                     creature = b[1], reveal = b[2] .. " – " .. instName(b[3]) }
        end
    end
end

local function makeLore()
    local pool = {}
    for i = 1, #QD.lore do pool[i] = i end
    shuffle(pool)
    for _, i in ipairs(pool) do
        local key = "l" .. i
        if not recentSet[key] then
            local entry = QD.lore[i]
            local ans = isDE and entry[4] or entry[3]
            local opts, correct = options(ans[1], { ans[2], ans[3], ans[4] })
            remember(key)
            return { kind = "lore", key = key, prompt = isDE and entry[2] or entry[1], options = opts, correct = correct,
                     reveal = ans[1] }
        end
    end
end

local MAKERS = { boss = makeBoss, tooltip = makeTooltip, lore = makeLore }
local PREFIX = { boss = "b", tooltip = "is", lore = "l" }

-- Kürzlich gestellte Fragen eines Typs vergessen (Präfixe b / i+s / l)
local function forgetKind(kind)
    local prefixes = PREFIX[kind] or kind:sub(1, 1)
    local keep = {}
    for _, key in ipairs(recent) do
        if prefixes:find(key:sub(1, 1), 1, true) then recentSet[key] = nil else keep[#keep + 1] = key end
    end
    recent = keep
end

local function nextQuestion()
    local order
    if mode == "mixed" then
        order = shuffle({ "boss", "tooltip", "lore" })
    else
        -- gewählter Typ: lieber eine Frage wiederholen als den Typ wechseln
        local made = MAKERS[mode]()
        if not made then
            forgetKind(mode)
            made = MAKERS[mode]()
        end
        if made then return made end
        order = { "boss", "lore" } -- z. B. Gegenstandsdaten noch nicht geladen
    end
    for _, kind in ipairs(order) do
        local made = MAKERS[kind]()
        if made then return made end
    end
    -- alles kürzlich gestellt: Gedächtnis leeren und nochmal
    recent, recentSet = {}, {}
    return MAKERS[order[1]]() or makeLore()
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

local function setButtonColor(b, state)
    if state == "correct" then
        b.bg:SetColorTexture(0.12, 0.42, 0.16, 1)
        b.border:SetColorTexture(0.35, 0.9, 0.4, 1)
    elseif state == "wrong" then
        b.bg:SetColorTexture(0.45, 0.1, 0.1, 1)
        b.border:SetColorTexture(1, 0.35, 0.35, 1)
    elseif state == "hover" then
        b.bg:SetColorTexture(0.18, 0.16, 0.27, 1)
        b.border:SetColorTexture(1, 0.82, 0, 1)
    else
        b.bg:SetColorTexture(0.1, 0.09, 0.15, 1)
        b.border:SetColorTexture(0.32, 0.29, 0.42, 1)
    end
end

local BOX_W, BOX_MAX_H = 270, 166

-- Boss-Modelle: Kamera weiter weg, damit auch große Bosse ganz ins Bild passen
local BOSS_ZOOM = 2.2
local function fitModel(m)
    pcall(m.SetPortraitZoom, m, 0)
    pcall(m.SetCamDistanceScale, m, m.zoom or BOSS_ZOOM)
end

local function showItem(item)
    local box = W.itemBox
    box.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local n = math.min(#item.lines, #box.left)
    local h = 12
    for i = 1, #box.left do
        local l, r = box.left[i], box.right[i]
        local line = item.lines[i]
        if i <= n then
            -- lange Zeilen umbrechen, damit die Lücke immer sichtbar ist
            l:SetWidth(line.right and (BOX_W - 90) or (BOX_W - 16))
            l:SetText(line.left)
            l:SetTextColor(line.lc[1], line.lc[2], line.lc[3])
            r:SetText(line.right or "")
            r:SetTextColor(line.rc[1], line.rc[2], line.rc[3])
            l:Show()
            r:Show()
            h = h + math.max(12, l:GetStringHeight() or 12) + 2
        else
            l:Hide()
            r:Hide()
        end
    end
    box:SetHeight(h)
    -- sehr lange Tooltips verkleinern statt über die Antworten zu ragen
    box:SetScale(math.min(1, BOX_MAX_H / h))
    box:Show()
end

local function drawHeader()
    W.counter:SetText(L.QUIZ_Q_FMT:format(math.min(round.n, ROUND), ROUND))
    W.streak:SetText(L.QUIZ_STREAK_FMT:format(round.streak, data().bestStreak))
    for _, m in ipairs(MODES) do
        local b = W.modes[m]
        if m == mode then b:LockHighlight() else b:UnlockHighlight() end
        b:SetEnabled(m ~= mode)
    end
end

local function showQuestion()
    W.model:Hide()
    W.itemBox:Hide()
    W.lore:Hide()
    W.summary:Hide()
    W.feedback:SetText("")
    W.next:Hide()
    W.zoomHint:SetShown(q.kind == "boss")
    W.prompt:SetText(q.prompt)
    if q.kind == "boss" then
        W.prompt:SetText(q.prompt)
        W.model:Show()
        W.model.zoom = BOSS_ZOOM
        pcall(W.model.SetCreature, W.model, q.creature)
        fitModel(W.model)
        W.model.facing = 0.4
        pcall(W.model.SetFacing, W.model, W.model.facing)
    elseif q.kind == "item" or q.kind == "spell" then
        showItem(q.item)
    else
        W.prompt:SetText("")
        W.lore:SetText(q.prompt)
        W.lore:Show()
    end
    for i, b in ipairs(W.answers) do
        b.label:SetText(q.options[i])
        b:Enable()
        b:Show()
        setButtonColor(b, nil)
    end
    drawHeader()
end

local function showSummary()
    W.zoomHint:Hide()
    W.model:Hide()
    W.itemBox:Hide()
    W.lore:Hide()
    W.prompt:SetText("")
    for _, b in ipairs(W.answers) do b:Hide() end
    local perfect = round.correct == ROUND
    W.summary:SetText(L.QUIZ_ROUND_FMT:format(round.correct, ROUND) .. "\n\n"
        .. (perfect and ("|cff4dff66" .. L.QUIZ_PERFECT .. "|r\n") or "")
        .. L.QUIZ_ROUND_STREAK_FMT:format(round.best))
    W.summary:Show()
    W.feedback:SetText("")
    W.next:SetText(L.QUIZ_NEW_ROUND)
    W.next:Show()
    drawHeader()
end

local function newRound()
    round = { n = 1, correct = 0, streak = 0, best = 0 }
    q = nextQuestion()
    showQuestion()
end

local function answer(i)
    if not q or q.answered then return end
    q.answered = true
    local d = data()
    d.answered = d.answered + 1
    local right = (i == q.correct)
    if right then
        d.correct = d.correct + 1
        round.correct = round.correct + 1
        round.streak = round.streak + 1
        round.best = math.max(round.best, round.streak)
        d.bestStreak = math.max(d.bestStreak, round.streak)
        W.feedback:SetText("|cff4dff66" .. L.QUIZ_CORRECT .. "|r  " .. q.reveal)
        U.play("IG_QUEST_LIST_COMPLETE")
    else
        round.streak = 0
        W.feedback:SetText("|cffff6666" .. L.QUIZ_WRONG .. "|r  " .. q.reveal)
        U.play("IG_QUEST_FAILED")
    end
    for j, b in ipairs(W.answers) do
        b:Disable()
        if j == q.correct then
            setButtonColor(b, "correct")
        elseif j == i then
            setButtonColor(b, "wrong")
        end
    end
    W.next:SetText(round.n >= ROUND and L.QUIZ_RESULTS or L.QUIZ_NEXT)
    W.next:Show()
    drawHeader()
    ns.UI.RefreshSidebar()
end

local function advance()
    if not round or round.done then
        newRound()
        return
    end
    if round.n >= ROUND then
        round.done = true
        local d = data()
        d.rounds = d.rounds + 1
        if round.correct == ROUND then d.perfect = d.perfect + 1 end
        showSummary()
        ns.UI.RefreshSidebar()
        return
    end
    round.n = round.n + 1
    q = nextQuestion()
    showQuestion()
end

local function setMode(m)
    mode = m
    newRound()
end

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------

function G.Build(p)
    pane = p
    local CW = 392

    -- Modus-Leiste
    W.modes = {}
    for i, m in ipairs(MODES) do
        local b = U.button(pane, L["QUIZ_MODE_" .. m:upper()], 94, 22)
        b:SetPoint("TOPLEFT", (i - 1) * 99, -2)
        b:SetScript("OnClick", function() setMode(m) end)
        W.modes[m] = b
    end

    W.counter = U.text(pane, "GameFontNormal")
    W.counter:SetPoint("TOPLEFT", 2, -34)
    W.streak = U.text(pane, "GameFontHighlightSmall", 0.8, 0.8, 0.85)
    W.streak:SetPoint("TOPRIGHT", -2, -35)

    -- Inhaltsfläche
    local content = CreateFrame("Frame", nil, pane)
    content:SetSize(CW, 196)
    content:SetPoint("TOPLEFT", 0, -54)
    U.addBackdrop(content, { 0.25, 0.22, 0.32, 1 }, { 0.06, 0.055, 0.09, 1 })
    W.content = content

    W.prompt = U.text(content, "GameFontNormal")
    W.prompt:SetPoint("TOP", 0, -8)
    W.prompt:SetWidth(CW - 20)

    W.model = CreateFrame("PlayerModel", nil, content)
    W.model:SetSize(CW - 40, 166)
    W.model:SetPoint("BOTTOM", 0, 4)
    -- nach dem Laden setzt WoW die Kamera zurück: dann nochmal einpassen
    pcall(W.model.SetScript, W.model, "OnModelLoaded", fitModel)
    -- Mausrad: selbst zoomen
    W.model:EnableMouseWheel(true)
    W.model:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = math.max(1, math.min(5, (self.zoom or BOSS_ZOOM) - delta * 0.3))
        fitModel(self)
    end)
    W.zoomHint = U.text(content, "GameFontDisableSmall")
    W.zoomHint:SetPoint("BOTTOMRIGHT", -6, 4)
    W.zoomHint:SetText(L.QUIZ_ZOOM_HINT)
    W.zoomHint:Hide()
    W.model:SetScript("OnUpdate", function(self, elapsed)
        self.facing = (self.facing or 0) + elapsed * 0.35
        pcall(self.SetFacing, self, self.facing)
    end)
    W.model:Hide()

    -- Tooltip-Nachbau
    local box = CreateFrame("Frame", nil, content)
    box:SetWidth(BOX_W)
    box:SetPoint("TOP", 14, -28)
    U.addBackdrop(box, { 0.55, 0.55, 0.6, 1 }, { 0.03, 0.03, 0.08, 0.96 })
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetSize(30, 30)
    box.icon:SetPoint("TOPRIGHT", box, "TOPLEFT", -4, 0)
    box.left, box.right = {}, {}
    for i = 1, 16 do
        local l = U.text(box, "GameFontHighlightSmall")
        if i == 1 then
            l:SetPoint("TOPLEFT", 8, -6)
        else
            l:SetPoint("TOPLEFT", box.left[i - 1], "BOTTOMLEFT", 0, -2)
        end
        l:SetJustifyH("LEFT")
        l:SetWordWrap(true)
        local r = U.text(box, "GameFontHighlightSmall")
        r:SetPoint("TOP", l, "TOP")
        r:SetPoint("RIGHT", box, "RIGHT", -8, 0)
        r:SetJustifyH("RIGHT")
        box.left[i], box.right[i] = l, r
    end
    box:Hide()
    W.itemBox = box

    W.lore = U.text(content, "GameFontHighlightLarge")
    W.lore:SetPoint("CENTER")
    W.lore:SetWidth(CW - 40)
    W.lore:Hide()

    W.summary = U.text(content, "GameFontHighlightLarge")
    W.summary:SetPoint("CENTER")
    W.summary:SetWidth(CW - 40)
    W.summary:Hide()

    -- Antworten 2 × 2
    W.answers = {}
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, pane)
        b:SetSize(194, 38)
        b:SetPoint("TOPLEFT", ((i - 1) % 2) * 198, -258 - math.floor((i - 1) / 2) * 42)
        b.border = b:CreateTexture(nil, "BACKGROUND", nil, -8)
        b.border:SetPoint("TOPLEFT", -1, 1)
        b.border:SetPoint("BOTTOMRIGHT", 1, -1)
        b.bg = b:CreateTexture(nil, "BACKGROUND", nil, -7)
        b.bg:SetAllPoints()
        b.label = U.text(b, "GameFontHighlight")
        b.label:SetPoint("CENTER")
        b.label:SetWidth(184)
        b:SetScript("OnClick", function() answer(i) end)
        b:SetScript("OnEnter", function(self) if self:IsEnabled() then setButtonColor(self, "hover") end end)
        b:SetScript("OnLeave", function(self) if self:IsEnabled() then setButtonColor(self, nil) end end)
        setButtonColor(b, nil)
        W.answers[i] = b
    end

    W.feedback = U.text(pane, "GameFontHighlight")
    W.feedback:SetPoint("TOPLEFT", 2, -348)
    W.feedback:SetWidth(CW - 124)
    W.feedback:SetJustifyH("LEFT")
    W.next = U.button(pane, L.QUIZ_NEXT, 112, 24)
    W.next:SetPoint("TOPRIGHT", 0, -344)
    W.next:SetScript("OnClick", advance)
    W.next:Hide()

    -- Gegenstände vorladen, damit sie bereitstehen
    for _, id in ipairs(QD.items) do requestItem(id) end
    for _, id in ipairs(QD.spells) do requestSpell(id) end

    pane:SetScript("OnShow", function()
        if not round then newRound() else drawHeader() end
    end)
end

---------------------------------------------------------------------------
-- /ade quizcheck: welche Bosse und Gegenstände kennt dieser Client?
---------------------------------------------------------------------------

local function creatureName(id)
    if not scan then scan = CreateFrame("GameTooltip", "AFKadeScanTooltip", nil, "GameTooltipTemplate") end
    scan:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
    scan:ClearLines()
    if not pcall(scan.SetHyperlink, scan, ("unit:Creature-0-0-0-0-%d-0000000000"):format(id)) then return nil end
    local l = _G.AFKadeScanTooltipTextLeft1
    local t = l and l:GetText()
    scan:Hide()
    if t and not ns.IsSecret(t) and t ~= "" then return t end
end

function G.Check()
    local bosses = QD.bosses
    local result = { time = date and date("%Y-%m-%d %H:%M") or "", noModel = {}, nameMismatch = {}, noName = {}, noItem = {} }
    ns.Print(L.QUIZ_CHECK_START:format(math.ceil(#bosses * 0.8 + 3)))
    for _, id in ipairs(QD.items) do requestItem(id) end
    for _, id in ipairs(QD.spells) do requestSpell(id) end
    -- sichtbar auf dem Bildschirm (fast durchsichtig), sonst lädt WoW das Modell nicht
    local m = CreateFrame("PlayerModel", nil, UIParent)
    m:SetSize(96, 96)
    m:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
    m:SetFrameStrata("TOOLTIP")
    m:SetAlpha(0.05)
    m:Show()
    local canCheckModel = type(m.GetModelFileID) == "function"
    if not canCheckModel then result.modelCheck = "GetModelFileID not available" end
    local i = 0
    local function step()
        if i > 0 then
            local b = bosses[i]
            if canCheckModel then
                local okF, fileID = pcall(m.GetModelFileID, m)
                if not (okF and fileID and fileID ~= 0) then
                    result.noModel[#result.noModel + 1] = b[1] .. " " .. b[2]
                end
            end
            local name = creatureName(b[1])
            if not name then
                result.noName[#result.noName + 1] = b[1] .. " " .. b[2]
            elseif not isDE and name ~= b[2] then
                result.nameMismatch[#result.nameMismatch + 1] = b[1] .. " expected '" .. b[2] .. "' got '" .. name .. "'"
            end
        end
        i = i + 1
        if i <= #bosses then
            pcall(m.SetCreature, m, bosses[i][1])
            creatureName(bosses[i][1]) -- Namen schon mal anfragen
            C_Timer.After(0.8, step)
            return
        end
        m:Hide()
        local itemsOK = 0
        for _, id in ipairs(QD.items) do
            if G.ReadItem(id) then itemsOK = itemsOK + 1 else result.noItem[#result.noItem + 1] = id end
        end
        local spellsOK = 0
        result.noSpell = {}
        for _, id in ipairs(QD.spells) do
            local sp = G.ReadSpell(id)
            if sp and sp.desc:find("%d") then spellsOK = spellsOK + 1 else result.noSpell[#result.noSpell + 1] = id end
        end
        result.spells = spellsOK .. "/" .. #QD.spells
        result.models = (#bosses - #result.noModel) .. "/" .. #bosses
        result.items = itemsOK .. "/" .. #QD.items
        ns.db.quizcheck = result
        ns.Print(L.QUIZ_CHECK_DONE_FMT:format(#bosses - #result.noModel, #bosses, itemsOK, #QD.items,
            #result.nameMismatch, #result.noName))
        local function list(title, t)
            if #t == 0 then return end
            ns.Print(title .. " (" .. #t .. "): " .. table.concat(t, ", ", 1, math.min(#t, 12)) .. (#t > 12 and " …" or ""))
        end
        list("No model", result.noModel)
        list("Name mismatch", result.nameMismatch)
        list("Missing items", result.noItem)
        ns.Print(("Spells with usable text: %s"):format(result.spells))
        list("Missing spells", result.noSpell)
    end
    step()
end

ns.RegisterGame(G)
