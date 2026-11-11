local addonName, ns = ...
local issecretvalue = issecretvalue or function() return false end

local active = {}   -- unit token -> element
local pool = {}
local tints = {}    -- unit token -> color while the Blizzard health bar is tinted by threat
local preview       -- element shown on the target while the options window is open

----------------------------------------------------------------------------------------------------
-- Nameplate parts. Blizzard plates get the integrated modes; any other nameplate addon gets the floating
-- badge anchored to the plate (no knowledge of other addons' internals is used).
----------------------------------------------------------------------------------------------------

local function getParts(plate)
    local uf = plate.UnitFrame
    local container = uf and uf.HealthBarsContainer
    local bar = container and container.healthBar
    if bar and uf.IsVisible and uf:IsVisible() then
        local level = uf.PlayerLevelDiffFrame
        return { uf = uf, bar = bar, level = level, blizzard = true }
    end
    return { uf = plate, bar = plate, blizzard = false }
end
ns.GetParts = getParts

local function safeNumber(fn, obj)
    local ok, value = pcall(fn, obj)
    if ok and type(value) == "number" and not issecretvalue(value) then return value end
    return nil
end

-- Measurements for ns.Layout from the live (or mock) parts.
function ns.Measure(parts)
    local m = { barW = safeNumber(parts.bar.GetWidth, parts.bar) or 190, barH = safeNumber(parts.bar.GetHeight, parts.bar) or 20 }
    local level = parts.level
    if level and level:IsShown() then
        m.levelShown = true
        m.levelW = safeNumber(level.GetWidth, level)
        m.levelH = safeNumber(level.GetHeight, level)
        -- Forever anchors the badge to the bar's right edge, Retail to its left: read the side from the anchor.
        local ok, _, _, relPoint = pcall(level.GetPoint, level, 1)
        m.levelRight = ok and type(relPoint) == "string" and relPoint:find("RIGHT") ~= nil
        if not (m.levelW and m.levelH) then m.levelShown = false end
    end
    return m
end

local function hookLayout(uf)
    if uf.trisThreatHooked or type(uf.UpdateAnchors) ~= "function" then return end
    uf.trisThreatHooked = true
    hooksecurefunc(uf, "UpdateAnchors", function(self) ns.RoomWasReset(self) end)
end

-- Places an element on parts with the current settings. Returns the spec.
function ns.Arrange(el, parts)
    local db = TrisThreatDB
    local mode = (parts.blizzard or parts.mock) and db.mode or "floating"
    local spec = ns.Layout(mode, db.side, ns.Measure(parts), db)
    ns.PlaceElement(el, parts, spec)
    if parts.blizzard or parts.mock then
        if parts.blizzard then hookLayout(parts.uf) end
        ns.SyncRoom(parts.uf, (db.makeRoom and mode ~= "floating") and spec.room or nil)
    end
    return spec
end

----------------------------------------------------------------------------------------------------
-- Health bar tint (Blizzard plates only, option "Color the nameplate bar")
----------------------------------------------------------------------------------------------------

local function applyTint(bar, color)
    pcall(bar.SetStatusBarColor, bar, color[1], color[2], color[3])
end

if CompactUnitFrame_UpdateHealthColor then
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        local unit = frame and frame.unit
        if unit and not issecretvalue(unit) and tints[unit] and frame.healthBar then applyTint(frame.healthBar, tints[unit]) end
    end)
end

local function clearTint(unit, parts)
    if not tints[unit] then return end
    tints[unit] = nil
    if parts and parts.blizzard and CompactUnitFrame_UpdateHealthColor then
        pcall(CompactUnitFrame_UpdateHealthColor, parts.uf)
    end
end

----------------------------------------------------------------------------------------------------
-- Pool
----------------------------------------------------------------------------------------------------

local function acquire()
    return table.remove(pool) or ns.CreateElement()
end

