local addonName, ns = ...
local L = ns.L

local ICON = "Interface\\AddOns\\TrisThreat\\Assets\\TrisThreatIcon.tga"
local launcher
local MINIMAP_BUTTON = "LibDBIcon10_" .. addonName

local function openSettings()
    if ns.ToggleOptions then ns.ToggleOptions() end
end

local function addTooltipLines(tooltip)
    tooltip:AddLine("TrisThreat", 1, 0.82, 0.2)
    tooltip:AddLine(L["Click: open settings"], 0.85, 0.88, 0.94)
end

-- AddonCompartment callbacks named in the TOCs. Arguments are optional and checked before use.
function TrisThreat_OnAddonCompartmentClick() openSettings() end

function TrisThreat_OnAddonCompartmentEnter(_, frame)
    if not GameTooltip then return end
    if type(frame) == "table" and frame.GetObjectType then
        GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    else
        GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    end
    addTooltipLines(GameTooltip)
    GameTooltip:Show()
end

function TrisThreat_OnAddonCompartmentLeave()
    if GameTooltip then GameTooltip:Hide() end
end

function ns.ApplyMinimap()
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (icon and launcher and TrisThreatDB) then return end
    if TrisThreatDB.minimap.hide then icon:Hide(addonName) else icon:Show(addonName) end
end

local function onClick(frame, button)
    -- Right-click on the minimap button hides it; Titan and other displays keep their own menus.
    if button == "RightButton" and type(frame) == "table" and frame.GetName and frame:GetName() == MINIMAP_BUTTON then
        TrisThreatDB.minimap.hide = true
        ns.ApplyMinimap()
        if ns.RefreshOptions then ns.RefreshOptions() end
        print("|cffe0ad3dTrisThreat|r: " .. L["Right-click the minimap icon to hide it. Bring it back under Show minimap icon in the settings."])
        return
    end
    openSettings()
end

local function register()
    if launcher or not LibStub or not TrisThreatDB then return end
    local broker = LibStub("LibDataBroker-1.1", true)
    if not broker then return end
    launcher = broker:NewDataObject(addonName, {
        type = "launcher",
        label = "TrisThreat",
        tocname = addonName,
        icon = ICON,
        OnClick = onClick,
        OnTooltipShow = addTooltipLines,
    })
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if dbIcon then dbIcon:Register(addonName, launcher, TrisThreatDB.minimap) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    register()
    self:UnregisterAllEvents()
end)
