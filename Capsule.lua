local addonName, ns = ...
local L = ns.L
local issecretvalue = issecretvalue or function() return false end

local TEXTURE_FILL = "Interface\\AddOns\\TrisThreat\\Assets\\Capsule_Fill.tga"
local TEXTURE_BORDER = "Interface\\AddOns\\TrisThreat\\Assets\\Capsule_Border.tga"
local WIDTH, HEIGHT = 56, 28

local active = {}   -- unit token -> capsule
local pool = {}
local preview       -- capsule shown by the options window

----------------------------------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------------------------------

local function createCapsule()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(TEXTURE_FILL)
    f.bg:SetVertexColor(0.04, 0.045, 0.055, 0.9)

    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    f.bar:SetStatusBarTexture(TEXTURE_FILL)
    f.bar:SetMinMaxValues(0, 100)
    f.bar:SetValue(100)

    f.top = CreateFrame("Frame", nil, f)
    f.top:SetAllPoints()
    f.top:SetFrameLevel(f.bar:GetFrameLevel() + 2)
    f.border = f.top:CreateTexture(nil, "OVERLAY")
    f.border:SetAllPoints()
    f.border:SetTexture(TEXTURE_BORDER)
    f.border:SetVertexColor(0.88, 0.68, 0.24, 1)

    f.text = f.top:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    f.text:SetPoint("CENTER", f.top, "CENTER", 0, 0)
    f.text:SetTextColor(1, 1, 1, 1)
    return f
end

local function acquire()
    return table.remove(pool) or createCapsule()
end