local function release(unit)
    local el = active[unit]
    if not el then return end
    active[unit] = nil
    if el.parts then
        clearTint(unit, el.parts)
        if el.parts.blizzard then ns.SyncRoom(el.parts.uf, nil) end
    end
    el.parts = nil
    el:Hide()
    el:ClearAllPoints()
    el:SetParent(UIParent)
    pool[#pool + 1] = el
end

----------------------------------------------------------------------------------------------------
-- Gradient: a color curve evaluated by the engine, so a secret percentage still gives a color
----------------------------------------------------------------------------------------------------

local curves = {}   -- "dps" | "tank" -> color curve (false = unavailable)

local function buildCurve(tank)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return false end
    local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not curve then return false end
    pcall(function()
        if curve.SetType and Enum and Enum.LuaCurveType then curve:SetType(Enum.LuaCurveType.Linear) end
        for _, stop in ipairs(ns.GRADIENT_STOPS) do
            local c = ns.GradientColor(tank and (100 - stop[1]) or stop[1], false)
            curve:AddPoint(stop[1], CreateColor(c[1], c[2], c[3], 1))
        end
        -- Values above 100 (raw percentages can exceed it) keep the end color instead of extrapolating.
        local last = ns.GradientColor(tank and 0 or 100, false)
        curve:AddPoint(1000, CreateColor(last[1], last[2], last[3], 1))
    end)
    return curve
end

-- Returns { r, g, b } (the numbers may be secret values) or nil when the curve cannot be evaluated.
local function curveColor(role, value)
    if value == nil then return nil end
    local key = role == "tank" and "tank" or "dps"
    if curves[key] == nil then curves[key] = buildCurve(key == "tank") end
    local curve = curves[key]
    if not curve then return nil end
    local ok, color = pcall(curve.Evaluate, curve, value)
    if not ok or not color then return nil end
    local ok2, r, g, b = pcall(color.GetRGB, color)
    if not ok2 or r == nil then return nil end
    return { r, g, b }
end

-- Used by /tt probe.
function ns.ProbeCurve(value)
    local color = curveColor("dps", value)
    return color ~= nil, color
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

-- Returns the display text. Secret numbers go straight to the engine (SetText).
local function readValue(unit, mode, status)
    if mode == "lead" and status == 3 and UnitThreatPercentageOfLead then
        return formatPercent(UnitThreatPercentageOfLead("player", unit), "+")
    end
    local _, _, scaled, raw = UnitDetailedThreatSituation("player", unit)
    return formatPercent((mode == "raw") and raw or scaled)
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

local function safeClassification(unit)
    local value = UnitClassification and UnitClassification(unit)
    if issecretvalue(value) then return nil end
    return value
end

local function isTargetPlate(plate)
    return plate ~= nil and plate == C_NamePlate.GetNamePlateForUnit("target")
end

----------------------------------------------------------------------------------------------------
-- Update
----------------------------------------------------------------------------------------------------

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
    local color = ns.COLORS[ns.StatusColorKey(status, role, offTank)] or ns.COLORS.unknown
    local _, _, scaled = UnitDetailedThreatSituation("player", unit)
    if offTank then
        color = ns.COLORS.offtank
    elseif scaled ~= nil then
        color = curveColor(role, scaled) or color
    end

    local el = active[unit]
    if not el then el = acquire(); active[unit] = el end
    local parts = getParts(plate)
    if el.parts and el.parts.uf ~= parts.uf and el.parts.blizzard then ns.SyncRoom(el.parts.uf, nil) end
    el.parts = parts
    ns.Arrange(el, parts)
    ns.PaintElement(el, color, readValue(unit, db.value, status), scaled, isTargetPlate(plate))

    if db.colorBar and parts.blizzard then
        tints[unit] = color
        applyTint(parts.bar, color)
    else
        clearTint(unit, parts)
    end
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
    if preview and preview:IsShown() then ns.ShowPreview() end
end

-- Settings changed (mode, side, offsets, colors): re-place everything.
function ns.ApplyLayout()
    ns.RefreshAll()
end

----------------------------------------------------------------------------------------------------
-- Test mode: an element on the current target while the options window is open (no combat needed)
----------------------------------------------------------------------------------------------------

ns.previewPercent = 70
ns.previewOffTank = false
local previewParts, previewUnit

local function clearPreview()
    if previewParts then
        if previewUnit and not active[previewUnit] then
            clearTint(previewUnit, previewParts)
            if previewParts.blizzard then ns.SyncRoom(previewParts.uf, nil) end
        end
        previewParts, previewUnit = nil, nil
    end
end

function ns.ShowPreview()
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    local unit = plate and plateUnit(plate)
    if not plate or (unit and active[unit]) then
        -- No target, or the target already shows its real threat element.
        clearPreview()
        if preview then preview:Hide() end
        return plate ~= nil
    end
    local parts = getParts(plate)
    if previewParts and previewParts.uf ~= parts.uf then clearPreview() end
    preview = preview or ns.CreateElement()
    previewParts, previewUnit = parts, unit
    ns.Arrange(preview, parts)
    local color = ns.ColorForPercent(ns.previewPercent, ns.GetRole(), ns.previewOffTank)
    ns.PaintElement(preview, color, ns.previewPercent .. "%", ns.previewPercent, true)
    if TrisThreatDB.colorBar and parts.blizzard and unit then
        tints[unit] = color
        applyTint(parts.bar, color)
    elseif unit then
        clearTint(unit, parts)
    end
    return true
end

function ns.HidePreview()
    clearPreview()
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
            "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TARGET_CHANGED" }) do
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
        if arg1 == previewUnit then clearPreview(); if preview then preview:Hide() end end
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        if type(arg1) == "string" and not issecretvalue(arg1) and arg1:find("^nameplate") then
            ns.UpdateUnit(arg1)
        else
            dirty = true
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Target border on the badge, and the test element follows the target while the options are open.
        dirty = true
        if ns.previewWanted and ns.previewWanted() then
            C_Timer.After(0, ns.ShowPreview) -- the new target's plate exists one frame later
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
