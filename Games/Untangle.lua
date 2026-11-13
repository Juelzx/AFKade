-- AFKade – Spiel „Entwirren“ (Leylocked-Chest-Rätsel)
--
-- Kugeln sind durch Linien verbunden. Tausche Kugeln, bis sich keine
-- Linie mehr kreuzt. Jedes Level wird aus einem festen Seed erzeugt:
--   1. Kugel-Plätze zufällig mit Mindestabstand verteilen
--   2. Ring durch alle Plätze + kreuzungsfreie Sehnen -> garantierte Lösung
--   3. Kugeln durch zufällige Tausche mischen

local _, ns = ...
local L, U = ns.L, ns.U

local G = {
    id = "untangle",
    name = L.GAME_UNTANGLE,
    hint = L.HINT_UNTANGLE,
    icon = ns.MEDIA .. "untangle",
    maxLevel = 100,
}

local BW, BH = ns.BOARD_W, ns.BOARD_H
local R = 11
local MARGIN = 24
local CLEARANCE = R * 1.8
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- Kugelanzahl und Liniendichte je Stufe (steigt innerhalb der Stufe an)
local SHAPE = {
    { nodes = { 5, 6 },   degree = { 2.0, 2.2 } },
    { nodes = { 7, 8 },   degree = { 2.2, 2.5 } },
    { nodes = { 9, 10 },  degree = { 2.5, 2.8 } },
    { nodes = { 11, 12 }, degree = { 2.8, 3.0 } },
    { nodes = { 13, 14 }, degree = { 3.0, 3.2 } },
    { nodes = { 15, 16 }, degree = { 3.2, 3.4 } },
}

local function config(level)
    local ti, f = ns.TierProgress(level)
    local t = SHAPE[ti]
    local n = math.floor(t.nodes[1] + (t.nodes[2] - t.nodes[1] + 0.999) * f)
    local degree = t.degree[1] + (t.degree[2] - t.degree[1]) * f
    local progress = (level - 1) / (G.maxLevel - 1)
    return {
        nodes = n,
        edges = math.floor(n * degree / 2 + 0.5),
        maxDegree = (ti >= 5) and 5 or 4,
        swaps = math.max(2, math.floor(n * (0.35 + 0.65 * progress) + 0.5)),
        minConflicts = math.max(2, math.floor(n * 0.5)),
    }
end

---------------------------------------------------------------------------
-- Geometrie
---------------------------------------------------------------------------

local function orient(ax, ay, bx, by, cx, cy)
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
end

local function segmentsCross(ax, ay, bx, by, cx, cy, dx, dy)
    local d1 = orient(cx, cy, dx, dy, ax, ay)
    local d2 = orient(cx, cy, dx, dy, bx, by)
    local d3 = orient(ax, ay, bx, by, cx, cy)
    local d4 = orient(ax, ay, bx, by, dx, dy)
    return ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0))
       and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0))
end

local function pointSegDist(px, py, ax, ay, bx, by)
    local vx, vy = bx - ax, by - ay
    local len2 = vx * vx + vy * vy
    local t = 0
    if len2 > 0 then t = ((px - ax) * vx + (py - ay) * vy) / len2 end
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = ax + vx * t - px, ay + vy * t - py
    return math.sqrt(qx * qx + qy * qy)
end

-- Konflikte: sich kreuzende Linien + Linien durch fremde Kugeln
local function evaluate(puzzle, pos)
    local slots, edges, n = puzzle.slots, puzzle.edges, puzzle.n
    local bad, count = {}, 0
    local touch = R + 1
    for i = 1, #edges do
        local e = edges[i]
        local a, b = slots[pos[e[1]]], slots[pos[e[2]]]
        for j = i + 1, #edges do
            local f = edges[j]
            if f[1] ~= e[1] and f[1] ~= e[2] and f[2] ~= e[1] and f[2] ~= e[2] then
                local c, d = slots[pos[f[1]]], slots[pos[f[2]]]
                if segmentsCross(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y) then
                    count = count + 1
                    bad[i], bad[j] = true, true
                end
            end
        end
        for node = 1, n do
            if node ~= e[1] and node ~= e[2] then
                local s = slots[pos[node]]
                if pointSegDist(s.x, s.y, a.x, a.y, b.x, b.y) < touch then
                    count = count + 1
                    bad[i] = true
                end
            end
        end
    end
    return count, bad
