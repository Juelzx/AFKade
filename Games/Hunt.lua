-- AFKade – Spiel „Jagdsaison“
--
-- Du bist Jäger: Figuren der anderen Fraktion laufen in drei Entfernungen
-- durchs Bild, Bäume verdecken Sicht und Schüsse.
--   Kampagne:  Wellen mit Ziel, Elite-Gegnern, Bossen, neuen Bewegungsarten
--              und wechselnden Gebieten. Gold kaufen Waffen und Upgrades.
--              Pro Welle dürfen 5 Gegner entkommen; scheitert man, wird nur
--              die Welle wiederholt – Gold bleibt, also kommt man immer weiter.
--   Entspannt: endlos, ohne Druck (halbes Gold)
--   90 Sekunden: Punktejagd mit Rekord
-- Steuerung nur mit Maus: Linksklick schießen, Rechtsklick nachladen,
-- Mausrad oder Waffenleiste: Waffe wechseln.

local _, ns = ...
local L, U = ns.L, ns.U

local G = {
    id = "hunt",
    name = L.GAME_HUNT,
    icon = ns.MEDIA .. "hunt",
}

local W, H = 384, 300
local CROSSHAIR = "Interface\\Cursor\\Crosshairs"
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"
local ELITE_ICON = "Interface\\Tooltips\\EliteNameplateIcon"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local FACING = math.pi / 2
local ROUND_TIME = 90
-- Jagdglück nach Fehlversuchen: je Stufe 5 % langsamere Ziele und 1 Flucht mehr
local LUCK_MAX, LUCK_SPEED = 8, 0.05

-- Sounds (Datei-Nummern aus dem Spiel). Pro Eintrag mehrere Listen: Fehlt
-- eine Datei im Client, wird die nächste Liste versucht, zuletzt ein UI-Klick.
local SOUNDS = {
    gun = { { 921248, 921250, 921252, 921254, 921256, 921258 } },           -- Jäger: Donnerbüchse
    bow = { { 922086, 922088, 922090, 922092, 922094 },                    -- Jäger: Bogen loslassen
            { 567674, 567673, 567682 } },                                  -- Classic: bowrelease
    xbow = { { 925549, 925551, 925553, 925555, 925557, 925559 } },         -- Jäger: Armbrustschuss
    gunReload = { { 567719, 567720, 567723 } },                            -- Classic: gunload
    xbowReload = { { 925307, 925309, 925311, 925313, 925315, 925317 } },   -- Jäger: Armbrust laden
}

-- Gegner (Creature-IDs). Allianz-Charaktere jagen die Horde und umgekehrt.
local ENEMIES = {
    Horde = { 3296, 3084, 3297, 7980 },   -- Orc, Tauren, Troll, Verlassener
    Alliance = { 68, 5595, 4262, 7944 },  -- Mensch, Zwerg, Nachtelfe, Gnom
}
local LEADER = { Horde = 4949, Alliance = 1748 } -- Thrall, Bolvar Fordragon
local CRITTERS = { 1933, 721 }                   -- Schaf, Hase

-- Drei Ebenen: Fußlinie, Rahmengröße, Grundtempo, Gold, Zeichenebene
local LANES = {
    { y = 146, w = 46, h = 66, speed = 34, gold = 5, points = 25, level = 2 },
    { y = 88, w = 70, h = 100, speed = 55, gold = 3, points = 10, level = 4 },
    { y = 22, w = 100, h = 142, speed = 80, gold = 2, points = 5, level = 6 },
}

local WEAPONS = {
    { id = "gun", icon = "Interface\\Icons\\INV_Weapon_Rifle_01", mag = 8, reload = 0.7, delay = 0.22,
      dmg = 1, price = 0, unlock = 1, sound = "gun", subclass = 3, ammoIcon = "Interface\\Icons\\INV_Ammo_Bullet_01" },
    { id = "bow", icon = "Interface\\Icons\\INV_Weapon_Bow_01", mag = nil, reload = 0, delay = 0.5,
      dmg = 1, speed = 950, price = 150, unlock = 3, sound = "bow", subclass = 2 },
    { id = "xbow", icon = "Interface\\Icons\\INV_Weapon_Crossbow_01", mag = 1, reload = 0.95, delay = 0.2,
      dmg = 3, pierce = true, single = true, price = 300, unlock = 6, sound = "xbow", subclass = 18,
      ammoIcon = "Interface\\Icons\\INV_Ammo_Arrow_01" },
    { id = "scatter", icon = "Interface\\Icons\\INV_Weapon_Rifle_01", tint = { 1, 0.65, 0.35 }, mag = 2,
      reload = 1.1, delay = 0.3, dmg = 1, spread = 28, price = 500, unlock = 9, sound = "gun",
      ammoIcon = "Interface\\Icons\\INV_Ammo_Bullet_01" },
}

local UPGRADES = {
    { id = "reload", icon = ns.MEDIA .. "reload", cost = { 60, 140, 260 } },
    { id = "mag", icon = ns.MEDIA .. "magazine", cost = { 60, 140, 260 } },
    { id = "scope", icon = ns.MEDIA .. "scope", cost = { 80, 180, 320 } },
    { id = "ammo", icon = ns.MEDIA .. "heavyammo", cost = { 150, 340 } },
}

---------------------------------------------------------------------------
-- Gebiete
---------------------------------------------------------------------------

local THEMES = {
    { key = "ashenvale", sky = { { 0.18, 0.16, 0.33 }, { 0.27, 0.23, 0.43 }, { 0.42, 0.33, 0.5 } },
      orb = { 0.9, 0.92, 1 }, hills = { 0.14, 0.13, 0.25 }, hillStyle = "round",
      ground = { { 0.16, 0.28, 0.24 }, { 0.14, 0.25, 0.21 }, { 0.11, 0.21, 0.17 } },
      tree = "round", crown = { { 0.16, 0.3, 0.34 }, { 0.13, 0.26, 0.3 }, { 0.1, 0.21, 0.24 } },
      trunk = { 0.2, 0.14, 0.14 }, far = { 0.12, 0.2, 0.24 }, particles = "fireflies" },
    { key = "barrens", sky = { { 0.55, 0.72, 0.88 }, { 0.68, 0.8, 0.9 }, { 0.92, 0.84, 0.66 } },
      orb = { 1, 0.92, 0.6 }, hills = { 0.66, 0.5, 0.34 }, hillStyle = "mesa", hillTop = { 0.58, 0.42, 0.28 },
      ground = { { 0.78, 0.66, 0.42 }, { 0.74, 0.61, 0.38 }, { 0.68, 0.55, 0.33 } },
      tree = "acacia", crown = { { 0.42, 0.5, 0.22 }, { 0.37, 0.45, 0.19 }, { 0.32, 0.4, 0.16 } },
      trunk = { 0.38, 0.27, 0.18 }, far = { 0.5, 0.48, 0.3 } },
    { key = "arathi", sky = { { 0.4, 0.6, 0.85 }, { 0.52, 0.7, 0.9 }, { 0.72, 0.82, 0.92 } },
      orb = { 1, 0.95, 0.7 }, hills = { 0.36, 0.48, 0.36 }, hillStyle = "round",
      ground = { { 0.42, 0.58, 0.32 }, { 0.37, 0.53, 0.28 }, { 0.31, 0.46, 0.23 } },
      tree = "round", crown = { { 0.25, 0.45, 0.2 }, { 0.21, 0.4, 0.17 }, { 0.17, 0.34, 0.13 } },
      trunk = { 0.33, 0.24, 0.16 }, far = { 0.28, 0.42, 0.26 }, ruins = { 0.55, 0.53, 0.5 } },
    { key = "alterac", sky = { { 0.5, 0.58, 0.7 }, { 0.62, 0.68, 0.78 }, { 0.78, 0.82, 0.88 } },
      orb = { 0.95, 0.96, 1 }, hills = { 0.58, 0.62, 0.7 }, hillStyle = "peaks",
      ground = { { 0.9, 0.92, 0.96 }, { 0.85, 0.88, 0.93 }, { 0.8, 0.83, 0.9 } },
      tree = "pine", crown = { { 0.16, 0.3, 0.25 }, { 0.13, 0.26, 0.21 }, { 0.1, 0.21, 0.17 } },
      trunk = { 0.28, 0.2, 0.15 }, far = { 0.3, 0.38, 0.38 }, particles = "snow", snowcaps = true },
}

-- Vordergrund-Bäume (in allen Gebieten gleich platziert -> gleiche Schwierigkeit)
-- layer 1 steht vor der fernen Ebene, 2 vor der mittleren, 3 vor der nahen
local FG_TREES = {
    { layer = 1, x = 70, y = 142, size = 46 },
    { layer = 1, x = 318, y = 142, size = 40 },
    { layer = 2, x = 200, y = 84, size = 64 },
    { layer = 3, x = 372, y = 0, size = 96 },
}
local FG_BUSH = { layer = 3, x = 28, y = 14, w = 64, h = 36 }
local LAYER_LEVEL = { 3, 5, 7 }

---------------------------------------------------------------------------
-- Zustand
---------------------------------------------------------------------------