local function release(unit)
    local f = active[unit]
    if not f then return end
    active[unit] = nil
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(UIParent)
    pool[#pool + 1] = f
end

local function layout(f, plate)
    local db = TrisThreatDB
    local scale = db.scale
    f:SetParent(plate)
    f:SetScale(scale)
    f:ClearAllPoints()
    -- Default: attached to the plate's top-left corner. Offsets are plate pixels (positive = right / up).
    f:SetPoint("TOPLEFT", plate, "TOPLEFT", db.offsetX / scale, db.offsetY / scale)
    f:SetFrameStrata("HIGH")
end

local function paint(f, colorKey, textValue, barValue)
    local c = ns.COLORS[colorKey] or ns.COLORS.unknown
    f.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    f.bar:SetValue(TrisThreatDB.showBar and barValue or 100)
    f.text:SetText(textValue or "")
    f:Show()
end

----------------------------------------------------------------------------------------------------
-- Threat reading (every API result is checked for secret values before it is compared)
----------------------------------------------------------------------------------------------------

local function readStatus(unit)
    local status = UnitThreatSituation("player", unit)
    if status == nil then return nil end
    if issecretvalue(status) then return false end
    return status
end

local function formatPercent(value, prefix)
    if value == nil then return "" end
    if C_StringUtil and C_StringUtil.RoundToNearestString then
        return (prefix or "") .. C_StringUtil.RoundToNearestString(value) .. "%"
    end
    if issecretvalue(value) then return "" end
    return (prefix or "") .. math.floor(value + 0.5) .. "%"
end

-- Returns text and a value for the fill bar. Secret numbers go straight to the engine (SetText / SetValue).
local function readValue(unit, mode, status)
    if mode == "lead" and status == 3 and UnitThreatPercentageOfLead then
        local lead = UnitThreatPercentageOfLead("player", unit)
        return formatPercent(lead, "+"), lead or 0
    end
    local _, _, scaled, raw = UnitDetailedThreatSituation("player", unit)
    local value = (mode == "raw") and raw or scaled
    return formatPercent(value), value or 0
end

local function holds(tankUnit, unit)
    if not UnitExists(tankUnit) then return false end
    local status = UnitThreatSituation(tankUnit, unit)
    return status ~= nil and not issecretvalue(status) and status == 3
end

-- Another tank (assigned role TANK) or your own pet holds the mob.
local function otherHolds(unit)
    if holds("pet", unit) then return true end
    local prefix, count
    if IsInRaid and IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup and IsInGroup() then prefix, count = "party", GetNumSubgroupMembers()
    else return false end
    for index = 1, count do
        local member = prefix .. index
        local same = UnitIsUnit(member, "player")
        if same ~= nil and not issecretvalue(same) and not same then
            local role = UnitGroupRolesAssigned(member)
            if role == "TANK" and holds(member, unit) then return true end
        end
    end
    return false
end

----------------------------------------------------------------------------------------------------
-- Update
----------------------------------------------------------------------------------------------------

local function safeClassification(unit)
    local value = UnitClassification and UnitClassification(unit)
    if issecretvalue(value) then return nil end
    return value
end

function ns.UpdateUnit(unit)
    local db = TrisThreatDB
    if not db then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then release(unit); return end
    local attackable = UnitCanAttack("player", unit)
    if issecretvalue(attackable) then attackable = true end
    local dead = UnitIsDead(unit)
    if issecretvalue(dead) then dead = false end
    if not attackable or dead
        or not ns.ShouldShow(db, safeClassification(unit), IsInInstance and IsInInstance() or false) then
        release(unit); return
    end
    local status = readStatus(unit)
    if status == nil then release(unit); return end

    local role = ns.GetRole()
    local offTank = status ~= false and db.offTank and role == "tank" and status < 3 and otherHolds(unit)
    local colorKey = ns.StatusColorKey(status, role, offTank)
    local text, barValue = readValue(unit, db.value, status)

    local f = active[unit]
    if not f then f = acquire(); active[unit] = f end
    layout(f, plate)
    paint(f, colorKey, text, barValue)
end

local function plateUnit(plate)
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit == nil or issecretvalue(unit) then return nil end
    return unit
end

function ns.RefreshAll()
    local seen = {}
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plateUnit(plate)
        if unit then
            seen[unit] = true
            ns.UpdateUnit(unit)
        end
    end
    for unit in pairs(active) do
        if not seen[unit] then release(unit) end
    end
end

-- Re-anchors every shown capsule (options sliders).
function ns.ApplyLayout()
    for unit, f in pairs(active) do
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate then layout(f, plate) end
    end
    if preview and preview:IsShown() then
        local plate = C_NamePlate.GetNamePlateForUnit("target")
        if plate then layout(preview, plate) end
    end
end

function ns.ShowPreview()
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if not plate then return false end
    preview = preview or createCapsule()
    layout(preview, plate)
    local role = ns.GetRole()
    paint(preview, role == "tank" and "good" or "warn", "70%", 70)
    return true
end

function ns.HidePreview()
    if preview then preview:Hide() end
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

local dirty, elapsed = false, 0
local lastRole

function ns.QueueRefresh() dirty = true end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        TrisThreatDB = ns.NormalizeDB(TrisThreatDB)
        self:UnregisterEvent("ADDON_LOADED")
        for _, name in ipairs({ "PLAYER_ENTERING_WORLD", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
            "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
            "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_EQUIPMENT_CHANGED",
            "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED" }) do
            pcall(self.RegisterEvent, self, name)
        end
        self:RegisterUnitEvent("UNIT_AURA", "player")
        self:SetScript("OnUpdate", function(_, delta)
            elapsed = elapsed + delta
            if dirty and elapsed >= 0.1 then
                dirty, elapsed = false, 0
                ns.RefreshAll()
            end
        end)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        ns.UpdateUnit(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        release(arg1)
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        if type(arg1) == "string" and not issecretvalue(arg1) and arg1:find("^nameplate") then
            ns.UpdateUnit(arg1)
        else
            dirty = true
        end
    elseif event == "UNIT_AURA" then
        -- A tank buff (Righteous Fury, Bear Form aura...) can change the detected role.
        local role = ns.GetRole()
        if role ~= lastRole then lastRole = role; dirty = true end
    else
        lastRole = ns.GetRole()
        dirty = true
    end
end)