end
G.Evaluate = evaluate

---------------------------------------------------------------------------
-- Generator
---------------------------------------------------------------------------

local function placeSlots(rng, n)
    local w, h = BW - 2 * MARGIN, BH - 2 * MARGIN
    local minDist = 0.72 * math.sqrt(w * h / n)
    local min2 = minDist * minDist
    local slots, tries = {}, 0
    while #slots < n do
        tries = tries + 1
        if tries > 5000 then return nil end
        local x = MARGIN + rng.float() * w
        local y = MARGIN + rng.float() * h
        local ok = true
        for _, s in ipairs(slots) do
            local dx, dy = s.x - x, s.y - y
            if dx * dx + dy * dy < min2 then ok = false break end
        end
        if ok then slots[#slots + 1] = { x = x, y = y } end
    end
    return slots
end

local function buildEdges(rng, slots, cfg)
    local n = #slots
    local edges, deg, has = {}, {}, {}
    for i = 1, n do deg[i] = 0 end
    local function key(a, b)
        if a > b then a, b = b, a end
        return a * 100 + b
    end
    local function clear(a, b)
        local A, B = slots[a], slots[b]
        for k = 1, n do
            if k ~= a and k ~= b
                and pointSegDist(slots[k].x, slots[k].y, A.x, A.y, B.x, B.y) < CLEARANCE then
                return false
            end
        end
        for _, e in ipairs(edges) do
            if e[1] ~= a and e[1] ~= b and e[2] ~= a and e[2] ~= b then
                local C, D = slots[e[1]], slots[e[2]]
                if segmentsCross(A.x, A.y, B.x, B.y, C.x, C.y, D.x, D.y) then return false end
            end
        end
        return true
    end
    local function add(a, b)
        edges[#edges + 1] = { a, b }
        deg[a], deg[b] = deg[a] + 1, deg[b] + 1
        has[key(a, b)] = true
    end

    local cx, cy = 0, 0
    for _, s in ipairs(slots) do cx, cy = cx + s.x, cy + s.y end
    cx, cy = cx / n, cy / n
    local angle, order = {}, {}
    for i = 1, n do
        order[i] = i
        angle[i] = atan2(slots[i].y - cy, slots[i].x - cx)
    end
    table.sort(order, function(a, b) return angle[a] < angle[b] end)
    for i = 1, n do
        local a, b = order[i], order[i % n + 1]
        if not clear(a, b) then return nil end
        add(a, b)
    end

    local cands = {}
    for a = 1, n - 1 do
        for b = a + 1, n do
            if not has[key(a, b)] then
                local dx, dy = slots[a].x - slots[b].x, slots[a].y - slots[b].y
                cands[#cands + 1] = { a, b, math.sqrt(dx * dx + dy * dy) * (0.6 + 0.8 * rng.float()) }
            end
        end
    end
    table.sort(cands, function(p, q) return p[3] < q[3] end)
    for _, c in ipairs(cands) do
        if #edges >= cfg.edges then break end
        local a, b = c[1], c[2]
        if deg[a] < cfg.maxDegree and deg[b] < cfg.maxDegree and clear(a, b) then add(a, b) end
    end
    return edges
end

local function minSwaps(pos, n)
    local seen, cycles = {}, 0
    for i = 1, n do
        if not seen[i] then
            cycles = cycles + 1
            local j = i
            while not seen[j] do
                seen[j] = true
                j = pos[j]
            end
        end
    end
    return n - cycles
end

local function scramble(rng, puzzle, cfg)
    local n = puzzle.n
    local pos, swaps = {}, 0
    for i = 1, n do pos[i] = i end
    local function swap()
        local a = rng.int(1, n)
        local b = rng.int(1, n - 1)
        if b >= a then b = b + 1 end
        pos[a], pos[b] = pos[b], pos[a]
        swaps = swaps + 1
    end
    for _ = 1, cfg.swaps do swap() end
    local conflicts = evaluate(puzzle, pos)
    while conflicts < cfg.minConflicts and swaps < cfg.swaps + 3 * n do
        swap()
        conflicts = evaluate(puzzle, pos)
    end
    if conflicts < cfg.minConflicts then return nil end
    return pos, minSwaps(pos, n)
end

local cache = {}

function G.Get(level)
    if cache[level] then return cache[level] end
    local cfg = config(level)
    local rng = ns.NewRNG(level * 7919 + 104729)
    for _ = 1, 300 do
        local slots = placeSlots(rng, cfg.nodes)
        if slots then
            local puzzle = { level = level, n = cfg.nodes, slots = slots }
            puzzle.edges = buildEdges(rng, slots, cfg)
            if puzzle.edges then
                local start, par = scramble(rng, puzzle, cfg)
                if start then
                    puzzle.start, puzzle.par = start, par
                    cache[level] = puzzle
                    return puzzle
                end
            end
        end
    end
    error("AFKade: could not generate untangle level " .. level)
end


---------------------------------------------------------------------------
-- Spielbrett
---------------------------------------------------------------------------

local COLOR = {
    node = { 0.36, 0.76, 1.0 },
    selected = { 1.0, 0.82, 0.1 },
    good = { 0.35, 0.95, 0.45, 1 },
    line = { 0.82, 0.88, 1.0, 0.85 },
    bad = { 1.0, 0.27, 0.27, 0.95 },
}

local kit, board
local nodes, lines, disp = {}, {}, {}
local puzzle, pos, selected, anim, conflicts

local onClick

local function slotXY(slot)
    local s = puzzle.slots[slot]
    return { x = s.x, y = s.y }
end

local function getNode(i)
    if nodes[i] then return nodes[i] end
    local b = CreateFrame("Button", nil, board)
    b:SetSize(2 * R + 6, 2 * R + 6)
    b:SetFrameLevel(board:GetFrameLevel() + 5)
    local ring = b:CreateTexture(nil, "BACKGROUND")
    ring:SetAllPoints()
    ring:SetColorTexture(0, 0, 0, 0.9)
    U.maskCircle(b, ring)
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("CENTER")
    fill:SetSize(2 * R, 2 * R)
    U.maskCircle(b, fill)
    local shine = b:CreateTexture(nil, "OVERLAY")
    shine:SetPoint("CENTER", -3, 3)
    shine:SetSize(R, R)
    shine:SetColorTexture(1, 1, 1, 0.3)
    U.maskCircle(b, shine)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(fill)
    hl:SetColorTexture(1, 1, 1, 0.25)
    U.maskCircle(b, hl)
    b.fill = fill
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, mouse) onClick(i, mouse) end)
    nodes[i] = b
    return b
end

local function getLine(i)
    if not lines[i] then
        local ln = board:CreateLine(nil, "ARTWORK")
        ln:SetThickness(3)
        lines[i] = ln
    end
    return lines[i]
end

local function layout()
    for i = 1, puzzle.n do
        nodes[i]:ClearAllPoints()
        nodes[i]:SetPoint("CENTER", board, "BOTTOMLEFT", disp[i].x, disp[i].y)
    end
    for i, e in ipairs(puzzle.edges) do
        local a, c = disp[e[1]], disp[e[2]]
        lines[i]:SetStartPoint("BOTTOMLEFT", board, a.x, a.y)
        lines[i]:SetEndPoint("BOTTOMLEFT", board, c.x, c.y)
    end
end

local function isSolvedState()
    return kit.state and kit.state.solved
end

local function colorNodes()
    local solved = isSolvedState()
    for i = 1, puzzle.n do
        local col = (selected == i) and COLOR.selected or (solved and COLOR.good or COLOR.node)
        nodes[i].fill:SetColorTexture(col[1], col[2], col[3], 1)
    end
end

local function applyColors()
    local c, bad = evaluate(puzzle, pos)
    conflicts = c
    local solved = isSolvedState()
    for i = 1, #puzzle.edges do
        local col = solved and COLOR.good or (bad[i] and COLOR.bad or COLOR.line)
        lines[i]:SetColorTexture(col[1], col[2], col[3], col[4])
    end
    colorNodes()
    kit:SetStatus(L.CROSSINGS_FMT:format(c), c == 0)
end

local function startSwap(a, b)
    pos[a], pos[b] = pos[b], pos[a]
    anim = {
        t = 0, dur = 0.18,
        from = { [a] = { x = disp[a].x, y = disp[a].y }, [b] = { x = disp[b].x, y = disp[b].y } },
        to = { [a] = slotXY(pos[a]), [b] = slotXY(pos[b]) },
    }
    kit.state.busy = true
end

onClick = function(i, mouse)
    if not kit:CanPlay() then return end
    if mouse == "RightButton" or selected == i then
        selected = nil
    elseif not selected then
        selected = i
        U.play("IG_MAINMENU_OPTION_CHECKBOX_ON")
    else
        local a = selected
        selected = nil
        startSwap(a, i)
        kit:Moved({ a, i })
        U.play("IG_MAINMENU_OPTION_CHECKBOX_OFF")
    end
    colorNodes()
end

local function validPerm(p, n)
    if type(p) ~= "table" or #p ~= n then return false end
    local seen = {}
    for i = 1, n do
        local v = p[i]
        if type(v) ~= "number" or v < 1 or v > n or seen[v] then return false end
        seen[v] = true
    end
    return true
end

function G.Create(k, b)
    kit, board = k, b
end

function G.Load(k, level, saved)
    puzzle = G.Get(level)
    anim, selected = nil, nil
    k.state.busy = false
    local accepted = validPerm(saved, puzzle.n)
    pos = accepted and U.copy(saved) or U.copy(puzzle.start)
    for i = 1, puzzle.n do
        getNode(i):Show()
        disp[i] = slotXY(pos[i])
    end
    for i = puzzle.n + 1, #nodes do nodes[i]:Hide() end
    for i = 1, #puzzle.edges do getLine(i):Show() end
    for i = #puzzle.edges + 1, #lines do lines[i]:Hide() end
    layout()
    applyColors()
    return accepted
end

function G.Serialize() return U.copy(pos) end

function G.Undo(_, entry)
    selected = nil
    startSwap(entry[1], entry[2])
    colorNodes()
end

function G.IsSolved() return conflicts == 0 end

function G.ShowSolved()
    selected = nil
    applyColors()
end

function G.OnPause()
    selected = nil
    if puzzle then colorNodes() end
end

function G.Update(_, elapsed)
    if not anim then return end
    anim.t = anim.t + elapsed
    local f = math.min(1, anim.t / anim.dur)
    local e = 1 - (1 - f) * (1 - f)
    for node, from in pairs(anim.from) do
        local to = anim.to[node]
        disp[node].x = from.x + (to.x - from.x) * e
        disp[node].y = from.y + (to.y - from.y) * e
    end
    layout()
    if f >= 1 then
        anim = nil
        kit.state.busy = false
        applyColors()
        kit:CheckSolved()
    end
end

-- Nur für Tests
function G.Debug() return puzzle, pos end

ns.RegisterGame(G)