local pane, canvas, hud, overlay, shop, weaponFrame
local Wd = {}
local themeSets, activeTheme = {}, nil
local occluders = {}
local state = "ready" -- ready | running | paused | over | shop | banner
local mode = "relaxed"
local cfg
local score, hits, shots, kills, escaped, timeLeft, runGold = 0, 0, 0, 0, 0, ROUND_TIME, 0
local spawnTimer, cooldown, reloading = 0, 0, 0
local weaponIndex = 1
local ammo = {}
local targets, modelPool, barPool = {}, {}, {}
local arrows, arrowPool = {}, {}
local popups, freePopups = {}, {}
local boss
local enemyFaction
local cursorTimer, recoil, bannerTime = 0, 0, 0
local aimX, aimY = W / 2, H / 2
local showHitboxes, hitboxTex = false, {}

local function data() return ns.GameData(G.id) end

local function camp()
    local d = data()
    return d.camp
end

function G.InitData(d)
    d.best = d.best or 0
    d.hits = d.hits or 0
    d.shots = d.shots or 0
    d.rounds = d.rounds or 0
    d.bossKills = d.bossKills or 0
    d.camp = d.camp or {}
    local c = d.camp
    c.wave = c.wave or 1
    c.bestWave = c.bestWave or 1
    c.luck = c.luck or 0
    c.gold = c.gold or 0
    c.owned = c.owned or { gun = true }
    c.up = c.up or {}
    for _, u in ipairs(UPGRADES) do c.up[u.id] = c.up[u.id] or 0 end
end

-- Spielstände zusammenführen (alte Pro-Charakter-Daten -> Account):
-- Zähler addieren, Rekorde behalten, die weiter fortgeschrittene Kampagne gewinnt
function G.MergeData(dst, src)
    dst.best = math.max(dst.best or 0, src.best or 0)
    for _, k in ipairs({ "hits", "shots", "rounds", "bossKills" }) do
        dst[k] = (dst[k] or 0) + (src[k] or 0)
    end
    local a, b = dst.camp, src.camp
    local bAhead = (b.bestWave or 1) > (a.bestWave or 1)
        or ((b.bestWave or 1) == (a.bestWave or 1) and (b.wave or 1) > (a.wave or 1))
    local gold = (a.gold or 0) + (b.gold or 0)
    if bAhead then
        a.wave, a.bestWave, a.luck = b.wave, b.bestWave, b.luck
    end
    a.gold = gold
    for id, v in pairs(b.owned or {}) do if v then a.owned[id] = true end end
    for id, lvl in pairs(b.up or {}) do a.up[id] = math.max(a.up[id] or 0, lvl) end
end

function G.StatRows(d)
    local c = d.camp or {}
    local acc = (d.shots or 0) > 0 and math.floor(d.hits / d.shots * 100 + 0.5) or 0
    return {
        { L.STAT_WAVE, c.bestWave or 1 },
        { L.STAT_BOSSES, U.fmtInt(d.bossKills or 0) },
        { L.STAT_RECORD90, L.STAT_PTS_FMT:format(U.fmtInt(d.best or 0)) },
        { L.STAT_ACCURACY, L.STAT_PCT_FMT:format(acc) },
        { L.STAT_HITS, U.fmtInt(d.hits or 0) },
    }
end

function G.SidebarText(d)
    return L.HUNT_SIDEBAR_FMT:format(d.camp and d.camp.wave or 1, U.fmtInt(d.camp and d.camp.gold or 0))
end

local function myEnemies()
    local fac = UnitFactionGroup("player")
    if fac == "Alliance" then return "Horde" end
    if fac == "Horde" then return "Alliance" end
    return (math.random() < 0.5) and "Horde" or "Alliance"
end

---------------------------------------------------------------------------
-- Wellen
---------------------------------------------------------------------------

