-- AFKade – Fotograf-Modus
--
-- Sammelt Orte für das geplante GeoGuessr-Spiel: Bei jedem Screenshot
-- (Druck-Taste oder /afkade snap) werden Zone, Teilzone, Kartenkoordinaten,
-- Weltposition und Uhrzeit gespeichert. Über die Uhrzeit lässt sich jeder
-- Eintrag später seiner Bilddatei zuordnen (WoWScrnShot_MMTTJJ_HHMMSS.jpg).
-- Daten liegen accountweit in AFKadeDB.photos.

local _, ns = ...
local L = ns.L
local Ph = {}
ns.Photographer = Ph

local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

local function clean(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

local function round(v)
    return v and math.floor(v * 10000 + 0.5) / 10000
end

local function mapPos(mapID)
    if not mapID then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not pos then return end
    local x, y = pos:GetXY()
    x, y = clean(x), clean(y)
    if x and y then return round(x), round(y) end
end

local function continentOf(mapID)
    local id = mapID
    for _ = 1, 10 do
        local info = id and C_Map.GetMapInfo(id)
        if not info then return end
        if info.mapType == CONTINENT then return id, info.name end
        id = info.parentMapID
    end
end

function Ph.Count()
    return #ns.db.photos
end

function Ph.Record()
    local rec = {
        ts = time(),
        shot = date("%m%d%y_%H%M%S"),
        char = UnitName("player"),
        zone = clean(GetRealZoneText()),
        subzone = clean(GetSubZoneText()),
    }
    local mapID = clean(C_Map.GetBestMapForUnit("player"))
    if mapID then
        rec.map = mapID
        local info = C_Map.GetMapInfo(mapID)
        rec.mapName = info and info.name
        rec.x, rec.y = mapPos(mapID)
        local cont, contName = continentOf(mapID)
        if cont then
            rec.cont, rec.contName = cont, contName
            rec.cx, rec.cy = mapPos(cont)
        end
    end
    local ok, wy, wx, _, inst = pcall(UnitPosition, "player")
    if ok and clean(wx) and clean(wy) then
        rec.wx, rec.wy, rec.inst = round(wx), round(wy), inst
    end
    local fok, facing = pcall(GetPlayerFacing)
    if fok and clean(facing) then rec.facing = round(facing) end

    table.insert(ns.db.photos, rec)

    local place = rec.zone or rec.mapName or "?"
    if rec.subzone and rec.subzone ~= "" and rec.subzone ~= place then
        place = rec.subzone .. ", " .. place
    end
    local coords = rec.x and ("%.1f, %.1f"):format(rec.x * 100, rec.y * 100) or L.PHOTO_NOCOORDS
    ns.Print(L.PHOTO_SAVED_FMT:format(place, coords, Ph.Count()))
end

---------------------------------------------------------------------------
-- /afkade snap: Interface kurz ausblenden, Screenshot, wieder einblenden
---------------------------------------------------------------------------

local snapping, restoreUI = false, false

local function finishSnap()
    if not snapping then return end
    snapping = false
    if restoreUI then UIParent:Show() end
    restoreUI = false
end

function Ph.Snap()
    if not ns.db.settings.photographer then
        ns.Print(L.PHOTO_NEED_MODE)
        return
    end
    if InCombatLockdown() then
        ns.Print(L.PHOTO_COMBAT)
        return
    end
    if snapping then return end
    snapping = true
    restoreUI = UIParent:IsShown()
    if restoreUI then UIParent:Hide() end
    C_Timer.After(0.15, function() pcall(Screenshot) end)
    C_Timer.After(4, finishSnap) -- Sicherheitsnetz, falls kein Event kommt
end

function Ph.Toggle()
    local s = ns.db.settings
    s.photographer = not s.photographer
    ns.Print(s.photographer and L.PHOTO_ON or L.PHOTO_OFF)
end

function Ph.OnEvent(event)
    if event == "SCREENSHOT_SUCCEEDED" and ns.db.settings.photographer then
        Ph.Record()
    end
    finishSnap()
end
