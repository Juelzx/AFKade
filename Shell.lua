-- AFKade – Hauptfenster mit Spielauswahl links
local _, ns = ...
local L, U = ns.L, ns.U
local UI = {}
ns.UI = UI

local SIDEBAR_W = 152
local CONTENT_W = 392
local FRAME_W, FRAME_H = SIDEBAR_W + 14 + CONTENT_W + 14, 458
local MIN_SCALE, MAX_SCALE = 0.7, 1.6

local frame
local programmaticHide = false
local panes, navButtons, kits = {}, {}, {}
local W = {}

---------------------------------------------------------------------------
-- Seitenleiste
---------------------------------------------------------------------------

local function navButton(key, label, icon, y, height)
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(SIDEBAR_W - 16, height)
    b:SetPoint("TOPLEFT", 8, y)

    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(1, 0.82, 0, 0.12)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(3)
    b.bar:SetColorTexture(1, 0.82, 0, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetSize(24, 24)
    ic:SetPoint("LEFT", 9, 0)
    ic:SetTexture(icon)
    U.iconCoords(ic, icon)

    local textW = SIDEBAR_W - 60
    b.label = U.text(b, "GameFontHighlight")
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    b.label:SetText(label)
    -- Lange Namen (z. B. "Hunting Season") nicht umbrechen, sondern kleiner setzen
    local sw = b.label:GetStringWidth()
    if sw and sw > textW then b.label:SetFontObject(GameFontHighlightSmall) end
    b.label:SetWidth(textW)
    if height > 32 then
        b.label:SetPoint("TOPLEFT", ic, "TOPRIGHT", 8, 1)
        b.sub = U.text(b, "GameFontHighlightSmall", 0.7, 0.7, 0.75)
        b.sub:SetPoint("BOTTOMLEFT", ic, "BOTTOMRIGHT", 8, -1)
        b.sub:SetWidth(textW)
        b.sub:SetJustifyH("LEFT")
        b.sub:SetWordWrap(false)
    else
        b.label:SetPoint("LEFT", ic, "RIGHT", 8, 0)
    end

    b:SetScript("OnClick", function() UI.ShowTab(key) end)
    navButtons[key] = b
    return b
end

function UI.RefreshSidebar()
    if not frame then return end
    for _, g in ipairs(ns.games) do
        local d = ns.GameData(g.id)
        if g.SidebarText then
            navButtons[g.id].sub:SetText(g.SidebarText(d))
        else
            navButtons[g.id].sub:SetText(L.CAMPAIGN_FMT:format(d.solved or 0, g.maxLevel))
        end
    end
end

---------------------------------------------------------------------------
-- Einstellungen & Statistik
---------------------------------------------------------------------------

local function fmtDuration(sec)
    sec = math.floor(sec or 0)
    local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
    if h > 0 then return ("%d h %d min"):format(h, m) end
    return ("%d min"):format(m)
end

local function buildSettingsPane(pane)
    local y = -2
    local checks = {}

    local function header(label)
        local h = U.text(pane, "GameFontNormal")
        h:SetPoint("TOPLEFT", 2, y)
        h:SetText(label)
        y = y - 22
    end

    local function check(key, label, onChange)
        local cb = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", 8, y + 4)
        local l = U.text(pane, "GameFontHighlight")
        l:SetPoint("LEFT", cb, "RIGHT", 4, 1)
        l:SetWidth(CONTENT_W - 44)
        l:SetJustifyH("LEFT")
        l:SetWordWrap(false)
        l:SetText(label)
        cb:SetScript("OnClick", function(self)
            ns.db.settings[key] = self:GetChecked() and true or false
            if onChange then onChange() end
        end)
        checks[key] = cb
        y = y - 26
    end

    header(L.SET_AUTO)
    check("taxi", L.SET_TAXI)
    check("transport", L.SET_TRANSPORT)
    check("afk", L.SET_AFK)
    check("queue", L.SET_QUEUE)
    check("dead", L.SET_DEAD)
    y = y - 8
    header(L.SET_BEHAVIOR)
    check("closeOnEnd", L.SET_CLOSE)
    check("hideCombat", L.SET_COMBAT)
    check("minimap", L.SET_MINIMAP, function() ns.MinimapButton.Refresh() end)

    -- Fenstergröße: [-] 100 % [+]
    local scaleTitle = U.text(pane, "GameFontHighlight")
    scaleTitle:SetPoint("TOPLEFT", 12, y - 2)
    scaleTitle:SetText(L.SET_SCALE)
    local minus = U.button(pane, "-", 24, 20)
    minus:SetPoint("LEFT", scaleTitle, "RIGHT", 10, 0)
    W.scaleLabel = U.text(pane, "GameFontHighlight")
    W.scaleLabel:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    W.scaleLabel:SetWidth(48)
    local plus = U.button(pane, "+", 24, 20)
    plus:SetPoint("LEFT", W.scaleLabel, "RIGHT", 4, 0)
    local scaleHint = U.text(pane, "GameFontDisableSmall")
    scaleHint:SetPoint("LEFT", plus, "RIGHT", 10, 0)
    scaleHint:SetText(L.SET_SCALE_HINT)
    minus:SetScript("OnClick", function() UI.SetScale((ns.db.settings.scale or 1) - 0.1) end)
    plus:SetScript("OnClick", function() UI.SetScale((ns.db.settings.scale or 1) + 0.1) end)
    y = y - 28

    local help = U.text(pane, "GameFontDisableSmall")
    help:SetPoint("BOTTOMLEFT", 2, 4)
    help:SetWidth(CONTENT_W - 4)
    help:SetJustifyH("LEFT")
    help:SetText(L.HELP)

    pane:SetScript("OnShow", function()
        for key, cb in pairs(checks) do cb:SetChecked(ns.db.settings[key]) end
        W.scaleLabel:SetText(("%d %%"):format(math.floor((ns.db.settings.scale or 1) * 100 + 0.5)))
    end)
end

---------------------------------------------------------------------------
-- Statistik: eine Karte pro Spiel
---------------------------------------------------------------------------

-- Standard für Rätselspiele: gelöst, Stufe des nächsten offenen Levels, Zeit
local function puzzleRows(g, d)
    local kit = kits[g.id]
    local allDone = (d.solved or 0) >= g.maxLevel
    local at = kit and kit:ResumeLevel() or 1
    local skipped = 0
    for l in pairs(d.skipped or {}) do
        local rec = d.levels[l]
        if not (rec and (rec.solved or (rec.stars or 0) > 0)) then skipped = skipped + 1 end
    end
    return {
        { L.STAT_SOLVED, ("%d / %d"):format(d.solved or 0, g.maxLevel) },
        { L.STAT_TIER, ns.TierName(at) },
        { L.STAT_NEXT, allDone and L.STAT_ALL_DONE or L.STAT_LEVEL_FMT:format(at) },
        { L.STAT_SKIPPED, skipped },
        { L.STAT_TIME, fmtDuration(ns.GameTime(d)) },
    }
end

local function statRows(g)
    local d = ns.GameData(g.id)
    if g.StatRows then return g.StatRows(d) end
    if g.maxLevel then return puzzleRows(g, d) end
    return {}
end

local function buildStatsPane(pane)
    local cards = {}
    local GAP = 10
    local CARD_W = (CONTENT_W - GAP) / 2
    local ROW_H = 18

    for i, g in ipairs(ns.games) do
        local c = CreateFrame("Frame", nil, pane)
        c:SetWidth(CARD_W)
        U.addBackdrop(c, { 0.25, 0.22, 0.32, 1 }, { 0.09, 0.08, 0.13, 1 })
        local ic = c:CreateTexture(nil, "ARTWORK")
        ic:SetSize(20, 20)
        ic:SetPoint("TOPLEFT", 8, -8)
        ic:SetTexture(g.icon)
        U.iconCoords(ic, g.icon)
        local title = U.text(c, "GameFontNormal")
        title:SetPoint("LEFT", ic, "RIGHT", 6, 0)
        title:SetWidth(CARD_W - 44)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(g.name)
        c.labels, c.values = {}, {}
        for r = 1, 6 do
            local l = U.text(c, "GameFontHighlightSmall", 0.75, 0.75, 0.8)
            l:SetPoint("TOPLEFT", 10, -36 - (r - 1) * ROW_H)
            local v = U.text(c, "GameFontHighlight")
            v:SetPoint("TOPRIGHT", -10, -34 - (r - 1) * ROW_H)
            c.labels[r], c.values[r] = l, v
        end
        cards[i] = c
    end

    local charLine = U.text(pane, "GameFontDisableSmall")
    charLine:SetPoint("BOTTOMLEFT", 2, 4)

    local function layout()
        -- Karten in zwei Spalten; Zeilenhöhe nach der längsten Karte der Reihe
        local y = 0
        for i = 1, #cards, 2 do
            local h = 0
            for j = i, math.min(i + 1, #cards) do
                local rows = statRows(ns.games[j])
                local c = cards[j]
                for r = 1, #c.labels do
                    local row = rows[r]
                    c.labels[r]:SetText(row and row[1] or "")
                    c.values[r]:SetText(row and tostring(row[2]) or "")
                end
                h = math.max(h, 42 + #rows * ROW_H)
            end
            for j = i, math.min(i + 1, #cards) do
                local c = cards[j]
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", ((j - i) * (CARD_W + GAP)) + 1, y - 1)
                c:SetHeight(h)
            end
            y = y - h - GAP
        end
        charLine:SetText(L.STATS_ACCOUNT)
    end
    pane:SetScript("OnShow", layout)
end

---------------------------------------------------------------------------
-- Hauptfenster
---------------------------------------------------------------------------

local function savePos()
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.db.pos = { point, relPoint, x, y }
end

-- Größte Stufe, bei der das Fenster noch ganz auf den Bildschirm passt
local function clampScale(s)
    local maxS = MAX_SCALE
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if w and h and w > 0 and h > 0 then
        maxS = math.max(MIN_SCALE, math.min(MAX_SCALE, w * 0.98 / FRAME_W, h * 0.98 / FRAME_H))
    end
    s = math.floor((tonumber(s) or 1) * 100 + 0.5) / 100
    return math.max(MIN_SCALE, math.min(maxS, s))
end

-- Fenster als Ganzes skalieren (Spiele, Texte und 3D-Modelle wachsen mit).
-- Die linke obere Ecke bleibt dabei an ihrer Stelle.
function UI.SetScale(s)
    s = clampScale(s)
    ns.db.settings.scale = s
    if W.scaleLabel then W.scaleLabel:SetText(("%d %%"):format(math.floor(s * 100 + 0.5))) end
    if not frame then return end
    local left, top, old = frame:GetLeft(), frame:GetTop(), frame:GetEffectiveScale()
    frame:SetScale(s)
    local new = frame:GetEffectiveScale()
    if left and top and old and new and new > 0 then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / new, top * old / new)
        savePos()
    end
end

local function restorePos()
    frame:ClearAllPoints()
    local p = ns.db.pos
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

function UI.LastGame()
    local id = ns.db.lastGame
    if id and ns.gameById[id] then return id end
    return ns.games[1].id
end

function UI.ShowTab(key)
    if not panes[key] then key = UI.LastGame() end
    for k, pane in pairs(panes) do pane:SetShown(k == key) end
    for k, b in pairs(navButtons) do
        b.sel:SetShown(k == key)
        b.bar:SetShown(k == key)
    end
    if ns.gameById[key] then ns.db.lastGame = key end
end

function UI.Create()
    if frame then return end
    frame = CreateFrame("Frame", "AFKadeFrame", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    U.addBackdrop(frame, { 0.42, 0.38, 0.52, 1 }, { 0.04, 0.04, 0.07, 0.95 })
    table.insert(UISpecialFrames, "AFKadeFrame") -- ESC schließt

    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT", -30, 0)
    drag:SetHeight(36)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePos()
    end)

    local title = U.text(frame, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(L.TITLE)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    -- Seitenleiste: Hintergrund + Trennlinie
    local side = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    side:SetPoint("TOPLEFT", 0, -38)
    side:SetPoint("BOTTOMLEFT", 0, 0)
    side:SetWidth(SIDEBAR_W)
    side:SetColorTexture(0.08, 0.07, 0.12, 1)
    local divider = frame:CreateTexture(nil, "BORDER")
    divider:SetPoint("TOPLEFT", SIDEBAR_W, -38)
    divider:SetPoint("BOTTOMLEFT", SIDEBAR_W, 0)
    divider:SetWidth(1)
    divider:SetColorTexture(0.42, 0.38, 0.52, 0.8)

    local function newPane()
        local pane = CreateFrame("Frame", nil, frame)
        pane:SetPoint("TOPLEFT", SIDEBAR_W + 14, -46)
        pane:SetPoint("BOTTOMRIGHT", -14, 10)
        pane:Hide()
        return pane
    end

    -- Spiele
    local y = -48
    for _, g in ipairs(ns.games) do
        navButton(g.id, g.name, g.icon, y, 40)
        local pane = newPane()
        panes[g.id] = pane
        if g.Build then
            g.Build(pane) -- eigenes Layout (z. B. Murloc-Sprint)
        else
            kits[g.id] = ns.LevelKit.New(pane, g)
        end
        y = y - 44
    end

    -- Einstellungen
    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", 12, y - 4)
    sep:SetSize(SIDEBAR_W - 24, 1)
    sep:SetColorTexture(1, 1, 1, 0.12)
    navButton("stats", L.NAV_STATS, ns.MEDIA .. "stats", y - 12, 30)
    panes.stats = newPane()
    buildStatsPane(panes.stats)
    navButton("settings", L.NAV_SETTINGS, ns.MEDIA .. "settings", y - 46, 30)
    panes.settings = newPane()
    buildSettingsPane(panes.settings)

    -- Ziehgriff unten rechts: Fenster größer/kleiner ziehen
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 50)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.GRIP_TIP, 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    grip:SetScript("OnMouseDown", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local left, top = frame:GetLeft(), frame:GetTop()
            local eff, parentEff = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
            if not (left and top and eff and parentEff) then return end
            local cx, cy = GetCursorPosition()
            -- gewünschte Größe in Bildschirmpunkten -> Skalierung
            local want = math.max((cx - left * eff) / FRAME_W, (top * eff - cy) / FRAME_H)
            local s = clampScale(want / parentEff)
            if s ~= ns.db.settings.scale then UI.SetScale(s) end
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        savePos()
    end)

    frame:SetScript("OnShow", UI.RefreshSidebar)
    frame:SetScript("OnHide", function()
        if not programmaticHide then ns.OnUserClosed() end
    end)

    frame:SetScale(clampScale(ns.db.settings.scale or 1))
    restorePos()
    UI.ShowTab(UI.LastGame())
end

function UI.IsShown()
    return frame ~= nil and frame:IsShown()
end

function UI.Open(tab)
    if not frame then return end
    if tab then UI.ShowTab(tab) end
    frame:Show()
end

-- Vom Addon selbst geschlossen (Anlass vorbei, Kampf) – kein Nutzer-Klick
function UI.Close()
    if frame and frame:IsShown() then
        programmaticHide = true
        frame:Hide()
        programmaticHide = false
    end
end

function UI.Toggle()
    if UI.IsShown() then frame:Hide() else UI.Open() end
end

function UI.ResetPosition()
    ns.db.pos = nil
    ns.db.settings.scale = 1
    if frame then
        frame:SetScale(1)
        if W.scaleLabel then W.scaleLabel:SetText("100 %") end
        restorePos()
    end
end

-- Nur für Tests
function UI.Kit(id) return kits[id] end