local function patternsFor(wave)
    local p = { "linear", "linear" }
    if wave >= 3 then p[#p + 1] = "stopgo" end
    if wave >= 5 then p[#p + 1] = "hop" end
    if wave >= 7 then p[#p + 1] = "turn" end
    if wave >= 9 then p[#p + 1] = "dash" end
    return p
end

local function waveConfig(wave)
    local isBoss = wave % 5 == 0
    return {
        wave = wave,
        boss = isBoss,
        goal = isBoss and 0 or math.min(30, 8 + 2 * wave),
        lives = 5,
        speed = math.min(1.8, 1 + 0.05 * (wave - 1)),
        maxAlive = math.min(7, 3 + math.floor(wave / 3)) - (isBoss and 1 or 0),
        interval = math.max(0.55, 1.4 - 0.05 * wave),
        elite = (wave >= 4) and math.min(0.25, 0.04 * (wave - 3)) or 0,
        eliteHP = math.min(5, 3 + math.floor(math.max(0, wave - 4) / 6)),
        critter = (wave >= 2) and 0.06 or 0,
        patterns = patternsFor(wave),
        bossHP = isBoss and math.min(90, 20 + 15 * (math.floor(wave / 5) - 1)) or 0,
        theme = (math.floor((wave - 1) / 5) % #THEMES) + 1,
        goldFactor = 1,
    }
end

local function relaxedConfig()
    return { wave = 0, goal = 0, speed = 1.05, maxAlive = 4, interval = 1.2, elite = 0.05, eliteHP = 3,
             critter = 0.05, patterns = { "linear", "linear", "stopgo" }, theme = math.random(1, #THEMES),
             goldFactor = 0.5 }
end

local function timedConfig()
    return { wave = 0, goal = 0, speed = 1.2, maxAlive = 5, interval = 0.9, elite = 0.08, eliteHP = 3,
             critter = 0.05, patterns = { "linear", "linear", "stopgo", "hop" }, theme = math.random(1, #THEMES),
             goldFactor = 0.5 }
end

-- Hinweis, was in dieser Welle neu ist
local function waveNews(wave)
    if wave == 2 then return L.HUNT_NEWS_CRITTER end
    if wave == 3 then return L.HUNT_NEWS_STOPGO end
    if wave == 4 then return L.HUNT_NEWS_ELITE end
    if wave % 5 == 0 then return L.HUNT_NEWS_BOSS end
    if wave == 6 or wave == 11 or wave == 16 then return L.HUNT_NEWS_ZONE end
    if wave == 7 then return L.HUNT_NEWS_TURN end
    if wave == 9 then return L.HUNT_NEWS_DASH end
    return nil
end

---------------------------------------------------------------------------
-- Waffen
---------------------------------------------------------------------------

local function upLevel(id) return camp().up[id] or 0 end

local function weapon() return WEAPONS[weaponIndex] end

local function magSize(w)
    if not w.mag then return nil end
    if w.single then return w.mag end
    local lvl = upLevel("mag")
    return w.mag + math.max(lvl, math.floor(w.mag * 0.25 * lvl + 0.5))
end

local function reloadTime(w) return w.reload * (1 - 0.2 * upLevel("reload")) end
local function damage(w) return w.dmg + upLevel("ammo") end
local function scopeScale() return 1 + 0.12 * upLevel("scope") end

-- Echte angelegte Fernkampfwaffe: gleicher Typ -> deren Name und Symbol
local function realWeapon(w)
    local link = GetInventoryItemLink("player", 18)
    if not link or not w.subclass then return nil end
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local ok, _, _, _, _, icon, _, subClassID = pcall(info, link)
    if ok and subClassID == w.subclass then return link:match("%[(.-)%]"), icon end
end

local function weaponName(w)
    local real = realWeapon(w)
    return real or L["HUNT_W_" .. w.id:upper()]
end

local function weaponIcon(w)
    local _, icon = realWeapon(w)
    return icon or w.icon
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function weaponTooltip(owner, i)
    if not GameTooltip then return end
    local w = WEAPONS[i]
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(weaponName(w), 1, 0.82, 0)
    GameTooltip:AddLine(L["HUNT_D_" .. w.id:upper()], 1, 1, 1, true)
    local size = magSize(w)
    GameTooltip:AddLine(L.HUNT_WSTATS_FMT:format(size and tostring(size) or L.HUNT_UNLIMITED, damage(w)), 0.8, 0.8, 0.8)
    if not camp().owned[w.id] then GameTooltip:AddLine(L.HUNT_BUY_HINT, 0.6, 0.6, 0.6, true) end
    GameTooltip:Show()
end

-- Zufällige Datei aus der ersten Liste, die der Client abspielen kann
local function playSound(key, fallbackKit)
    for _, list in ipairs(SOUNDS[key] or {}) do
        local ok, willPlay = pcall(PlaySoundFile, list[math.random(1, #list)], "SFX")
        if ok and willPlay then return end
    end
    if fallbackKit then U.play(fallbackKit) end
end

local function playShot(w)
    playSound(w.sound, "IG_MAINMENU_OPTION_CHECKBOX_OFF")
end

---------------------------------------------------------------------------
-- Mauszeiger
---------------------------------------------------------------------------

local function setCrosshair(on)
    if on then pcall(SetCursor, CROSSHAIR) else pcall(ResetCursor) end
end

local function cursorPos()
    local scale = canvas:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    return cx / scale - canvas:GetLeft(), cy / scale - canvas:GetBottom()
end

---------------------------------------------------------------------------
-- Popups
---------------------------------------------------------------------------

local function popup(x, y, text, r, g, b)
    local fs = table.remove(freePopups) or U.text(hud, "GameFontNormalLarge")
    fs:SetTextColor(r, g, b)
    fs:SetText(text)
    fs:SetAlpha(1)
    fs:Show()
    popups[#popups + 1] = { fs = fs, x = x, y = y, t = 0 }
end

local function updatePopups(dt)
    for i = #popups, 1, -1 do
        local p = popups[i]
        p.t = p.t + dt
        p.fs:ClearAllPoints()
        p.fs:SetPoint("CENTER", canvas, "BOTTOMLEFT", p.x, p.y + p.t * 40)
        p.fs:SetAlpha(math.max(0, 1 - p.t / 0.9))
        if p.t >= 0.9 then
            p.fs:Hide()
            freePopups[#freePopups + 1] = p.fs
            table.remove(popups, i)
        end
    end
end

---------------------------------------------------------------------------
-- Kulisse
---------------------------------------------------------------------------

local function box(parent, layer, x, y, w, h, c, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", x, y)
    t:SetSize(w, h)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

local function blob(parent, layer, cx, cy, w, h, c, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetPoint("CENTER", canvas, "BOTTOMLEFT", cx, cy)
    t:SetSize(w, h)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    U.maskCircle(parent, t)
    return t
end

-- Zeichnet einen Baum und liefert die Rechtecke, die Schüsse abfangen
local function drawTree(parent, style, x, y, s, crown, trunk, snow)
    local occ = {}
    local function add(x0, y0, w, h) occ[#occ + 1] = { x = x0, y = y0, w = w, h = h } end
    if style == "pine" then
        local tw = s * 0.12
        box(parent, "ARTWORK", x - tw / 2, y, tw, s * 0.35, trunk)
        add(x - tw / 2, y, tw, s * 0.35)
        local widths = { 1.0, 0.78, 0.56, 0.32 }
        for i, f in ipairs(widths) do
            local w, h = s * f, s * 0.3
            local y0 = y + s * 0.25 + (i - 1) * s * 0.26
            box(parent, "ARTWORK", x - w / 2, y0, w, h, crown)
            if snow then box(parent, "ARTWORK", x - w / 2, y0 + h - 3, w, 3, { 0.95, 0.97, 1 }) end
            add(x - w / 2, y0, w, h)
        end
    elseif style == "acacia" then
        local tw = s * 0.1
        box(parent, "ARTWORK", x - tw / 2, y, tw, s * 1.1, trunk)
        add(x - tw / 2, y, tw, s * 1.1)
        blob(parent, "ARTWORK", x, y + s * 1.12, s * 1.8, s * 0.42, crown)
        blob(parent, "ARTWORK", x + s * 0.25, y + s * 1.25, s * 1.0, s * 0.3, crown)
        add(x - s * 0.8, y + s * 0.95, s * 1.6, s * 0.4)
    else -- round
        local tw = s * 0.18
        box(parent, "ARTWORK", x - tw / 2, y, tw, s * 0.9, trunk)
        add(x - tw / 2, y, tw, s * 0.7)
        blob(parent, "ARTWORK", x - s * 0.28, y + s * 0.78, s * 0.72, s * 0.62, crown)
        blob(parent, "ARTWORK", x + s * 0.3, y + s * 0.8, s * 0.7, s * 0.6, crown)
        blob(parent, "ARTWORK", x, y + s * 1.0, s * 0.95, s * 0.8, crown)
        add(x - s * 0.5, y + s * 0.6, s * 1.0, s * 0.75)
    end
    return occ
end

local function buildTheme(th)
    local base = canvas:GetFrameLevel()
    local set = { frames = {}, particles = {}, occ = {} }
    local back = CreateFrame("Frame", nil, canvas)
    back:SetAllPoints()
    back:SetFrameLevel(base + 1)
    set.frames[#set.frames + 1] = back

    -- Himmel in drei Bändern, Mond/Sonne, Berge
    box(back, "BACKGROUND", 0, 170, W, H - 170, th.sky[3])
    box(back, "BACKGROUND", 0, 215, W, H - 215, th.sky[2])
    box(back, "BACKGROUND", 0, 262, W, H - 262, th.sky[1])
    blob(back, "BORDER", 120, 248, 30, 30, th.orb)
    -- Hügel, Tafelberge oder Gipfel am Horizont
    for _, m in ipairs({ { 0, 80, 36 }, { 55, 120, 54 }, { 150, 95, 40 }, { 225, 130, 60 }, { 330, 90, 38 } }) do
        local x, w, h = m[1], m[2], m[3]
        if th.hillStyle == "mesa" then
            box(back, "BORDER", x, 160, w, h, th.hills)
            box(back, "BORDER", x, 160 + h - 4, w, 4, th.hillTop or th.hills)
        elseif th.hillStyle == "peaks" then
            local steps = 5
            for k = 0, steps - 1 do
                local f = 1 - k / steps
                local c = (k == steps - 1) and { 0.95, 0.97, 1 } or th.hills
                box(back, "BORDER", x + w * (1 - f) / 2, 160 + h * k / steps, w * f, h / steps + 1, c)
            end
        else
            blob(back, "BORDER", x + w / 2, 160, w * 1.25, h * 2, th.hills)
        end
    end
    -- Ferne Baumreihe (Silhouetten, fangen nichts ab)
    for i = 0, 11 do
        local x = 8 + i * 33 + (i % 3) * 5
        local s = 18 + (i * 7) % 10
        if th.tree == "pine" then
            box(back, "BORDER", x - s * 0.3, 166, s * 0.6, s * 0.5, th.far)
            box(back, "BORDER", x - s * 0.18, 166 + s * 0.45, s * 0.36, s * 0.45, th.far)
        elseif th.tree == "acacia" then
            box(back, "BORDER", x - 1, 166, 2, s * 0.7, th.far)
            blob(back, "BORDER", x, 166 + s * 0.75, s * 1.4, s * 0.35, th.far)
        else
            blob(back, "BORDER", x, 166 + s * 0.5, s, s, th.far)
        end
    end
    -- Boden der drei Ebenen
    box(back, "ARTWORK", 0, 140, W, 30, th.ground[1])
    box(back, "ARTWORK", 0, 80, W, 60, th.ground[2])
    box(back, "ARTWORK", 0, 0, W, 80, th.ground[3])
    if th.ruins then
        for _, r in ipairs({ { 30, 160, 10, 26 }, { 46, 160, 10, 18 }, { 260, 160, 12, 30 }, { 278, 160, 26, 8 } }) do
            box(back, "ARTWORK", r[1], r[2], r[3], r[4], th.ruins)
        end
    end

    -- Vordergrund-Ebenen mit Bäumen und Busch
    local fg = {}
    for i, lv in ipairs(LAYER_LEVEL) do
        local f = CreateFrame("Frame", nil, canvas)
        f:SetAllPoints()
        f:SetFrameLevel(base + lv)
        fg[i] = f
        set.frames[#set.frames + 1] = f
    end
    for _, tr in ipairs(FG_TREES) do
        local occ = drawTree(fg[tr.layer], th.tree, tr.x, tr.y, tr.size, th.crown[tr.layer], th.trunk, th.snowcaps)
        for _, o in ipairs(occ) do
            o.level = LAYER_LEVEL[tr.layer]
            set.occ[#set.occ + 1] = o
        end
    end
    local b = FG_BUSH
    blob(fg[b.layer], "ARTWORK", b.x, b.y + b.h / 2, b.w, b.h, th.crown[3])
    set.occ[#set.occ + 1] = { x = b.x - b.w * 0.42, y = b.y, w = b.w * 0.84, h = b.h * 0.8, level = LAYER_LEVEL[b.layer] }

    -- Partikel: Glühwürmchen oder Schnee
    if th.particles then
        local pf = CreateFrame("Frame", nil, canvas)
        pf:SetAllPoints()
        pf:SetFrameLevel(base + 8)
        set.frames[#set.frames + 1] = pf
        local n = (th.particles == "snow") and 34 or 14
        for i = 1, n do
            local size = (th.particles == "snow") and 2 + i % 2 or 3
            local c = (th.particles == "snow") and { 1, 1, 1 } or { 0.8, 1, 0.5 }
            local t = pf:CreateTexture(nil, "OVERLAY")
            t:SetSize(size, size)
            t:SetColorTexture(c[1], c[2], c[3], 0.85)
            set.particles[i] = { tex = t, x = (i * 53) % W, y = (i * 37) % H, phase = i * 0.7, kind = th.particles }
        end
    end
    return set
end

local function updateParticles(dt)
    if not activeTheme then return end
    for _, p in ipairs(activeTheme.particles) do
        p.phase = p.phase + dt
        if p.kind == "snow" then
            p.y = p.y - 22 * dt
            p.x = p.x + math.sin(p.phase * 1.3) * 8 * dt
            if p.y < 0 then p.y = H end
        else
            p.x = p.x + math.sin(p.phase * 0.8) * 10 * dt
            p.y = p.y + math.cos(p.phase * 0.6) * 6 * dt
            p.tex:SetAlpha(0.35 + 0.6 * math.abs(math.sin(p.phase * 1.7)))
        end
        p.tex:ClearAllPoints()
        p.tex:SetPoint("CENTER", canvas, "BOTTOMLEFT", p.x % W, p.y)
    end
end

local function setTheme(index)
    themeSets[index] = themeSets[index] or buildTheme(THEMES[index])
    for i, set in pairs(themeSets) do
        for _, f in ipairs(set.frames) do f:SetShown(i == index) end
    end
    activeTheme = themeSets[index]
    occluders = activeTheme.occ
end

---------------------------------------------------------------------------
-- Ziele
---------------------------------------------------------------------------

local function getBar()
    local b = table.remove(barPool)
    if b then return b end
    b = CreateFrame("StatusBar", nil, canvas)
    b:SetStatusBarTexture(BAR)
    b:SetStatusBarColor(0.85, 0.15, 0.15)
    U.addBackdrop(b, { 0, 0, 0, 1 }, { 0.1, 0.1, 0.1, 0.9 })
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(14, 14)
    b.icon:SetPoint("RIGHT", b, "LEFT", -1, 0)
    b.icon:SetTexture(ELITE_ICON)
    return b
end

local function releaseTarget(i)
    local t = targets[i]
    t.model:Hide()
    modelPool[#modelPool + 1] = t.model
    if t.bar then
        t.bar:Hide()
        barPool[#barPool + 1] = t.bar
    end
    if t == boss then boss = nil end
    table.remove(targets, i)
end

local function clearTargets()
    for i = #targets, 1, -1 do releaseTarget(i) end
    for _, a in ipairs(arrows) do
        a.line:Hide()
        arrowPool[#arrowPool + 1] = a.line
    end
    arrows = {}
end

local function pickLane()
    local r = math.random(1, 100)
    if r <= 25 then return LANES[1] elseif r <= 60 then return LANES[2] end
    return LANES[3]
end

local function newTarget(creature, lane, opts)
    local m = table.remove(modelPool) or CreateFrame("PlayerModel", nil, canvas)
    local dir = opts.dir or ((math.random() < 0.5) and 1 or -1)
    local scale = opts.scale or 1
    local w, h = lane.w * scale, lane.h * scale
    m:SetFrameLevel(canvas:GetFrameLevel() + lane.level)
    m:SetSize(w, h)
    m:SetAlpha(1)
    m:Show()
    pcall(m.SetCreature, m, creature)
    pcall(m.SetFacing, m, dir * FACING)
    pcall(m.SetAnimation, m, 4)
    local t = {
        model = m, lane = lane, dir = dir, creature = creature, w = w, h = h,
        x = opts.x or ((dir == 1) and -w or W), yOff = 0,
        speed = lane.speed * cfg.speed * (opts.speedMul or 1) * (0.85 + math.random() * 0.3),
        hp = opts.hp or 1, maxHP = opts.hp or 1,
        gold = opts.gold or lane.gold, points = opts.points or lane.points,
        elite = opts.elite, boss = opts.boss, critter = opts.critter,
        pattern = opts.pattern or "linear", age = 0, moving = true, timer = 1 + math.random(),
        turnX = W * (0.3 + math.random() * 0.4), alive = true, dying = 0,
    }
    if t.elite or t.boss then
        t.bar = getBar()
        t.bar:SetFrameLevel(canvas:GetFrameLevel() + lane.level)
        t.bar:SetSize(math.max(30, w * 0.6), 5)
        t.bar:SetMinMaxValues(0, t.maxHP)
        t.bar:SetValue(t.hp)
        t.bar:Show()
    end
    targets[#targets + 1] = t
    return t
end

local function spawn()
    if cfg.critter > 0 and math.random() < cfg.critter then
        local lane = LANES[math.random(2, 3)]
        newTarget(CRITTERS[math.random(1, #CRITTERS)], lane,
            { critter = true, scale = 0.45, gold = 0, points = 0, pattern = "hop" })
        return
    end
    local lane = pickLane()
    local list = ENEMIES[enemyFaction]
    local creature = list[math.random(1, #list)]
    local pattern = cfg.patterns[math.random(1, #cfg.patterns)]
    if math.random() < cfg.elite then
        newTarget(creature, lane, { elite = true, scale = 1.15, hp = cfg.eliteHP, gold = lane.gold * 3,
            points = lane.points * 3, pattern = pattern })
    else
        newTarget(creature, lane, { pattern = pattern })
    end
end

local function spawnBoss()
    boss = newTarget(LEADER[enemyFaction], LANES[2], { boss = true, scale = 1.25, hp = cfg.bossHP,
        gold = 60 + 20 * math.floor(cfg.wave / 5), points = 100, pattern = "dash", x = W * 0.4, dir = 1 })
end

local function hitbox(t)
    local s = scopeScale()
    local w, h = t.w * 0.5 * s, t.h * 0.88 * math.min(s, 1.1)
    local cx = t.x + t.w / 2
    return cx - w / 2, t.lane.y + t.yOff + t.h * 0.04, w, h
end

local function placeTarget(t)
    t.model:ClearAllPoints()
    t.model:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", t.x, t.lane.y + t.yOff)
    if t.bar then
        t.bar:ClearAllPoints()
        t.bar:SetPoint("BOTTOM", canvas, "BOTTOMLEFT", t.x + t.w / 2, t.lane.y + t.yOff + t.h * 0.92)
        t.bar:SetValue(t.hp)
    end
end

local function moveTarget(t, dt)
    t.age = t.age + dt
    local speed = t.speed
    if t.pattern == "stopgo" then
        t.timer = t.timer - dt
        if t.timer <= 0 then
            t.moving = not t.moving
            t.timer = t.moving and (1 + math.random() * 0.6) or (0.6 + math.random() * 0.4)
            pcall(t.model.SetAnimation, t.model, t.moving and 4 or 0)
        end
        if not t.moving then speed = 0 end
    elseif t.pattern == "hop" then
        t.yOff = math.abs(math.sin(t.age * 5)) * 16 * (t.h / 100)
    elseif t.pattern == "turn" then
        if not t.turned and ((t.dir == 1 and t.x > t.turnX) or (t.dir == -1 and t.x < t.turnX)) then
            t.turned = true
            t.dir = -t.dir
            pcall(t.model.SetFacing, t.model, t.dir * FACING)
        end
    elseif t.pattern == "dash" then
        speed = speed * (1 + 1.2 * math.max(0, math.sin(t.age * 2.2)))
    end
    -- angeschlagener Anführer wird schneller
    if t.boss and t.hp <= t.maxHP / 2 then speed = speed * 1.5 end
    t.x = t.x + t.dir * speed * dt
    -- Boss läuft hin und her statt zu entkommen
    if t.boss then
        if t.x < 10 then t.x, t.dir = 10, 1 pcall(t.model.SetFacing, t.model, FACING) end
        if t.x > W - t.w - 10 then t.x, t.dir = W - t.w - 10, -1 pcall(t.model.SetFacing, t.model, -FACING) end
    end
end

---------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------

local function drawAmmo()
    local w = weapon()
    local size = magSize(w)
    local left = ammo[w.id] or 0
    for i, b in ipairs(Wd.bullets) do
        if size and i <= size then
            b:SetTexture(w.ammoIcon)
            b:SetDesaturated(i > left)
            b:SetAlpha(i > left and 0.3 or 1)
            b:Show()
        else
            b:Hide()
        end
    end
    Wd.infinite:SetShown(size == nil)
    Wd.reloadHint:SetShown(state == "running" and size and left == 0 and reloading <= 0)
end

local function drawSlots()
    local c = camp()
    for i, w in ipairs(WEAPONS) do
        local s = Wd.slots[i]
        s.icon:SetTexture(weaponIcon(w))
        if w.tint then s.icon:SetVertexColor(w.tint[1], w.tint[2], w.tint[3]) end
        local owned = c.owned[w.id]
        s.icon:SetDesaturated(not owned)
        s.icon:SetAlpha(owned and 1 or 0.35)
        s.sel:SetShown(i == weaponIndex)
    end
end

local function drawHud()
    local d = data()
    if mode == "campaign" then
        if cfg.boss and boss then
            Wd.top:SetText(L.HUNT_WAVE_FMT:format(cfg.wave) .. "  ·  " .. L.HUNT_BOSS_FMT:format(boss.hp, boss.maxHP))
        else
            Wd.top:SetText(L.HUNT_WAVE_FMT:format(cfg.wave) .. "  ·  " .. L.HUNT_GOAL_FMT:format(kills, cfg.goal))
        end
        Wd.top2:SetText(cfg.boss and L.HUNT_BOSS_ESCORT or L.HUNT_ESCAPED_FMT:format(escaped, cfg.lives))
        if escaped >= cfg.lives - 1 then Wd.top2:SetTextColor(1, 0.45, 0.45) else Wd.top2:SetTextColor(0.9, 0.9, 0.9) end
        Wd.right:SetText(U.fmtInt(camp().gold) .. " " .. GOLD)
    elseif mode == "timed" then
        local s = math.max(0, math.ceil(timeLeft))
        Wd.top:SetText(("%d:%02d"):format(math.floor(s / 60), s % 60))
        Wd.top2:SetText("")
        Wd.right:SetText(L.HUNT_SCORE_FMT:format(U.fmtInt(score)))
    else
        Wd.top:SetText(L.HUNT_SCORE_FMT:format(U.fmtInt(score)))
        Wd.top2:SetText("")
        Wd.right:SetText(U.fmtInt(camp().gold) .. " " .. GOLD)
    end
    drawAmmo()
end

local function drawStats()
    local d, c = data(), camp()
    local acc = d.shots > 0 and math.floor(d.hits / d.shots * 100 + 0.5) or 0
    Wd.stats:SetText(L.HUNT_STATS_FMT:format(c.bestWave, U.fmtInt(d.hits), acc, U.fmtInt(d.best)))
    Wd.endButton:SetShown(state == "running")
    Wd.endButton:SetText(mode == "campaign" and L.HUNT_PAUSE or L.HUNT_END)
end

---------------------------------------------------------------------------
-- Waffenansicht (2D, aus Linien gezeichnet)
---------------------------------------------------------------------------

local PIVOT_X, PIVOT_Y = W / 2, -4
local weaponLines = {}

local function wline(i, thick, c)
    local ln = weaponLines[i]
    if not ln then
        ln = weaponFrame:CreateLine(nil, "ARTWORK")
        weaponLines[i] = ln
    end
    ln:SetThickness(thick)
    ln:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    ln:Show()
    return ln
end

local function seg(i, thick, c, x1, y1, x2, y2)
    local ln = wline(i, thick, c)
    ln:SetStartPoint("BOTTOMLEFT", canvas, x1, y1)
    ln:SetEndPoint("BOTTOMLEFT", canvas, x2, y2)
end

local WOOD, STEEL, DARK, STRING = { 0.42, 0.27, 0.15 }, { 0.38, 0.4, 0.44 }, { 0.16, 0.16, 0.18 }, { 0.9, 0.88, 0.8 }

local function drawWeapon()
    local w = weapon()
    local dx, dy = aimX - PIVOT_X, aimY - PIVOT_Y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then dx, dy, len = 0, 1, 1 end
    dx, dy = dx / len, dy / len
    if dy < 0.35 then dy = 0.35 end -- nicht nach unten zielen
    local n = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx / n, dy / n
    local px, py = -dy, dx -- senkrecht
    local bx, by = PIVOT_X - dx * recoil, PIVOT_Y - dy * recoil
    local used = 0
    local function S(thick, c, x1, y1, x2, y2)
        used = used + 1
        seg(used, thick, c, x1, y1, x2, y2)
    end
    local tipX, tipY
    if w.id == "gun" or w.id == "scatter" then
        S(14, WOOD, bx - dx * 10, by - dy * 10, bx + dx * 26, by + dy * 26)
        local barrel = (w.id == "scatter") and 9 or 6
        S(barrel, STEEL, bx + dx * 20, by + dy * 20, bx + dx * 72, by + dy * 72)
        S(3, DARK, bx + dx * 30, by + dy * 30, bx + dx * 34, by + dy * 34)
        if w.id == "scatter" then
            S(15, STEEL, bx + dx * 66, by + dy * 66, bx + dx * 76, by + dy * 76)
        end
        tipX, tipY = bx + dx * 76, by + dy * 76
    elseif w.id == "bow" then
        local gx, gy = bx + dx * 30, by + dy * 30
        local e1x, e1y = gx + px * 40 - dx * 12, gy + py * 40 - dy * 12
        local e2x, e2y = gx - px * 40 - dx * 12, gy - py * 40 - dy * 12
        S(5, WOOD, gx, gy, e1x, e1y)
        S(5, WOOD, gx, gy, e2x, e2y)
        local drawn = (cooldown > 0) and 0 or 1
        local nx, ny = gx - dx * (10 + 16 * drawn), gy - dy * (10 + 16 * drawn)
        S(1.5, STRING, e1x, e1y, nx, ny)
        S(1.5, STRING, e2x, e2y, nx, ny)
        if drawn == 1 then S(2.5, DARK, nx, ny, nx + dx * 58, ny + dy * 58) end
        tipX, tipY = gx + dx * 20, gy + dy * 20
    else -- Armbrust
        S(10, WOOD, bx - dx * 8, by - dy * 8, bx + dx * 58, by + dy * 58)
        local tx, ty = bx + dx * 52, by + dy * 52
        S(5, STEEL, tx, ty, tx + px * 32 - dx * 8, ty + py * 32 - dy * 8)
        S(5, STEEL, tx, ty, tx - px * 32 - dx * 8, ty - py * 32 - dy * 8)
        local loaded = (ammo.xbow or 0) > 0 and reloading <= 0
        local sx, sy = tx - dx * (loaded and 22 or 8), ty - dy * (loaded and 22 or 8)
        S(1.5, STRING, tx + px * 32 - dx * 8, ty + py * 32 - dy * 8, sx, sy)
        S(1.5, STRING, tx - px * 32 - dx * 8, ty - py * 32 - dy * 8, sx, sy)
        if loaded then S(3, DARK, sx, sy, sx + dx * 34, sy + dy * 34) end
        tipX, tipY = tx + dx * 10, ty + dy * 10
    end
    for i = used + 1, #weaponLines do weaponLines[i]:Hide() end
    return tipX, tipY
end

---------------------------------------------------------------------------
-- Overlays
---------------------------------------------------------------------------

local function showOverlay(title, line1, line2, buttons)
    Wd.ovTitle:SetText(title)
    Wd.ovLine1:SetText(line1 or "")
    Wd.ovLine2:SetText(line2 or "")
    local n = #buttons
    local bw = (n >= 3) and 92 or 120
    for i, b in ipairs(Wd.ovButtons) do
        local spec = buttons[i]
        if spec then
            b:SetText(spec[1])
            b.action = spec[2]
            b:SetWidth(bw)
            b:ClearAllPoints()
            b:SetPoint("BOTTOM", overlay, "BOTTOM", (i - (n + 1) / 2) * (bw + 6), 12)
            b:Show()
        else
            b:Hide()
        end
    end
    shop:Hide()
    overlay:Show()
end

local startMode, selectWeapon -- vorwärts

local function factionLine()
    local name = (enemyFaction == "Horde") and L.HUNT_FACTION_HORDE or L.HUNT_FACTION_ALLIANCE
    local emblem = (enemyFaction == "Horde") and "Interface\\TargetingFrame\\UI-PVP-Horde"
        or "Interface\\TargetingFrame\\UI-PVP-Alliance"
    return ("|T%s:22:22:0:0:64:64:0:40:0:40|t "):format(emblem) .. L.HUNT_TARGETS_FMT:format(name)
end

local function menuButtons()
    return {
        { L.HUNT_CAMPAIGN, function() startMode("campaign") end },
        { L.HUNT_RELAXED, function() startMode("relaxed") end },
        { L.HUNT_TIMED, function() startMode("timed") end },
    }
end

local function showMenu()
    state = "ready"
    setCrosshair(false)
    clearTargets()
    local c = camp()
    setTheme(waveConfig(c.wave).theme)
    showOverlay(L.GAME_HUNT, factionLine(),
        L.HUNT_MENU_FMT:format(c.wave, U.fmtInt(c.gold) .. " " .. GOLD), menuButtons())
    drawStats()
end

---------------------------------------------------------------------------
-- Shop
---------------------------------------------------------------------------

local function refreshShop()
    local c = camp()
    Wd.shopGold:SetText(U.fmtInt(c.gold) .. " " .. GOLD)
    for i, w in ipairs(WEAPONS) do
        local row = Wd.shopWeapons[i]
        row.icon:SetTexture(weaponIcon(w))
        if w.tint then row.icon:SetVertexColor(w.tint[1], w.tint[2], w.tint[3]) end
        row.name:SetText(weaponName(w))
        local b = row.button
        if c.owned[w.id] then
            b:SetText(L.HUNT_OWNED)
            b:SetEnabled(false)
        elseif c.wave < w.unlock then
            b:SetText(L.HUNT_FROM_WAVE_FMT:format(w.unlock))
            b:SetEnabled(false)
        else
            b:SetText(U.fmtInt(w.price) .. " g")
            b:SetEnabled(c.gold >= w.price)
        end
    end
    for i, u in ipairs(UPGRADES) do
        local row = Wd.shopUps[i]
        local lvl = c.up[u.id]
        row.name:SetText(L["HUNT_U_" .. u.id:upper()] .. "  " .. ("|cffffd100%s|r"):format(("+"):rep(lvl)) ..
            ("|cff555555%s|r"):format(("+"):rep(#u.cost - lvl)))
        local b = row.button
        if lvl >= #u.cost then
            b:SetText(L.HUNT_MAX)
            b:SetEnabled(false)
        else
            b:SetText(U.fmtInt(u.cost[lvl + 1]) .. " g")
            b:SetEnabled(c.gold >= u.cost[lvl + 1])
        end
    end
end

local function buyWeapon(i)
    local c, w = camp(), WEAPONS[i]
    if c.owned[w.id] or c.wave < w.unlock or c.gold < w.price then return end
    c.gold = c.gold - w.price
    c.owned[w.id] = true
    U.play("IG_BACKPACK_OPEN")
    refreshShop()
    drawSlots()
end

local function buyUpgrade(i)
    local c, u = camp(), UPGRADES[i]
    local lvl = c.up[u.id]
    if lvl >= #u.cost or c.gold < u.cost[lvl + 1] then return end
    c.gold = c.gold - u.cost[lvl + 1]
    c.up[u.id] = lvl + 1
    U.play("IG_BACKPACK_OPEN")
    refreshShop()
end

local function showShop(title, sub)
    state = "shop"
    setCrosshair(false)
    overlay:Hide()
    Wd.shopTitle:SetText(title)
    Wd.shopSub:SetText(sub or "")
    Wd.shopNext:SetText(L.HUNT_NEXT_WAVE_FMT:format(camp().wave))
    refreshShop()
    shop:Show()
    drawStats()
    ns.UI.RefreshSidebar()
end

---------------------------------------------------------------------------
-- Ablauf
---------------------------------------------------------------------------

local function refill()
    for _, w in ipairs(WEAPONS) do ammo[w.id] = magSize(w) or 0 end
    reloading, cooldown = 0, 0
end

local function run()
    overlay:Hide()
    shop:Hide()
    state = "running"
    drawStats()
    if canvas:IsMouseOver() then setCrosshair(true) end
end

local function banner(title, sub)
    Wd.bannerTitle:SetText(title)
    Wd.bannerSub:SetText(sub or "")
    Wd.banner:Show()
    bannerTime = 2.2
end

local function startWave()
    local c = camp()
    cfg = waveConfig(c.wave)
    -- Jagdglück: jeder Fehlversuch macht den nächsten Versuch etwas leichter
    local luck = math.min(LUCK_MAX, c.luck or 0)
    cfg.luck = luck
    if luck > 0 then
        cfg.speed = cfg.speed * (1 - LUCK_SPEED * luck)
        cfg.lives = cfg.lives + luck
    end
    enemyFaction = myEnemies()
    setTheme(cfg.theme)
    clearTargets()
    kills, escaped, runGold = 0, 0, 0
    refill()
    spawnTimer = 1.2
    if cfg.boss then spawnBoss() end
    drawHud()
    drawSlots()
    local sub = waveNews(c.wave)
    if luck > 0 then
        local line = L.HUNT_LUCK_FMT:format(math.floor(luck * LUCK_SPEED * 100 + 0.5), luck)
        sub = sub and (sub .. "\n" .. line) or line
    end
    banner(L.HUNT_WAVE_FMT:format(c.wave) .. " – " .. L["HUNT_ZONE_" .. THEMES[cfg.theme].key:upper()], sub)
    run()
end

-- Trägt der Charakter gerade einen Bogen oder eine Armbrust (und ist die im
-- Spiel freigeschaltet), geht's direkt mit der los.
local function preferRealWeapon()
    local c = camp()
    if not c.owned[weapon().id] then weaponIndex = 1 end
    for i, w in ipairs(WEAPONS) do
        if c.owned[w.id] and realWeapon(w) then
            weaponIndex = i
            return
        end
    end
end

startMode = function(m)
    mode = m
    enemyFaction = myEnemies()
    preferRealWeapon()
    if m == "campaign" then
        startWave()
        return
    end
    cfg = (m == "timed") and timedConfig() or relaxedConfig()
    setTheme(cfg.theme)
    clearTargets()
    score, hits, shots, runGold = 0, 0, 0, 0
    timeLeft = ROUND_TIME
    refill()
    spawnTimer = 0.4
    drawHud()
    drawSlots()
    run()
end

local function pause()
    if state ~= "running" then return end
    state = "paused"
    setCrosshair(false)
    drawStats()
    showOverlay(L.HUNT_PAUSED, nil, nil, { { L.CONTINUE, run }, { L.HUNT_MENU, showMenu } })
end

local function waveCleared()
    local c = camp()
    clearTargets()
    c.wave = c.wave + 1
    c.bestWave = math.max(c.bestWave, c.wave)
    c.luck = 0
    U.play("IG_QUEST_LIST_COMPLETE")
    showShop(L.HUNT_WAVE_DONE_FMT:format(c.wave - 1), L.HUNT_EARNED_FMT:format(U.fmtInt(runGold) .. " " .. GOLD))
end

local function waveFailed()
    local c = camp()
    clearTargets()
    c.luck = math.min(LUCK_MAX, (c.luck or 0) + 1)
    U.play("IG_QUEST_FAILED")
    showShop(L.HUNT_WAVE_FAILED, L.HUNT_FAILED_SUB_FMT:format(U.fmtInt(runGold) .. " " .. GOLD,
        math.floor(c.luck * LUCK_SPEED * 100 + 0.5), c.luck))
end

local function finish()
    state = "over"
    setCrosshair(false)
    clearTargets()
    local d = data()
    d.rounds = d.rounds + 1
    local record = false
    if mode == "timed" and score > d.best then
        d.best = score
        record = true
    end
    drawStats()
    ns.UI.RefreshSidebar()
    local acc = shots > 0 and math.floor(hits / shots * 100 + 0.5) or 0
    local line2
    if record then
        line2 = L.HUNT_NEW_RECORD
    elseif mode == "timed" then
        line2 = L.HUNT_BEST_FMT:format(U.fmtInt(d.best))
    end
    U.play("IG_QUEST_LIST_COMPLETE")
    showOverlay(L.HUNT_OVER, L.HUNT_RESULT_FMT:format(U.fmtInt(score), hits, acc), line2, menuButtons())
end

local function earn(gold)
    gold = math.floor(gold * cfg.goldFactor + 0.5)
    local c = camp()
    c.gold = c.gold + gold
    runGold = runGold + gold
end

local function kill(t, x, y)
    if state ~= "running" or not t.alive then return end
    t.alive = false
    pcall(t.model.SetAnimation, t.model, 1)
    if t.bar then t.bar:Hide() end
    if t.critter then
        local c = camp()
        local loss = math.min(c.gold, 5)
        c.gold = c.gold - loss
        popup(x, y + 10, L.HUNT_CRITTER, 1, 0.5, 0.5)
        return
    end
    hits = hits + 1
    score = score + t.points
    data().hits = data().hits + 1
    earn(t.gold)
    if t.boss then
        data().bossKills = (data().bossKills or 0) + 1
    else
        kills = kills + 1
    end
    local r, g, b = 1, 1, 1
    if t.elite or t.boss then r, g, b = 1, 0.82, 0 end
    popup(x, y + 10, "+" .. math.floor(t.gold * cfg.goldFactor + 0.5) .. "g", r, g, b)
    if mode == "campaign" then
        if t.boss then
            waveCleared()
        elseif not cfg.boss and kills >= cfg.goal then
            waveCleared()
        end
    end
end

local function damageTarget(t, dmg, x, y)
    if state ~= "running" or not t.alive then return end
    t.hp = t.hp - dmg
    if t.hp <= 0 then
        kill(t, x, y)
    else
        popup(x, y + 10, "-" .. dmg, 1, 0.6, 0.6)
        placeTarget(t)
    end
end

-- Was liegt an diesem Punkt vorne? Liefert Ziele (nach Ebene) und Baum-Ebene
local function inRect(x, y, rx, ry, rw, rh, pad)
    pad = pad or 0
    return x >= rx - pad and x <= rx + rw + pad and y >= ry - pad and y <= ry + rh + pad
end

local function occluderLevel(x, y)
    local best = 0
    for _, o in ipairs(occluders) do
        if o.level > best and inRect(x, y, o.x, o.y, o.w, o.h) then best = o.level end
    end
    return best
end
G.OccluderLevel = occluderLevel

local function resolveShot(x, y, w)
    local radius = w.spread or 0
    local hitList = {}
    for _, t in ipairs(targets) do
        if t.alive then
            local hx, hy, hw, hh = hitbox(t)
            if inRect(x, y, hx, hy, hw, hh, radius) then hitList[#hitList + 1] = t end
        end
    end
    table.sort(hitList, function(a, b) return a.lane.level > b.lane.level end)
    local tree = w.pierce and 0 or occluderLevel(x, y)
    local top = hitList[1]
    if tree > 0 and (not top or tree > top.lane.level) then
        popup(x, y, L.HUNT_TREE, 0.75, 0.6, 0.4)
        return
    end
    local dmg = damage(w)
    if w.pierce then
        for _, t in ipairs(hitList) do if t.alive then damageTarget(t, dmg, x, y) end end
    elseif w.spread then
        for _, t in ipairs(hitList) do
            if t.alive and t.lane.level >= tree then damageTarget(t, dmg, x, y) end
        end
    elseif top then
        damageTarget(top, dmg, x, y)
    end
end

local function reload()
    local w = weapon()
    if not w.mag or ammo[w.id] == magSize(w) or reloading > 0 then return end
    reloading = reloadTime(w)
    playSound((w.id == "xbow") and "xbowReload" or "gunReload", "IG_BACKPACK_OPEN")
end

local function shoot()
    local w = weapon()
    if reloading > 0 or cooldown > 0 then return end
    if w.mag and (ammo[w.id] or 0) <= 0 then
        U.play("IG_MAINMENU_OPTION_CHECKBOX_OFF")
        return
    end
    if w.mag then ammo[w.id] = ammo[w.id] - 1 end
    cooldown = w.delay
    shots = shots + 1
    data().shots = data().shots + 1
    playShot(w)
    recoil = (w.id == "bow") and 0 or ((w.id == "scatter") and 12 or 7)
    local x, y = cursorPos()
    aimX, aimY = x, y
    local tipX, tipY = drawWeapon()
    if w.speed then
        -- Pfeil fliegt: Treffer wird beim Ankommen geprüft (vorhalten!)
        local dist = math.sqrt((x - tipX) ^ 2 + (y - tipY) ^ 2)
        local ln = table.remove(arrowPool)
        if not ln then
            ln = weaponFrame:CreateLine(nil, "OVERLAY")
            ln:SetThickness(2.5)
            ln:SetColorTexture(0.15, 0.12, 0.1, 1)
        end
        arrows[#arrows + 1] = { line = ln, x0 = tipX, y0 = tipY, x1 = x, y1 = y, t = 0, dur = dist / w.speed, w = w }
    else
        Wd.flash:ClearAllPoints()
        Wd.flash:SetPoint("CENTER", canvas, "BOTTOMLEFT", tipX, tipY)
        Wd.flash:SetSize(w.spread and 26 or 16, w.spread and 26 or 16)
        Wd.flash:Show()
        Wd.flash.t = 0.07
        resolveShot(x, y, w)
    end
    if w.mag and ammo[w.id] == 0 then reload() end
    drawHud()
end

local function updateArrows(dt)
    for i = #arrows, 1, -1 do
        local a = arrows[i]
        a.t = a.t + dt
        local f = math.min(1, a.t / math.max(a.dur, 0.01))
        local cx, cy = a.x0 + (a.x1 - a.x0) * f, a.y0 + (a.y1 - a.y0) * f
        local len = math.sqrt((a.x1 - a.x0) ^ 2 + (a.y1 - a.y0) ^ 2)
        local ux, uy = (a.x1 - a.x0) / math.max(len, 1), (a.y1 - a.y0) / math.max(len, 1)
        a.line:SetStartPoint("BOTTOMLEFT", canvas, cx - ux * 22, cy - uy * 22)
        a.line:SetEndPoint("BOTTOMLEFT", canvas, cx, cy)
        a.line:Show()
        if f >= 1 then
            a.line:Hide()
            arrowPool[#arrowPool + 1] = a.line
            table.remove(arrows, i)
            resolveShot(a.x1, a.y1, a.w)
            if state ~= "running" then return end -- Welle vorbei, Pfeile wurden geleert
        end
    end
end

selectWeapon = function(i)
    if i == weaponIndex or not camp().owned[WEAPONS[i].id] then return end
    weaponIndex = i
    reloading, cooldown = 0, 0.15
    local w = weapon()
    if w.mag and (ammo[w.id] or 0) <= 0 then reload() end
    drawSlots()
    drawHud()
end

local function switchWeapon(step)
    local c = camp()
    local n = #WEAPONS
    local i = weaponIndex
    for _ = 1, n do
        i = (i - 1 + step) % n + 1
        if c.owned[WEAPONS[i].id] then break end
    end
    selectWeapon(i)
end

local function drawHitboxes()
    local n = 0
    local function rectTex(x, y, w, h, r, g, b)
        n = n + 1
        local t = hitboxTex[n]
        if not t then
            t = hud:CreateTexture(nil, "OVERLAY")
            hitboxTex[n] = t
        end
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", x, y)
        t:SetSize(math.max(1, w), math.max(1, h))
        t:SetColorTexture(r, g, b, 0.28)
        t:Show()
    end
    if showHitboxes and state == "running" then
        for _, t in ipairs(targets) do
            if t.alive then
                local x, y, w, h = hitbox(t)
                rectTex(x, y, w, h, 1, 0.1, 0.1)
            end
        end
        for _, o in ipairs(occluders) do rectTex(o.x, o.y, o.w, o.h, 0.2, 0.4, 1) end
    end
    for i = n + 1, #hitboxTex do hitboxTex[i]:Hide() end
end

local function update(_, elapsed)
    local dt = math.min(elapsed, 0.1)
    if Wd.flash.t then
        Wd.flash.t = Wd.flash.t - dt
        if Wd.flash.t <= 0 then
            Wd.flash.t = nil
            Wd.flash:Hide()
        end
    end
    updatePopups(dt)
    updateParticles(dt)
    if bannerTime > 0 then
        bannerTime = bannerTime - dt
        Wd.banner:SetAlpha(math.min(1, bannerTime / 0.5))
        if bannerTime <= 0 then Wd.banner:Hide() end
    end
    recoil = math.max(0, recoil - dt * 90)
    if canvas:IsMouseOver() and state == "running" then aimX, aimY = cursorPos() end
    drawWeapon()
    drawHitboxes()
    if state ~= "running" then return end

    cursorTimer = cursorTimer - dt
    if cursorTimer <= 0 then
        cursorTimer = 0.25
        if canvas:IsMouseOver() then setCrosshair(true) end
    end

    if mode == "timed" then
        timeLeft = timeLeft - dt
        if timeLeft <= 0 then
            timeLeft = 0
            drawHud()
            finish()
            return
        end
    end

    cooldown = math.max(0, cooldown - dt)
    if reloading > 0 then
        reloading = reloading - dt
        if reloading <= 0 then
            reloading = 0
            local w = weapon()
            ammo[w.id] = magSize(w) or 0
        end
    end

    updateArrows(dt)
    if state ~= "running" then return end

    spawnTimer = spawnTimer - dt
    local alive = 0
    for _, t in ipairs(targets) do if t.alive and not t.boss then alive = alive + 1 end end
    if spawnTimer <= 0 and alive < cfg.maxAlive then
        spawn()
        spawnTimer = cfg.interval * (0.75 + math.random() * 0.5)
    end

    for i = #targets, 1, -1 do
        local t = targets[i]
        if t.alive then
            moveTarget(t, dt)
            if not t.boss and (t.x > W + 5 or t.x < -t.w - 5) then
                local counts = not t.critter
                releaseTarget(i)
                if counts and mode == "campaign" and not cfg.boss then
                    escaped = escaped + 1
                    if escaped > cfg.lives then
                        waveFailed()
                        return
                    end
                end
            else
                placeTarget(t)
            end
        else
            t.dying = t.dying + dt
            if t.dying > 0.9 then t.model:SetAlpha(math.max(0, 1 - (t.dying - 0.9) / 0.6)) end
            if t.dying > 1.5 then releaseTarget(i) end
        end
    end
    drawHud()
end

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------

local function buildShop()
    shop = CreateFrame("Frame", nil, canvas)
    shop:SetAllPoints()
    shop:SetFrameLevel(canvas:GetFrameLevel() + 30)
    shop:EnableMouse(true)
    local bg = shop:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.035, 0.07, 0.95)
    Wd.shopTitle = U.text(shop, "GameFontNormalLarge", 1, 0.82, 0)
    Wd.shopTitle:SetPoint("TOPLEFT", 12, -10)
    Wd.shopSub = U.text(shop, "GameFontHighlightSmall", 0.85, 0.85, 0.9)
    Wd.shopSub:SetPoint("TOPLEFT", Wd.shopTitle, "BOTTOMLEFT", 0, -3)
    Wd.shopSub:SetWidth(W - 24)
    Wd.shopSub:SetJustifyH("LEFT")
    Wd.shopSub:SetWordWrap(false)
    Wd.shopGold = U.text(shop, "GameFontNormalLarge", 1, 1, 1)
    Wd.shopGold:SetPoint("TOPRIGHT", -12, -10)

    local head1 = U.text(shop, "GameFontNormal")
    head1:SetPoint("TOPLEFT", 12, -46)
    head1:SetText(L.HUNT_SHOP_WEAPONS)
    local hint = U.text(shop, "GameFontDisableSmall")
    hint:SetPoint("LEFT", head1, "RIGHT", 8, 0)
    hint:SetText(L.HUNT_SHOP_HOVER)
    Wd.shopWeapons = {}
    for i = 1, #WEAPONS do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x, y = 12 + col * 184, -64 - row * 38
        -- unsichtbare Fläche über Symbol + Name für den Tooltip
        local hover = CreateFrame("Frame", nil, shop)
        hover:SetPoint("TOPLEFT", x, y)
        hover:SetSize(170, 32)
        hover:EnableMouse(true)
        hover:SetScript("OnEnter", function(self) weaponTooltip(self, i) end)
        hover:SetScript("OnLeave", hideTooltip)
        local icon = hover:CreateTexture(nil, "ARTWORK")
        icon:SetSize(32, 32)
        icon:SetPoint("TOPLEFT")
        local name = U.text(hover, "GameFontHighlightSmall")
        name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
        name:SetWidth(132)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        local b = U.button(shop, "", 84, 18)
        b:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 0)
        b:SetFrameLevel(hover:GetFrameLevel() + 2)
        b:SetScript("OnClick", function() buyWeapon(i) end)
        Wd.shopWeapons[i] = { icon = icon, name = name, button = b }
    end

    local head2 = U.text(shop, "GameFontNormal")
    head2:SetPoint("TOPLEFT", 12, -144)
    head2:SetText(L.HUNT_SHOP_UPGRADES)
    Wd.shopUps = {}
    for i, u in ipairs(UPGRADES) do
        local y = -162 - (i - 1) * 23
        local icon = shop:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("TOPLEFT", 12, y)
        icon:SetTexture(u.icon)
        local name = U.text(shop, "GameFontHighlightSmall")
        name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        name:SetWidth(262)
        name:SetJustifyH("LEFT")
        local b = U.button(shop, "", 84, 20)
        b:SetPoint("TOPRIGHT", shop, "TOPRIGHT", -12, y)
        b:SetScript("OnClick", function() buyUpgrade(i) end)
        Wd.shopUps[i] = { name = name, button = b }
    end

    Wd.shopNext = U.button(shop, "", 150, 24)
    Wd.shopNext:SetPoint("BOTTOMRIGHT", -12, 10)
    Wd.shopNext:SetScript("OnClick", startWave)
    local menu = U.button(shop, L.HUNT_MENU, 100, 24)
    menu:SetPoint("BOTTOMLEFT", 12, 10)
    menu:SetScript("OnClick", showMenu)
    shop:Hide()
end

function G.Build(p)
    pane = p
    enemyFaction = myEnemies()

    canvas = CreateFrame("Frame", nil, pane)
    canvas:SetSize(W, H)
    canvas:SetPoint("TOP", 0, -4)
    pcall(canvas.SetClipsChildren, canvas, true)
    U.addBackdrop(canvas, { 0.25, 0.22, 0.32, 1 }, { 0, 0, 0, 1 })
    setTheme(1)

    weaponFrame = CreateFrame("Frame", nil, canvas)
    weaponFrame:SetAllPoints()
    weaponFrame:SetFrameLevel(canvas:GetFrameLevel() + 9)

    -- HUD
    hud = CreateFrame("Frame", nil, canvas)
    hud:SetAllPoints()
    hud:SetFrameLevel(canvas:GetFrameLevel() + 10)
    Wd.top = U.text(hud, "GameFontNormalLarge", 1, 1, 1)
    Wd.top:SetPoint("TOPLEFT", 10, -8)
    Wd.top2 = U.text(hud, "GameFontHighlightSmall", 0.9, 0.9, 0.9)
    Wd.top2:SetPoint("TOPLEFT", Wd.top, "BOTTOMLEFT", 0, -2)
    Wd.right = U.text(hud, "GameFontNormalLarge", 1, 1, 1)
    Wd.right:SetPoint("TOPRIGHT", -10, -8)
    Wd.bullets = {}
    for i = 1, 14 do
        local b = hud:CreateTexture(nil, "OVERLAY")
        b:SetSize(12, 12)
        b:SetPoint("BOTTOMLEFT", 8 + (i - 1) * 13, 8)
        Wd.bullets[i] = b
    end
    Wd.infinite = U.text(hud, "GameFontHighlightSmall", 1, 1, 1)
    Wd.infinite:SetPoint("BOTTOMLEFT", 10, 10)
    Wd.infinite:SetText(L.HUNT_ARROWS_INF)
    Wd.reloadHint = U.text(hud, "GameFontNormal", 1, 0.82, 0)
    Wd.reloadHint:SetPoint("BOTTOMLEFT", 8, 24)
    Wd.reloadHint:SetText(L.HUNT_RELOAD)
    Wd.slots = {}
    for i = 1, #WEAPONS do
        local s = CreateFrame("Button", nil, hud)
        s:SetSize(26, 26)
        s:SetPoint("BOTTOMRIGHT", -8 - (#WEAPONS - i) * 30, 8)
        s.sel = s:CreateTexture(nil, "BACKGROUND")
        s.sel:SetPoint("TOPLEFT", -2, 2)
        s.sel:SetPoint("BOTTOMRIGHT", 2, -2)
        s.sel:SetColorTexture(1, 0.82, 0, 1)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetAllPoints()
        s:SetScript("OnClick", function() if state == "running" then selectWeapon(i) end end)
        s:SetScript("OnEnter", function(self) weaponTooltip(self, i) end)
        s:SetScript("OnLeave", hideTooltip)
        Wd.slots[i] = s
    end
    Wd.flash = hud:CreateTexture(nil, "OVERLAY", nil, 2)
    Wd.flash:SetSize(16, 16)
    Wd.flash:SetColorTexture(1, 0.9, 0.4, 0.9)
    U.maskCircle(hud, Wd.flash)
    Wd.flash:Hide()

    Wd.banner = CreateFrame("Frame", nil, hud)
    Wd.banner:SetSize(W, 60)
    Wd.banner:SetPoint("TOP", 0, -46)
    Wd.bannerTitle = U.text(Wd.banner, "GameFontNormalHuge", 1, 0.82, 0)
    Wd.bannerTitle:SetPoint("TOP")
    Wd.bannerSub = U.text(Wd.banner, "GameFontHighlight")
    Wd.bannerSub:SetPoint("TOP", Wd.bannerTitle, "BOTTOM", 0, -4)
    Wd.bannerSub:SetWidth(W - 20)
    Wd.banner:Hide()

    -- Menü-/Pause-/Ergebnis-Overlay
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetSize(310, 160)
    overlay:SetPoint("CENTER", 0, 10)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 20)
    overlay:EnableMouse(true)
    U.addBackdrop(overlay, { 0.42, 0.38, 0.52, 1 }, { 0.05, 0.04, 0.08, 0.93 })
    Wd.ovTitle = U.text(overlay, "GameFontNormalHuge", 1, 0.82, 0)
    Wd.ovTitle:SetPoint("TOP", 0, -12)
    Wd.ovLine1 = U.text(overlay, "GameFontHighlight")
    Wd.ovLine1:SetPoint("TOP", Wd.ovTitle, "BOTTOM", 0, -10)
    Wd.ovLine1:SetWidth(290)
    Wd.ovLine2 = U.text(overlay, "GameFontNormal", 0.4, 1, 0.5)
    Wd.ovLine2:SetPoint("TOP", Wd.ovLine1, "BOTTOM", 0, -6)
    Wd.ovLine2:SetWidth(290)
    Wd.ovButtons = {}
    for i = 1, 3 do
        local b = U.button(overlay, "", 92, 24)
        b:SetScript("OnClick", function(self) if self.action then self.action() end end)
        Wd.ovButtons[i] = b
    end
    buildShop()

    -- Eingabe: nur Maus
    canvas:EnableMouse(true)
    pcall(canvas.EnableMouseWheel, canvas, true)
    canvas:SetScript("OnMouseDown", function(_, button)
        if state ~= "running" then return end
        if button == "RightButton" then reload() else shoot() end
    end)
    canvas:SetScript("OnMouseWheel", function(_, delta)
        if state == "running" then switchWeapon(delta > 0 and -1 or 1) end
    end)
    canvas:SetScript("OnEnter", function() if state == "running" then setCrosshair(true) end end)
    canvas:SetScript("OnLeave", function() setCrosshair(false) end)
    canvas:SetScript("OnUpdate", update)

    -- Unter dem Spielfeld
    local controls = U.text(pane, "GameFontHighlightSmall", 0.85, 0.85, 0.9)
    controls:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 2, -10)
    controls:SetWidth(W - 120)
    controls:SetJustifyH("LEFT")
    controls:SetText(L.HUNT_CONTROLS)
    Wd.stats = U.text(pane, "GameFontHighlightSmall", 0.75, 0.75, 0.8)
    Wd.stats:SetPoint("TOPLEFT", controls, "BOTTOMLEFT", 0, -8)
    Wd.stats:SetWidth(W)
    Wd.stats:SetJustifyH("LEFT")
    Wd.endButton = U.button(pane, L.HUNT_END, 110, 22)
    Wd.endButton:SetPoint("TOPRIGHT", canvas, "BOTTOMRIGHT", 0, -8)
    Wd.endButton:SetScript("OnClick", function()
        if mode == "campaign" then pause() else finish() end
    end)

    cfg = relaxedConfig()
    refill()
    drawSlots()
    drawHud()
    showMenu()

    -- Waffe im Spiel gewechselt -> Symbole und Namen aktualisieren
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:SetScript("OnEvent", function()
        drawSlots()
        if shop:IsShown() then refreshShop() end
    end)

    pane:SetScript("OnShow", function()
        drawSlots()
        if state == "ready" then
            enemyFaction = myEnemies()
            showMenu()
        end
        drawStats()
    end)
    pane:SetScript("OnHide", function()
        pause()
        setCrosshair(false)
    end)
end

function G.OnCombat()
    pause()
    setCrosshair(false)
end

function G.ToggleHitbox()
    showHitboxes = not showHitboxes
    ns.Print(showHitboxes and L.HUNT_HITBOX_ON or L.HUNT_HITBOX_OFF)
end

-- Nur für Tests
function G.Debug()
    return { state = state, mode = mode, cfg = cfg, score = score, hits = hits, shots = shots, kills = kills,
             escaped = escaped, ammo = ammo, reloading = reloading, cooldown = cooldown, timeLeft = timeLeft,
             targets = targets, canvas = canvas, enemy = enemyFaction, weapon = weapon(), weaponIndex = weaponIndex,
             camp = camp(), boss = boss, occluders = occluders, hitbox = hitbox, magSize = magSize,
             arrows = arrows, shop = shop, overlay = overlay, buyWeapon = buyWeapon, buyUpgrade = buyUpgrade,
             startWave = startWave, WEAPONS = WEAPONS, UPGRADES = UPGRADES, waveConfig = waveConfig,
             LANES = LANES, ENEMIES = ENEMIES, newTarget = newTarget, showHitboxes = showHitboxes,
             hitboxTex = hitboxTex, theme = activeTheme, themes = themeSets, banner = Wd.banner,
             realWeapon = realWeapon, damage = damage, reloadTime = reloadTime, selectWeapon = selectWeapon, startMode = startMode }
end

ns.RegisterGame(G)
