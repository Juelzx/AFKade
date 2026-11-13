-- AFKade – Spiel „Leylinien“ (Leitungs-Puzzle)
--
-- Ein Raster aus Leitungsstücken. Drehe die Teile, bis die Energie von der
-- Quelle in der Mitte jedes Teil erreicht und keine Leitung ins Leere zeigt.
-- Erzeugung: zufälliger Spannbaum über alle Felder (garantierte Lösung),
-- danach wird jedes Teil zufällig verdreht.

local _, ns = ...
local L, U = ns.L, ns.U

local G = {
    id = "pipes",
    name = L.GAME_PIPES,
    hint = L.HINT_PIPES,
    icon = ns.MEDIA .. "leylines",
    maxLevel = 100,
}

local BW, BH = ns.BOARD_W, ns.BOARD_H

-- Richtungen als Bits: 1 = Nord, 2 = Ost, 4 = Süd, 8 = West
local DIRS = {
    { bit = 1, dc = 0,  dr = -1, opp = 4 },
    { bit = 2, dc = 1,  dr = 0,  opp = 8 },
    { bit = 4, dc = 0,  dr = 1,  opp = 1 },
    { bit = 8, dc = -1, dr = 0,  opp = 2 },
}

local function has(m, b) return math.floor(m / b) % 2 == 1 end
local function rotCW(m) return (m * 2) % 16 + math.floor(m / 8) end
local function rotCCW(m) return rotCW(rotCW(rotCW(m))) end
local function arms(m)
    local n = 0
    for _, d in ipairs(DIRS) do if has(m, d.bit) then n = n + 1 end end
    return n
end

-- Rastergröße je Stufe (von -> bis innerhalb der Stufe)
local SIZES = {
    { { 4, 3 }, { 5, 4 } },
    { { 5, 4 }, { 6, 4 } },
    { { 6, 4 }, { 6, 5 } },
    { { 7, 5 }, { 7, 5 } },
    { { 7, 5 }, { 8, 5 } },
    { { 8, 6 }, { 8, 6 } },
}

local function size(level)
    local ti, f = ns.TierProgress(level)
    local a, b = SIZES[ti][1], SIZES[ti][2]
    return math.floor(a[1] + (b[1] - a[1] + 0.999) * f), math.floor(a[2] + (b[2] - a[2] + 0.999) * f)
end

---------------------------------------------------------------------------
-- Generator
---------------------------------------------------------------------------

local cache = {}

