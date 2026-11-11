local addonName, ns = ...
local L = ns.L
local issecretvalue = issecretvalue or function() return false end

local TEXTURE_FILL = "Interface\\AddOns\\TrisThreat\\Assets\\Tab_Fill.tga"
local TEXTURE_BORDER = "Interface\\AddOns\\TrisThreat\\Assets\\Tab_Border.tga"
local WIDTH, HEIGHT = 60, 22

-- The capsule is a tab that grows out of the health bar: flat bottom edge on the bar's top-left corner,
-- rounded top corners, same fill color as the bar. The user's offsets are added on top.
local BASE_X, BASE_Y = 0, -1

local tints = {}    -- unit token -> { r, g, b } while the nameplate bar is colored by threat
local active = {}   -- unit token -> capsule
local pool = {}
local preview       -- capsule shown by the options window

----------------------------------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------------------------------

function ns.CreateCapsule()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")

    f.fill = f:CreateTexture(nil, "BACKGROUND")
    f.fill:SetAllPoints()
    f.fill:SetTexture(TEXTURE_FILL)

    -- A soft top-to-bottom sheen gives the flat color the same depth as a nameplate bar.
    f.sheen = f:CreateTexture(nil, "BORDER")
    f.sheen:SetAllPoints()
    f.sheen:SetTexture(TEXTURE_FILL)
    if f.sheen.SetGradient and CreateColor then
        f.sheen:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.28), CreateColor(1, 1, 1, 0.22))
    end

    f.border = f:CreateTexture(nil, "ARTWORK")
    f.border:SetAllPoints()
    f.border:SetTexture(TEXTURE_BORDER)
    f.border:SetVertexColor(0, 0, 0, 0.95)

    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.text:SetTextColor(1, 1, 1, 1)
    return f
end

----------------------------------------------------------------------------------------------------
-- Nameplate bar: find it, anchor to it, tint it (Platynator and Blizzard nameplates)
----------------------------------------------------------------------------------------------------

-- Returns the bar frame to anchor to, the owner used for tinting and the kind ("platynator" | "blizzard" | nil).
local function findBar(plate)
    for _, child in ipairs({ plate:GetChildren() }) do
        local widgets = child.widgets
        if type(widgets) == "table" then
            for _, widget in ipairs(widgets) do
                if type(widget) == "table" and widget.statusBar and widget.UpdateHealth then
                    return widget.statusBar, widget, "platynator"
                end
            end
        end
    end
    local unitFrame = plate.UnitFrame
    if unitFrame and unitFrame.healthBar then return unitFrame.healthBar, unitFrame, "blizzard" end
    return plate, nil, nil
end

local function applyTint(kind, owner, color)
    if not (owner and color) then return end
    pcall(function()
        if kind == "platynator" then
            owner.statusBar:GetStatusBarTexture():SetVertexColor(color[1], color[2], color[3])
            if owner.statusBarCutaway and owner.details and owner.details.animate then
                owner.statusBarCutaway:GetStatusBarTexture():SetVertexColor(color[1], color[2], color[3])
            end
        elseif kind == "blizzard" then
            owner.healthBar:SetStatusBarColor(color[1], color[2], color[3])
        end
    end)
end

-- The color the nameplate bar currently shows (nil when it cannot be read).
local function readBarColor(kind, owner)
    if not owner then return nil end
    local ok, r, g, b = pcall(function()
        if kind == "platynator" then return owner.statusBar:GetStatusBarTexture():GetVertexColor() end
        if kind == "blizzard" then return owner.healthBar:GetStatusBarColor() end
    end)
    if ok and type(r) == "number" and type(g) == "number" and type(b) == "number"
        and not issecretvalue(r) and not issecretvalue(g) and not issecretvalue(b) then
        return { r, g, b }
    end
    return nil
end

-- Give the nameplate its own color logic back.
local function restoreTint(kind, owner)
    pcall(function()
        if kind == "platynator" and owner.ColorEventHandler then
            owner:ColorEventHandler("")
        elseif kind == "blizzard" and CompactUnitFrame_UpdateHealthColor then
            CompactUnitFrame_UpdateHealthColor(owner)
        end
    end)
end

local function followBar(unit, kind, owner)
    local f = active[unit]
    if not f or TrisThreatDB.colorBar then return end
    local c = readBarColor(kind, owner)
    if c then ns.PaintCapsule(f, c, nil) end
end

