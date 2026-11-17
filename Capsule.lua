local addonName, ns = ...
local issecretvalue = issecretvalue or function() return false end

local active = {}   -- unit token -> element
local pool = {}
local tints = {}    -- unit token -> color while the Blizzard health bar is tinted by threat
local safeGlows, safePool = {}, {}
local safeSince = {} -- unit token -> GetTime() since it became a safe pick
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
        local makeRoom = db.makeRoom and mode ~= "floating"
        ns.SyncRoom(parts.uf, makeRoom and spec.room or nil)
        -- Other addons' icons (quest markers ...) under a badge or strip move outward as well.
        if parts.blizzard and makeRoom and (mode == "badge" or mode == "strip") then
            ns.PushForeign(el, parts, ns.EffectiveSide(mode, db.side))
        else
            ns.ReleaseForeign(el)
        end
    end
    return spec
end

----------------------------------------------------------------------------------------------------
-- Health bar tint (Blizzard plates only, option "Color the health bar")
----------------------------------------------------------------------------------------------------

local function applyTint(bar, color)
    local texture = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if texture and texture.SetVertexColor then
        pcall(texture.SetVertexColor, texture, color[1], color[2], color[3], 1)
    end
end

if CompactUnitFrame_UpdateHealthColor then
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        local unit = frame and frame.unit
        if unit and not issecretvalue(unit) and frame.healthBar then
            if tints[unit] then applyTint(frame.healthBar, tints[unit]) end
        end
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
    local safe = el.safeGlow
    if safe then
        safeGlows[unit] = nil
        ns.DetachBroadGlow(safe)
        safePool[#safePool + 1] = safe
        el.safeGlow = nil
    end
    ns.ReleaseForeign(el)
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

local curves = {}   -- "dps" | "tank" | "lead" -> color curve (false = unavailable)

-- dps: scaled 0 green -> 100 red. tank: mirrored. lead: a tank's lead over the next player,
-- 100 % (about to lose it) red -> 200 % (twice the next player's threat) green.
local function buildCurve(kind)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return false end
    local ok, curve = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not curve then return false end
    pcall(function()
        if curve.SetType and Enum and Enum.LuaCurveType then curve:SetType(Enum.LuaCurveType.Linear) end
        local offset = kind == "lead" and 100 or 0
        for _, stop in ipairs(ns.GRADIENT_STOPS) do
            local c = ns.GradientColor(stop[1], kind ~= "dps")
            curve:AddPoint(stop[1] + offset, CreateColor(c[1], c[2], c[3], 1))
        end
        -- Beyond the last stop (raw percentages and leads can exceed it) keep the end color.
        local last = ns.GradientColor(100, kind ~= "dps")
        curve:AddPoint(10000, CreateColor(last[1], last[2], last[3], 1))
    end)
    return curve
end

-- Returns { r, g, b } (the numbers may be secret values) or nil when the curve cannot be evaluated.
local function curveColor(key, value)
    if value == nil then return nil end
    if key ~= "lead" then key = key == "tank" and "tank" or "dps" end
    if curves[key] == nil then curves[key] = buildCurve(key) end
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

local function holds(tankUnit, unit)
    if not UnitExists(tankUnit) then return false end
    local status = UnitThreatSituation(tankUnit, unit)
    return status ~= nil and not issecretvalue(status) and status == 3
end

-- A readable number from a threat API, or nil (missing, error, secret).
local function readNumber(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and type(value) == "number" and not issecretvalue(value) then return value end
    return nil
end

-- Your raw threat in % of the holder's (4th return of UnitDetailedThreatSituation), nil when secret.
local function rawShare(unit)
    if type(UnitDetailedThreatSituation) ~= "function" then return nil end
    local ok, _, _, _, raw = pcall(UnitDetailedThreatSituation, "player", unit)
    if ok and type(raw) == "number" and not issecretvalue(raw) then return raw end
    return nil
end

local function isMainTank(holder)
    if holder == "pet" or type(GetPartyAssignment) ~= "function" then return false end
    local ok, assigned = pcall(GetPartyAssignment, "MAINTANK", holder)
    return ok and not issecretvalue(assigned) and assigned == true
end

-- Only a holder's current target is a useful recommendation; prefer the assigned main tank when several hold it.
local function targetedBy(holder, unit)
    local same = UnitIsUnit(holder .. "target", unit)
    return same ~= nil and not issecretvalue(same) and same == true
end

-- Is anybody besides the player (group members, their pets, your pet) on the mob's threat list?
local function onList(other, unit)
    if not UnitExists(other) then return false end
    local status = UnitThreatSituation(other, unit)
    if status == nil then return false end
    return true -- a secret status still means "on the list"
end

function ns.OthersOnThreatList(unit)
    if onList("pet", unit) then return true end
    local prefix, count
    if IsInRaid and IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup and IsInGroup() then prefix, count = "party", GetNumSubgroupMembers()
    else return false end
    for index = 1, count do
        local member = prefix .. index
        local same = UnitIsUnit(member, "player")
        if same == nil or issecretvalue(same) or not same then
            if onList(member, unit) or onList(prefix .. "pet" .. index, unit) then return true end
        end
    end
    return false
end

-- Prefer a group tank; without an assigned tank, allow another group member or your pet to qualify.
local function holderOf(unit)
    local pet = holds("pet", unit) and "pet" or nil
    local prefix, count
    if IsInRaid and IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup and IsInGroup() then prefix, count = "party", GetNumSubgroupMembers()
    else return pet end
    local override = TrisThreatDB and TrisThreatDB.safeTankGUID
    if override then
        for index = 1, count do
            local member = prefix .. index
            local same = UnitIsUnit(member, "player")
            if same ~= nil and not issecretvalue(same) and not same
                and UnitGUID(member) == override then
                return holds(member, unit) and member or nil
            end
        end
        return nil
    end
    local firstTank, firstMember, hasTankRole
    for index = 1, count do
        local member = prefix .. index
        local same = UnitIsUnit(member, "player")
        if same ~= nil and not issecretvalue(same) and not same then
            local role = UnitGroupRolesAssigned(member)
            local tankAura = false
            if type(UnitHasEffectivelyTankAura) == "function" then
                local ok, value = pcall(UnitHasEffectivelyTankAura, member)
                tankAura = ok and value == true and not issecretvalue(value)
            end
            if role == "TANK" or tankAura then
                hasTankRole = true
                if holds(member, unit) then
                    if isMainTank(member) then return member end
                    firstTank = firstTank or member
                end
            elseif not issecretvalue(role) and holds(member, unit) then
                firstMember = firstMember or member
            end
        end
    end
    return firstTank or (hasTankRole and pet) or firstMember or pet
end

local function otherHolds(unit) return holderOf(unit) ~= nil end

function ns.SafeTankGUIDPresent(guid)
    local prefix, count
    if IsInRaid and IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup and IsInGroup() then prefix, count = "party", GetNumSubgroupMembers()
    else return false end
    for index = 1, count do
        local unit = prefix .. index
        local same = UnitIsUnit(unit, "player")
        if same ~= nil and not issecretvalue(same) and not same and UnitGUID(unit) == guid then return true end
    end
    return false
end

function ns.GetSafeTankUnit()
    local db = TrisThreatDB
    if db and db.safeTankGUID then
        local prefix, count
        if IsInRaid and IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
        elseif IsInGroup and IsInGroup() then prefix, count = "party", GetNumSubgroupMembers()
        else return nil end
        for index = 1, count do
            local unit = prefix .. index
            local same = UnitIsUnit(unit, "player")
            if same ~= nil and not issecretvalue(same) and not same and UnitGUID(unit) == db.safeTankGUID then
                return unit, "manual"
            end
        end
        return nil
    end
    local prefix, count
    if IsInRaid and IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup and IsInGroup() then prefix, count = "party", GetNumSubgroupMembers()
    else return nil end
    local best, bestRank
    for index = 1, count do
        local unit = prefix .. index
        local same = UnitIsUnit(unit, "player")
        if same ~= nil and not issecretvalue(same) and not same then
            local rank
            local assigned = type(GetPartyAssignment) == "function" and GetPartyAssignment("MAINTANK", unit)
            if assigned == true and not issecretvalue(assigned) then rank = 0
            elseif UnitGroupRolesAssigned(unit) == "TANK" then rank = 1
            elseif type(UnitHasEffectivelyTankAura) == "function" then
                local ok, aura = pcall(UnitHasEffectivelyTankAura, unit)
                if ok and aura == true and not issecretvalue(aura) then rank = 2 end
            end
            if rank and (not bestRank or rank < bestRank) then best, bestRank = unit, rank end
        end
    end
    if best then return best, "automatic" end
    local targetHolder = UnitExists("target") and holderOf("target")
    return targetHolder, targetHolder and "threat" or nil
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
        or not ns.ShouldShow(db, safeClassification(unit), IsInInstance and IsInInstance() or false,
            IsInGroup and IsInGroup() or false) then
        release(unit); return
    end
    local status = readStatus(unit)
    if status == nil then release(unit); return end

    local role = ns.GetRole()
    local offTank = status ~= false and role == "tank" and status < 3 and otherHolds(unit)
    local color = ns.COLORS[ns.StatusColorKey(status, role, offTank)] or ns.COLORS.unknown
    local _, _, scaled = UnitDetailedThreatSituation("player", unit)
    -- Strip fill: value on [low, high]. Secret numbers are fine, the engine computes the fill.
    local fill, low, high = scaled, 0, 100
    local text = formatPercent(scaled) -- 0..100, 100 % = the aggro changes hands
    local holding = role == "tank" and status ~= false and status >= 2
    if offTank then
        color = ns.COLORS.offtank
    elseif holding and UnitThreatPercentageOfLead then
        -- Tanking: full and green with a big lead, shrinking and turning red as the next player closes in.
        local lead = UnitThreatPercentageOfLead("player", unit)
        -- Alone on the threat list there is no next player: a readable 0 means "all yours", so full and green.
        if lead ~= nil and not issecretvalue(lead) and lead <= 0 then lead = 200 end
        -- Nobody else on the threat list (solo, or the group has not touched it yet): the lead is then a secret 0
        -- (no next player), which would show an empty bar. The threat status of the others is readable, so
        -- check it: if none of them is on the list, it is all yours, full and green.
        local alone = not ns.OthersOnThreatList(unit)
        if alone then
            fill, low, high = 1, 0, 1
            color = ns.COLORS.good
        elseif lead ~= nil then
            fill, low, high = lead, 100, 200
            text = formatPercent(lead) -- holding it as a tank: how far you lead the next player
            color = curveColor("lead", lead) or color
        end
    elseif role == "tank" then
        color = ns.COLORS.bad -- a tank that lost the enemy: red, the fill shows how close it is to taking it back
    elseif scaled ~= nil then
        color = curveColor(role, scaled) or color
    end

    local el = active[unit]
    if not el then el = acquire(); active[unit] = el end
    local parts = getParts(plate)
    if el.parts and el.parts.uf ~= parts.uf and el.parts.blizzard then ns.SyncRoom(el.parts.uf, nil) end
    el.parts = parts
    ns.Arrange(el, parts)
    ns.PaintElement(el, color, text, fill, isTargetPlate(plate), low, high)

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

----------------------------------------------------------------------------------------------------
-- Safe target: a green halo on every enemy a tank (or pet) targets and leads clearly while your threat is low
----------------------------------------------------------------------------------------------------

-- Safe-target halos are pooled separately from the threat meter.
ns.safeGlows = safeGlows

local function setSafe(unit, plate, on)
    local g = safeGlows[unit]
    if not on then
        if g and not g.removing then
            g.removing = true
            ns.FadeBroadGlow(g, g:GetAlpha(), 0, 0.1, function()
                if safeGlows[unit] ~= g or not g.removing then return end
                safeGlows[unit] = nil
                if active[unit] and active[unit].safeGlow == g then active[unit].safeGlow = nil end
                ns.DetachBroadGlow(g)
                safePool[#safePool + 1] = g
            end)
        end
        return
    end
    local needsFade = not g or g.removing
    if not g then
        g = table.remove(safePool) or ns.CreateBroadGlow(TrisThreatDB.safeGlowColor or ns.GLOW_GREEN)
        g:SetAlpha(0)
        safeGlows[unit] = g
    end
    g.removing = false
    g.color = TrisThreatDB.safeGlowColor or ns.GLOW_GREEN
    if active[unit] then active[unit].safeGlow = g end
    ns.PlaceBroadGlow(g, getParts(plate), active[unit])
    g:Show()
    if needsFade then ns.FadeBroadGlow(g, g:GetAlpha(), 1, 0.15) end
end

-- Settings "Test" button: shows the safe halo on the current target for a moment, whatever its real threat.
local testUnit
function ns.TestSafeGlow()
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    local unit = plate and plateUnit(plate)
    if not unit then return false end
    testUnit = unit
    ns.RefreshSafe()
    C_Timer.After(1.6, function() testUnit = nil; ns.RefreshSafe() end)
    return true
end

local function safeInfo(unit, status, holder)
    return {
        status = status,
        share = status ~= nil and rawShare(unit) or nil,
        lead = readNumber(UnitThreatPercentageOfLead, holder, unit),
        leadCategory = readNumber(UnitThreatLeadSituation, holder, unit),
        targeted = targetedBy(holder, unit),
    }
end

-- "/tt safe": what the safe-glow decision sees for every nameplate (run it in combat).
function ns.SafeReport()
    local function show(value)
        if value == nil then return "-" end
        if issecretvalue(value) then return "secret" end
        return tostring(value)
    end
    local rows, lines = 0, {}
    local function out(text) lines[#lines + 1] = text; print(text) end
    out("|cffe0ad3dTrisThreat|r safe: role " .. tostring(ns.GetRole()) .. ", glow " .. tostring(TrisThreatDB.safeGlow)
        .. ", group " .. tostring(IsInGroup and IsInGroup()) .. ", instance " .. tostring(IsInInstance and IsInInstance())
        .. ", combat " .. tostring(InCombatLockdown and InCombatLockdown()))
    TrisThreatDB.safeReport = lines -- saved on /reload, so it can be read without a chat screenshot
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plateUnit(plate)
        if unit then
            rows = rows + 1
            local status = readStatus(unit)
            local holder = ns.IsSafeStatus(status) and holderOf(unit)
            local text
            if holder then
                local info = safeInfo(unit, status, holder)
                local exists = UnitExists(holder .. "target")
                local raw = UnitIsUnit(holder .. "target", unit)
                text = "holder " .. holder .. ", holder target exists " .. show(exists) .. ", same raw " .. show(raw)
                    .. " (" .. type(raw) .. "), targeted " .. show(info.targeted) .. ", lead " .. show(info.lead)
                    .. ", leadCat " .. show(info.leadCategory) .. ", share " .. show(info.share)
                    .. " -> " .. (ns.IsSafeTarget(info) and "SAFE" or "no")
            else
                text = "no holder (own status " .. (status == false and "secret" or show(status)) .. ")"
            end
            out("  " .. rows .. ". status " .. (status == false and "secret" or show(status)) .. ": " .. text)
        end
    end
    if rows == 0 then out("  no nameplates") end
end

function ns.RefreshSafe()
    local db = TrisThreatDB
    local plates, candidates = {}, {}
    if db and db.enabled and db.safeGlow and ns.GetRole() ~= "tank" then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local unit = plateUnit(plate)
            if unit then
                plates[unit] = plate
                local attackable = UnitCanAttack("player", unit)
                if issecretvalue(attackable) then attackable = true end
                local dead = UnitIsDead(unit)
                if issecretvalue(dead) then dead = false end
                if attackable and not dead
                    and ns.ShouldShow(db, safeClassification(unit), IsInInstance and IsInInstance() or false,
                        IsInGroup and IsInGroup() or false) then
                    local status = readStatus(unit)
                    local holder = ns.IsSafeStatus(status) and holderOf(unit)
                    if holder then
                        local safe, leadScore = ns.IsSafeTarget(safeInfo(unit, status, holder))
                        if safe then candidates[unit] = { holder = holder, leadScore = leadScore } end
                    end
                end
            end
        end
    end
    local picks, now = ns.PickSafe(candidates), GetTime()
    -- A new pick must hold for 0.3 s before it glows (no flicker); losing it is immediate.
    for unit in pairs(safeSince) do
        if not picks[unit] then safeSince[unit] = nil end
    end
    for unit in pairs(picks) do safeSince[unit] = safeSince[unit] or now end
    for unit, plate in pairs(plates) do
        local on = unit == testUnit or (safeSince[unit] ~= nil and now - safeSince[unit] >= 0.3)
        setSafe(unit, plate, on)
    end
    for unit in pairs(safeGlows) do
        if not plates[unit] then setSafe(unit, nil, false) end
    end
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
    ns.RefreshSafe()
    if preview and preview:IsShown() then ns.ShowPreview() end
    if ns.UpdateModeDisplay then ns.UpdateModeDisplay() end
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
        if preview then ns.ReleaseForeign(preview) end
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
    preview.parts = parts
    ns.Arrange(preview, parts)
    local color = ns.ColorForPercent(ns.previewPercent, ns.GetRole(), ns.previewOffTank)
    ns.PaintElement(preview, color, ns.previewPercent .. "%", ns.previewPercent, true, 0, 100)
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
local safeDirty, safeTick = false, 0
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
            elapsed, safeTick = elapsed + delta, safeTick + delta
            if dirty and elapsed >= 0.1 then
                dirty, safeDirty, elapsed, safeTick = false, false, 0, 0
                ns.RefreshAll()
            elseif safeTick >= 0.5 or (safeDirty and safeTick >= 0.1) then
                -- Who a tank targets changes without a threat event: re-check twice a second.
                safeDirty, safeTick = false, 0
                ns.RefreshSafe()
            end
        end)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        ns.UpdateUnit(arg1)
        safeDirty = true
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        release(arg1)
        safeDirty = true
        if arg1 == previewUnit then clearPreview(); if preview then preview:Hide() end end
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        if type(arg1) == "string" and not issecretvalue(arg1) and arg1:find("^nameplate") then
            ns.UpdateUnit(arg1)
            safeDirty = true
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
        if event == "GROUP_ROSTER_UPDATE" and TrisThreatDB.safeTankGUID
            and not ns.SafeTankGUIDPresent(TrisThreatDB.safeTankGUID) then
            TrisThreatDB.safeTankGUID = nil
        end
        lastRole = ns.GetRole()
        dirty = true
    end
end)