function G.Get(level)
    if cache[level] then return cache[level] end
    local w, h = size(level)
    local n = w * h
    local rng = ns.NewRNG(level * 6151 + 99991)
    local function idx(c, r) return (r - 1) * w + c end

    -- Zufälliger Spannbaum (Prim): verbindet alle Felder ohne Kreise
    local sol = {}
    for i = 1, n do sol[i] = 0 end
    local src = idx(math.ceil(w / 2), math.ceil(h / 2))
    local inTree, frontier, count = { [src] = true }, {}, 1
    local function addFrontier(i)
        local c, r = (i - 1) % w + 1, math.floor((i - 1) / w) + 1
        for _, d in ipairs(DIRS) do
            local nc, nr = c + d.dc, r + d.dr
            if nc >= 1 and nc <= w and nr >= 1 and nr <= h then
                local j = idx(nc, nr)
                if not inTree[j] then frontier[#frontier + 1] = { i, j, d } end
            end
        end
    end
    addFrontier(src)
    while count < n do
        local k = rng.int(1, #frontier)
        local e = frontier[k]
        frontier[k] = frontier[#frontier]
        frontier[#frontier] = nil
        if not inTree[e[2]] then
            sol[e[1]] = sol[e[1]] + e[3].bit
            sol[e[2]] = sol[e[2]] + e[3].opp
            inTree[e[2]] = true
            count = count + 1
            addFrontier(e[2])
        end
    end

    -- Verdrehen; Teile, die zufällig richtig liegen, meist nochmal drehen
    local start, par = {}, 0
    for i = 1, n do
        local m = sol[i]
        for _ = 1, rng.int(0, 3) do m = rotCW(m) end
        if m == sol[i] and rotCW(m) ~= m and rng.float() < 0.7 then
            repeat m = rotCW(m) until m ~= sol[i]
        end
        start[i] = m
        -- Mindestklicks für dieses Teil (links oder rechts herum)
        local probe = m
        for k = 0, 3 do
            if probe == sol[i] then
                par = par + math.min(k, 4 - k)
                break
            end
            probe = rotCW(probe)
        end
    end

    local p = { level = level, w = w, h = h, n = n, src = src, sol = sol, start = start, par = par }
    cache[level] = p
    return p
end

-- Wie viele Felder sind versorgt, wie viele Leitungen zeigen ins Leere?
local function evaluate(p, cur)
    local w, h = p.w, p.h
    local powered, queue, head = { [p.src] = true }, { p.src }, 1
    while head <= #queue do
        local i = queue[head]
        head = head + 1
        local c, r = (i - 1) % w + 1, math.floor((i - 1) / w) + 1
        for _, d in ipairs(DIRS) do
            if has(cur[i], d.bit) then
                local nc, nr = c + d.dc, r + d.dr
                if nc >= 1 and nc <= w and nr >= 1 and nr <= h then
                    local j = (nr - 1) * w + nc
                    if not powered[j] and has(cur[j], d.opp) then
                        powered[j] = true
                        queue[#queue + 1] = j
                    end
                end
            end
        end
    end
    local loose = 0
    for i = 1, p.n do
        local c, r = (i - 1) % w + 1, math.floor((i - 1) / w) + 1
        for _, d in ipairs(DIRS) do
            if has(cur[i], d.bit) then
                local nc, nr = c + d.dc, r + d.dr
                if nc < 1 or nc > w or nr < 1 or nr > h or not has(cur[(nr - 1) * w + nc], d.opp) then
                    loose = loose + 1
                end
            end
        end
    end
    return #queue, loose, powered
end
G.Evaluate = evaluate


---------------------------------------------------------------------------
-- Spielbrett
---------------------------------------------------------------------------

local COLOR = {
    power = { 0.35, 0.8, 1.0 },
    off = { 0.42, 0.42, 0.5 },
    good = { 0.35, 0.95, 0.45 },
    source = { 1.0, 0.82, 0.2 },
    crystalOn = { 0.8, 0.5, 1.0 },
    crystalOff = { 0.3, 0.22, 0.4 },
}

local kit, board
local cells = {}
local puzzle, cur
local solvedNow = false

local onClick

local function getCell(i)
    if cells[i] then return cells[i] end
    local b = CreateFrame("Button", nil, board)
    b:SetFrameLevel(board:GetFrameLevel() + 2)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.11, 0.10, 0.17, 1)
    b.arms = {}
    for k = 1, 4 do b.arms[k] = b:CreateTexture(nil, "ARTWORK") end
    b.hub = b:CreateTexture(nil, "ARTWORK", nil, 1)
    U.maskCircle(b, b.hub)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(bg)
    hl:SetColorTexture(1, 1, 1, 0.07)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, mouse) onClick(i, mouse) end)
    cells[i] = b
    return b
end

local function layoutCells()
    local w, h = puzzle.w, puzzle.h
    local cs = math.floor(math.min(BW / w, BH / h))
    local ox, oy = math.floor((BW - cs * w) / 2), math.floor((BH - cs * h) / 2)
    local t = math.max(4, math.floor(cs * 0.16))
    local half = cs / 2 + t / 2
    for i = 1, puzzle.n do
        local b = getCell(i)
        local c, r = (i - 1) % w + 1, math.floor((i - 1) / w) + 1
        b:SetSize(cs, cs)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", board, "TOPLEFT", ox + (c - 1) * cs, -(oy + (r - 1) * cs))
        local a = b.arms
        a[1]:ClearAllPoints(); a[1]:SetPoint("TOP"); a[1]:SetSize(t, half)
        a[2]:ClearAllPoints(); a[2]:SetPoint("RIGHT"); a[2]:SetSize(half, t)
        a[3]:ClearAllPoints(); a[3]:SetPoint("BOTTOM"); a[3]:SetSize(t, half)
        a[4]:ClearAllPoints(); a[4]:SetPoint("LEFT"); a[4]:SetSize(half, t)
        if i == puzzle.src then
            b.kind = "source"
        elseif arms(puzzle.sol[i]) == 1 then
            b.kind = "crystal"
        else
            b.kind = "pipe"
        end
        local hub = (b.kind == "source" and cs * 0.55) or (b.kind == "crystal" and cs * 0.42) or t * 1.6
        b.hub:ClearAllPoints()
        b.hub:SetPoint("CENTER")
        b.hub:SetSize(hub, hub)
        b:Show()
    end
    for i = puzzle.n + 1, #cells do cells[i]:Hide() end
end

local function redraw()
    local count, loose, powered = evaluate(puzzle, cur)
    solvedNow = count == puzzle.n and loose == 0
    local solved = kit.state and kit.state.solved
    local lit, crystals = 0, 0
    for i = 1, puzzle.n do
        local b = cells[i]
        local col = solved and COLOR.good or (powered[i] and COLOR.power or COLOR.off)
        for k, d in ipairs(DIRS) do
            if has(cur[i], d.bit) then
                b.arms[k]:Show()
                b.arms[k]:SetColorTexture(col[1], col[2], col[3], 1)
            else
                b.arms[k]:Hide()
            end
        end
        local hc = col
        if b.kind == "source" then
            hc = COLOR.source
        elseif b.kind == "crystal" then
            crystals = crystals + 1
            if powered[i] then lit = lit + 1 end
            hc = solved and COLOR.good or (powered[i] and COLOR.crystalOn or COLOR.crystalOff)
        end
        b.hub:SetColorTexture(hc[1], hc[2], hc[3], 1)
    end
    kit:SetStatus(L.CRYSTALS_FMT:format(lit, crystals), solvedNow)
end

onClick = function(i, mouse)
    if not kit:CanPlay() then return end
    if mouse == "RightButton" then
        cur[i] = rotCCW(cur[i])
        kit:Moved({ i, -1 })
    else
        cur[i] = rotCW(cur[i])
        kit:Moved({ i, 1 })
    end
    U.play("IG_MAINMENU_OPTION_CHECKBOX_OFF")
    redraw()
    kit:CheckSolved()
end

-- Gespeicherter Stand gültig? Jedes Teil muss eine Drehung der Lösung sein.
local function validState(s)
    if type(s) ~= "table" or #s ~= puzzle.n then return false end
    for i = 1, puzzle.n do
        local m, ok = puzzle.sol[i], false
        for _ = 1, 4 do
            if m == s[i] then ok = true end
            m = rotCW(m)
        end
        if not ok then return false end
    end
    return true
end

function G.Create(k, b)
    kit, board = k, b
end

function G.Load(k, level, saved)
    puzzle = G.Get(level)
    k.state.busy = false
    local accepted = validState(saved)
    cur = accepted and U.copy(saved) or U.copy(puzzle.start)
    layoutCells()
    redraw()
    return accepted
end

function G.Serialize() return U.copy(cur) end

function G.Undo(_, entry)
    local i = entry[1]
    cur[i] = (entry[2] == 1) and rotCCW(cur[i]) or rotCW(cur[i])
    redraw()
end

function G.IsSolved() return solvedNow end

function G.ShowSolved() redraw() end

-- Nur für Tests
function G.Debug() return puzzle, cur end
G.RotCW, G.RotCCW = rotCW, rotCCW

ns.RegisterGame(G)
