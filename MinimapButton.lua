-- AFKade – Minimap-Button
-- Linksklick: Fenster öffnen/schließen, Rechtsklick: Einstellungen,
-- Ziehen: am Minimap-Rand verschieben (Position wird gespeichert).

local _, ns = ...
local L, U = ns.L, ns.U
local M = {}
ns.MinimapButton = M

local ICON = ns.MEDIA .. "logo"
local DEFAULT_ANGLE = 220
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local button

local function updatePosition()
    local angle = math.rad(ns.db.minimapAngle or DEFAULT_ANGLE)
    local x, y = math.cos(angle), math.sin(angle)
    -- Eckige Minimaps (z. B. durch UI-Addons): an den Rand des Quadrats schieben
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape ~= "ROUND" then
        x = math.max(-1, math.min(1, x * 1.414))
        y = math.max(-1, math.min(1, y * 1.414))
    end
    local r = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.minimapAngle = math.deg(atan2(cy / scale - my, cx / scale - mx))
    updatePosition()
end

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(L.TITLE)
    GameTooltip:AddLine(L.TOTAL_SOLVED_FMT:format(ns.char.solved, ns.MaxSolved()), 1, 1, 1)
    local sprint = ns.GameData("sprint")
    if sprint then GameTooltip:AddLine(L.SPRINT_BEST_FMT:format(U.fmtInt(sprint.best or 0)), 1, 1, 1) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.MM_LEFT, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L.MM_RIGHT, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L.MM_DRAG, 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function M.Create()
    if button or not Minimap then return end
    button = CreateFrame("Button", "AFKadeMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Aufbau wie die Standard-Minimap-Buttons: Hintergrund, Symbol, Goldrand
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", 7, -6)
    U.maskCircle(button, icon)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    button.icon = icon

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            ns.UI.Open("settings")
        else
            ns.UI.Toggle()
        end
    end)
    -- Kleiner "Drück"-Effekt
    button:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 8, -7) end)
    button:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 7, -6) end)
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", onDragUpdate)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
        icon:SetPoint("TOPLEFT", 7, -6)
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updatePosition()
    M.Refresh()
end

function M.Refresh()
    if button then button:SetShown(ns.db.settings.minimap) end
end

-- Addon-Sammelmenü neben der Minimap (nur in Clients, die es haben)
function AFKade_OnAddonCompartmentClick(_, mouse)
    if mouse == "RightButton" then
        ns.UI.Open("settings")
    else
        ns.UI.Toggle()
    end
end