-- Both plate addons repaint their bar on their own events; a post-hook puts our color back on top, or (when we
-- do not tint) lets the capsule follow the bar's color.
local function hookOwner(kind, owner)
    if kind ~= "platynator" or owner.trisThreatHooked then return end
    owner.trisThreatHooked = true
    hooksecurefunc(owner, "SetColor", function(self)
        local unit = self.unit
        if not unit or issecretvalue(unit) then return end
        if tints[unit] then applyTint("platynator", self, tints[unit]) else followBar(unit, "platynator", self) end
    end)
end

if CompactUnitFrame_UpdateHealthColor then
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        local unit = frame and frame.unit
        if not unit or issecretvalue(unit) then return end
        if tints[unit] then applyTint("blizzard", frame, tints[unit]) else followBar(unit, "blizzard", frame) end
    end)
end

local function acquire()
    return table.remove(pool) or ns.CreateCapsule()
end

local function release(unit)
    local f = active[unit]
    if not f then return end
    active[unit] = nil
    tints[unit] = nil
    if f.tintOwner then restoreTint(f.tintKind, f.tintOwner) end
    f.tintOwner, f.tintKind = nil, nil
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(UIParent)
    pool[#pool + 1] = f
end

-- Anchors a capsule to a bar frame. Also used by the options window's mock nameplate.
function ns.AnchorCapsule(f, bar, parent)
    local db = TrisThreatDB
    local scale = db.scale
    f:SetParent(parent or bar)
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", (BASE_X + db.offsetX) / scale, (BASE_Y + db.offsetY) / scale)
end

local function layout(f, plate)
    local bar, owner, kind = findBar(plate)
    ns.AnchorCapsule(f, bar, plate)
    f:SetFrameStrata("HIGH")
    f.tintOwner, f.tintKind = owner, kind
    if owner then hookOwner(kind, owner) end
end

-- color = { r, g, b }; textValue nil keeps the current text (used when only the color changes).
function ns.PaintCapsule(f, color, textValue)
    local c = color or ns.COLORS.unknown
    f.fill:SetVertexColor(c[1], c[2], c[3], 1)
    if textValue ~= nil then f.text:SetText(textValue) end
    f:Show()
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
    local color = ns.COLORS[colorKey] or ns.COLORS.unknown   -- fallback when no percentage can be graded
    local _, _, scaled = UnitDetailedThreatSituation("player", unit)
    if offTank then
        color = ns.COLORS.offtank
    elseif scaled ~= nil then
        color = curveColor(role, scaled) or color
    end
    local text = readValue(unit, db.value, status)

    local f = active[unit]
    if not f then f = acquire(); active[unit] = f end
    layout(f, plate)
    if db.colorBar and f.tintOwner then
        tints[unit] = color
        applyTint(f.tintKind, f.tintOwner, color)
    else
        if tints[unit] then
            tints[unit] = nil
            restoreTint(f.tintKind, f.tintOwner)
        end
        -- Not tinting: the capsule takes whatever color the nameplate bar shows.
        color = readBarColor(f.tintKind, f.tintOwner) or color
    end
    ns.PaintCapsule(f, color, text)
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
    if preview and preview:IsShown() then ns.ShowPreview() end
end

-- Test mode: a capsule on the current target, shown while the options window is open (no combat needed).
ns.previewPercent = 70
ns.previewOffTank = false
local previewTint

local function clearPreviewTint()
    if previewTint then
        tints[previewTint.unit] = nil
        restoreTint(previewTint.kind, previewTint.owner)
        previewTint = nil
    end
end

function ns.ShowPreview()
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if not plate then ns.HidePreview(); return false end
    preview = preview or ns.CreateCapsule()
    layout(preview, plate)
    clearPreviewTint()
    local unit = plateUnit(plate)
    local color = ns.ColorForPercent(ns.previewPercent, ns.GetRole(), ns.previewOffTank)
    if not TrisThreatDB.colorBar then
        color = readBarColor(preview.tintKind, preview.tintOwner) or color
    end
    ns.PaintCapsule(preview, color, ns.previewPercent .. "%")
    if TrisThreatDB.colorBar and preview.tintOwner and unit and not active[unit] then
        tints[unit] = color
        previewTint = { unit = unit, kind = preview.tintKind, owner = preview.tintOwner }
        applyTint(preview.tintKind, preview.tintOwner, color)
    end
    return true
end

function ns.HidePreview()
    clearPreviewTint()
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
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        if type(arg1) == "string" and not issecretvalue(arg1) and arg1:find("^nameplate") then
            ns.UpdateUnit(arg1)
        else
            dirty = true
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
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
