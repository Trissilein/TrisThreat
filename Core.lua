local addonName, ns = ...
ns.name = addonName

local issecretvalue = issecretvalue or function() return false end

-- Everything that is pure logic (defaults, role, colors, filters) lives here so the Fengari harness can test it.

ns.OFFSET_LIMIT = 400 -- the settings preview is ~630 wide: the element can be dragged across all of it

ns.defaults = {
    enabled = true,
    role = "auto",       -- auto | tank | damage | healer
    offsetX = 0,
    offsetY = 0,
    scale = 1,
    mode = "badge",      -- floating | badge | strip; set by dropping the element in the settings preview
    side = "right",      -- left | right | top | bottom (strip: top/bottom)
    makeRoom = true,     -- move Blizzard elements aside for the integrated modes
    colorText = true,    -- threat color on the number
    colorBackground = false, -- threat color on the badge background (the strip fill is always colored)
    stripText = true,    -- strip mode shows the number at its right end
    glow = true,         -- pulsing red halo: tank lost aggro, or anybody else pulled it
    colorBar = false,    -- also tint the nameplate health bar
    onlyInstances = false,
    hideTrivial = true,
    minimap = { hide = false },
}

local ROLE_CHOICES = { auto = true, tank = true, damage = true, healer = true }
local DISPLAY_MODES = { floating = true, badge = true, strip = true }
local SIDES = { left = true, right = true, top = true, bottom = true }

local function clamp(value, low, high, fallback)
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    return math.max(low, math.min(high, value))
end

function ns.ClampOffset(value)
    return math.floor(clamp(value, -ns.OFFSET_LIMIT, ns.OFFSET_LIMIT, 0) + 0.5)
end

-- Fills missing keys and repairs out-of-range values. Idempotent.
function ns.NormalizeDB(db)
    db = type(db) == "table" and db or {}
    local d = ns.defaults
    db.enabled = db.enabled ~= false
    db.role = ROLE_CHOICES[db.role] and db.role or d.role
    db.offsetX = ns.ClampOffset(db.offsetX)
    db.offsetY = ns.ClampOffset(db.offsetY)
    db.scale = clamp(db.scale, 0.5, 2, 1)
    if db.mode == "segment" then db.mode = "badge" end -- the segment mode was dropped: the badge can sit there freely
    db.mode = DISPLAY_MODES[db.mode] and db.mode or d.mode
    db.side = SIDES[db.side] and db.side or d.side
    for _, key in ipairs({ "makeRoom", "colorText", "colorBackground", "stripText", "glow", "colorBar", "hideTrivial" }) do
        if db[key] == nil then db[key] = d[key] end
        db[key] = db[key] == true
    end
    db.onlyInstances = db.onlyInstances == true
    db.value, db.offTank = nil, nil -- retired settings: the number is chosen automatically, off-tank color is always on
    db.minimap = type(db.minimap) == "table" and db.minimap or {}
    db.minimap.hide = db.minimap.hide == true
    return db
end

----------------------------------------------------------------------------------------------------
-- Role
----------------------------------------------------------------------------------------------------

-- Role resolution as explicit rules, first match wins. Returns role and the reason (shown in the tooltip and
-- the options window, so a review screenshot says why a mode was chosen).
-- api = { groupRole(), tankAura(), shieldTank(), otherTank(), specRole() }; each may be missing, error or be
-- secret, which counts as "unknown".
--   1. Group role TANK or HEALER (a deliberate choice) wins.
--   2. Tank form, stance or aura (Bear Form; on Forever not used for Warriors/Paladins, see shieldTank).
--   3. Shield (Forever, Warrior/Paladin): a Paladin with clearly more Holy than Protection talents heals;
--      otherwise tank, unless another tank is in the group, then damage dealer.
--      The DAMAGER group role does not override this: a party without a role check gives everybody DAMAGER.
--   4. Group role DAMAGER, then specialization role (Retail), else damage dealer.
ns.ROLE_REASONS = {
    groupTank = "group role", groupHealer = "group role", aura = "tank form or stance",
    shield = "shield, no other tank", shieldOtherTank = "shield, another tank in the group",
    shieldHoly = "shield, mostly Holy talents",
    groupDamage = "group role", specTank = "specialization", specHealer = "specialization", default = "no tank signal",
}

function ns.ResolveRole(api)
    local function read(fn)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn)
        if not ok or value == nil or issecretvalue(value) then return nil end
        return value
    end
    local group = read(api.groupRole)
    if group == "TANK" then return "tank", "groupTank" end
    if group == "HEALER" then return "healer", "groupHealer" end
    if read(api.tankAura) == true then return "tank", "aura" end
    if read(api.shieldTank) == true then
        if read(api.talentLean) == "healer" then return "healer", "shieldHoly" end
        if read(api.otherTank) == true then return "damage", "shieldOtherTank" end
        return "tank", "shield"
    end
    if group == "DAMAGER" then return "damage", "groupDamage" end
    local spec = read(api.specRole)
    if spec == "TANK" then return "tank", "specTank" end
    if spec == "HEALER" then return "healer", "specHealer" end
    return "damage", "default"
end

-- Another group member who tanks: assigned TANK role, or a readable tank form/stance/aura.
local function otherTankInGroup()
    local prefix, count
    if IsInRaid and IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup and IsInGroup() then prefix, count = "party", GetNumSubgroupMembers()
    else return false end
    for index = 1, count do
        local member = prefix .. index
        local same = UnitIsUnit(member, "player")
        if same ~= nil and not issecretvalue(same) and not same and UnitExists(member) then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(member)
            if role == "TANK" then return true end
            local _, class = UnitClass(member)
            local shieldClass = not GetSpecialization and (class == "WARRIOR" or class == "PALADIN")
            -- Bear Form and the like count; on Forever a Warrior's or Paladin's aura does not (their shield
            -- decides, and other players' gear is not readable without inspecting them).
            if UnitHasEffectivelyTankAura and not shieldClass then
                local ok, tank = pcall(UnitHasEffectivelyTankAura, member)
                if ok and tank == true then return true end
            end
        end
    end
    return false
end
ns.OtherTankInGroup = otherTankInGroup

-- Points spent in one talent tab across client versions (Classic: name, icon, pointsSpent, fileName;
-- later: id, name, description, icon, pointsSpent, ...). nil when the client has no tabbed talents.
local function tabPoints(tab)
    if not GetTalentTabInfo then return nil end
    local ok, a, b, c, d, e = pcall(GetTalentTabInfo, tab)
    if not ok then return nil end
    if type(c) == "number" and type(a) == "string" then return c end
    if type(e) == "number" then return e end
    return nil
end

-- "healer" when a Paladin has clearly more points in Holy than in Protection (5 or more), else nil.
-- Early levels spread points evenly, so a small difference decides nothing.
function ns.TalentLean(class, holy, protection)
    if class ~= "PALADIN" or type(holy) ~= "number" or type(protection) ~= "number" then return nil end
    if holy >= protection + 5 then return "healer" end
    return nil
end

function ns.DetectRole()
    return ns.ResolveRole({
        tankAura = function()
            -- Forever, Warrior and Paladin: the shield decides (Righteous Fury or a stance on a two-hander is not a
            -- tank). Bear Form and other classes' tank auras still count.
            if not GetSpecialization then
                local _, class = UnitClass("player")
                if class == "WARRIOR" or class == "PALADIN" then return nil end
            end
            if UnitHasEffectivelyTankAura then return UnitHasEffectivelyTankAura("player") end
            if PlayerUtil and PlayerUtil.IsPlayerEffectivelyTank then return PlayerUtil.IsPlayerEffectivelyTank() end
        end,
        groupRole = function() return UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") end,
        otherTank = otherTankInGroup,
        talentLean = function()
            local _, class = UnitClass("player")
            return ns.TalentLean(class, tabPoints(1), tabPoints(2))
        end,
        -- Forever has no real specializations: a Warrior or Paladin with a shield is a tank unless the group
        -- role says otherwise. Shamans carry shields in every role, so they are left out. Retail uses the spec.
        shieldTank = function()
            if GetSpecialization then return nil end
            local _, class = UnitClass("player")
            if class ~= "WARRIOR" and class ~= "PALADIN" then return false end
            local itemID = GetInventoryItemID and GetInventoryItemID("player", 17)
            if not itemID then return false end
            local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
            if not getInfo then return false end
            local _, _, _, _, _, classID, subclassID = getInfo(itemID)
            return classID == 4 and subclassID == 6 -- Armor / Shield, independent of the client language
        end,
        specRole = function()
            local getSpec = GetSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
            if getSpec and GetSpecializationRole then return GetSpecializationRole(getSpec()) end
        end,
    })
end

-- "Tank mode" / "DPS mode" / "Healer mode", plus whether it was detected or set by hand.
ns.MODE_TEXT = { tank = "Tank mode", damage = "DPS mode", healer = "Healer mode" }
function ns.RoleModeText()
    local role = ns.GetRole()
    local manual = TrisThreatDB and TrisThreatDB.role ~= "auto"
    local reason
    if manual then reason = "set by hand" else
        local _, key = ns.DetectRole()
        reason = ns.ROLE_REASONS[key] or key
    end
    return ns.MODE_TEXT[role] or role, manual, role, reason
end

function ns.GetRole()
    local choice = TrisThreatDB and TrisThreatDB.role or "auto"
    if choice ~= "auto" then return choice end
    return ns.DetectRole()
end

----------------------------------------------------------------------------------------------------
-- Colors
----------------------------------------------------------------------------------------------------

ns.COLORS = {
    good = { 0.2, 0.85, 0.3 },
    warn = { 1, 0.6, 0.1 },
    bad = { 0.9, 0.15, 0.15 },
    offtank = { 0.25, 0.55, 1 },
    unknown = { 0.6, 0.6, 0.6 },
}

-- Continuous grading: green at 0 %, yellow at 50 %, red at 100 %. A tank sees it mirrored (100 % = holding = green).
ns.GRADIENT_STOPS = {
    { 0, { 0.18, 0.85, 0.30 } },
    { 50, { 0.97, 0.82, 0.16 } },
    { 100, { 0.90, 0.15, 0.15 } },
}

-- Plain-number version (options preview, tests, fallback). The in-game path evaluates the same stops on a color
-- curve so secret percentages work too.
function ns.GradientColor(percent, tank)
    local value = tonumber(percent) or 0
    value = math.max(0, math.min(100, value))
    if tank then value = 100 - value end
    local stops = ns.GRADIENT_STOPS
    for i = 2, #stops do
        local a, b = stops[i - 1], stops[i]
        if value <= b[1] then
            local t = (value - a[1]) / (b[1] - a[1])
            return {
                a[2][1] + (b[2][1] - a[2][1]) * t,
                a[2][2] + (b[2][2] - a[2][2]) * t,
                a[2][3] + (b[2][3] - a[2][3]) * t,
            }
        end
    end
    return stops[#stops][2]
end

-- A tank's lead over the next player: 100 % red (about to lose it), 200 % or more green.
function ns.LeadColor(lead)
    return ns.GradientColor((tonumber(lead) or 100) - 100, true)
end

-- Preview: warn at the bad end of the slider (tank near 0 %, everybody else near 100 %).
function ns.PreviewWarn()
    if ns.previewOffTank then return false end
    local tank = ns.GetRole() == "tank"
    local percent = ns.previewPercent or 0
    return (tank and percent <= 10) or (not tank and percent >= 90)
end

-- Color for a readable percentage; a co-tank or pet holding the mob wins (tank only).
function ns.ColorForPercent(percent, role, offTank)
    if offTank and role == "tank" then return ns.COLORS.offtank end
    return ns.GradientColor(percent, role == "tank")
end

-- status: UnitThreatSituation 0..3, nil = not on the threat list (hidden), false = unreadable (secret).
-- Returns the color key or nil when nothing should be shown.
function ns.StatusColorKey(status, role, offTank)
    if status == nil then return nil end
    if status == false then return "unknown" end
    local tank = role == "tank"
    if tank then
        if status >= 3 then return "good" end
        if status == 2 then return "warn" end
        return offTank and "offtank" or "bad"
    end
    if status >= 2 then return "bad" end
    if status == 1 then return "warn" end
    return "good"
end

----------------------------------------------------------------------------------------------------
-- Filters
----------------------------------------------------------------------------------------------------

-- classification: UnitClassification token or nil; inInstance: boolean.
function ns.ShouldShow(db, classification, inInstance)
    if not db.enabled then return false end
    if db.onlyInstances and not inInstance then return false end
    if db.hideTrivial and (classification == "trivial" or classification == "minus") then return false end
    return true
end

----------------------------------------------------------------------------------------------------
-- Layout: where the threat element sits and how much room the Blizzard elements must give up
----------------------------------------------------------------------------------------------------

-- Measurements follow Blizzard's Forever nameplate (Blizzard_NamePlates, Camelot level badge): the badge is
-- 5 px beside the bar, 3 px above and 2 px below it; the bar frame's shadow reaches 6 px below the bar.
ns.BADGE_GAP = 5
ns.BADGE_WIDTH_FACTOR = 50 / 25   -- a level badge is 28 wide for "22"; ours holds "100%"

-- Effective side per mode: strips sit above/below the bar.
function ns.EffectiveSide(mode, side)
    if mode == "strip" then return side == "bottom" and "bottom" or "top" end
    return side
end

-- m = { barW, barH, levelShown, levelRight, levelW, levelH }; db for floating offsets/scale.
-- Returns spec = { look, w, h, points = { { point, rel ("bar"|"level"), relPoint, x, y }, ... },
--                  scale, room = { nameY, leftX, rightX, healthTextX } }.
function ns.Layout(mode, side, m, db)
    local barW, barH = m.barW or 190, m.barH or 20
    local badgeH = (m.levelShown and m.levelH) or (barH + 5)
    local badgeW = math.floor(badgeH * ns.BADGE_WIDTH_FACTOR + 0.5)
    local room = { nameY = 0, leftX = 0, rightX = 0, healthTextX = 0, barY = 0 }
    local spec = { look = "badge", w = badgeW, h = badgeH, scale = 1, room = room }
    side = ns.EffectiveSide(mode, side)

    if mode == "floating" then
        local scale = db and db.scale or 1
        spec.scale = scale
        spec.points = { { "BOTTOMLEFT", "bar", "TOPLEFT", ((db and db.offsetX) or 0) / scale, (((db and db.offsetY) or 0) + 3) / scale } }
        return spec
    end

    if mode == "badge" then
        local gap = ns.BADGE_GAP
        if side == "right" then
            if m.levelShown and m.levelRight then
                spec.points = { { "LEFT", "level", "RIGHT", gap, 0 } }
            else
                spec.points = { { "LEFT", "bar", "RIGHT", gap, 0.5 } }
            end
            room.rightX = badgeW + gap
        elseif side == "left" then
            spec.points = { { "RIGHT", "bar", "LEFT", -gap, 0.5 } }
            room.leftX = -(badgeW + gap)
        elseif side == "top" then
            spec.points = { { "BOTTOMLEFT", "bar", "TOPLEFT", 0, 4 } }
            room.nameY = badgeH + 2
        else
            spec.points = { { "TOPLEFT", "bar", "BOTTOMLEFT", 0, -7 } }
            -- The cast bar sits right under the health bar: lift the health bar so the badge fits between.
            room.barY = badgeH + 7
        end
        return spec
    end

    -- strip
    spec.look = "strip"
    spec.w = barW
    spec.h = math.max(4, math.floor(barH * 0.35 + 0.5))
    if side == "bottom" then
        spec.points = { { "TOPLEFT", "bar", "BOTTOMLEFT", 0, -7 }, { "TOPRIGHT", "bar", "BOTTOMRIGHT", 0, -7 } }
        -- Lift the health bar (name and auras follow it) so the cast bar below never covers the strip.
        room.barY = spec.h + 7
    else
        spec.points = { { "BOTTOMLEFT", "bar", "TOPLEFT", 0, 5 }, { "BOTTOMRIGHT", "bar", "TOPRIGHT", 0, 5 } }
        room.nameY = spec.h + 5
    end
    return spec
end

----------------------------------------------------------------------------------------------------
-- Settings preview: snap spots and free placement. Coordinates are panel-local (origin bottom-left),
-- computed from the mock's fixed geometry (Options.lua layoutMock), so they never move while dragging.
----------------------------------------------------------------------------------------------------

ns.MOCK_W, ns.MOCK_H = 628, 150
ns.MOCK_ZONES = {
    { mode = "badge", side = "right", text = "Badge right" }, { mode = "badge", side = "left", text = "Badge left" },
    { mode = "badge", side = "top", text = "Badge above" }, { mode = "badge", side = "bottom", text = "Badge below" },
    { mode = "strip", side = "top", text = "Strip above" }, { mode = "strip", side = "bottom", text = "Strip below" },
} -- dropping the badge on a strip spot turns it into the strip; there is no mode switch
local MOCK_MEASURE = { barW = 190, barH = 20, levelShown = true, levelRight = true, levelW = 28, levelH = 25 }

local function mockRects()
    local barL = ns.MOCK_W / 2 - 16 - 95
    local barB = ns.MOCK_H / 2 - 8 - 10
    local bar = { l = barL, b = barB, r = barL + 190, t = barB + 20 }
    local level = { l = bar.r + 5, b = bar.b - 2, r = bar.r + 5 + 28, t = bar.t + 3 }
    return bar, level
end

local function rectPoint(r, point)
    local x = point:find("LEFT") and r.l or point:find("RIGHT") and r.r or (r.l + r.r) / 2
    local y = point:find("BOTTOM") and r.b or point:find("TOP") and r.t or (r.b + r.t) / 2
    return x, y
end

-- left, bottom, right, top of the spot where ns.Layout would put the element.
function ns.MockZoneRect(mode, side)
    local bar, level = mockRects()
    local rects = { bar = bar, level = level }
    local spec = ns.Layout(mode, side, MOCK_MEASURE, nil)
    local p = spec.points[1]
    local ax, ay = rectPoint(rects[p[2]], p[3])
    ax, ay = ax + p[4], ay + p[5]
    local w = spec.w
    if spec.points[2] then
        local q = spec.points[2]
        local bx = rectPoint(rects[q[2]], q[3])
        w = bx + q[4] - ax
    end
    local l = p[1]:find("LEFT") and ax or p[1]:find("RIGHT") and ax - w or ax - w / 2
    local b = p[1]:find("BOTTOM") and ay or p[1]:find("TOP") and ay - spec.h or ay - spec.h / 2
    return l, b, l + w, b + spec.h
end

-- Each snap spot is a dot at the center of its rect. Index of the dot closest to (x, y) within 22 px, or nil.
function ns.PickMockZone(x, y, rects)
    local best, bestDist
    for i, r in ipairs(rects) do
        local dx, dy = (r[1] + r[3]) / 2 - x, (r[2] + r[4]) / 2 - y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist <= 22 and (not best or dist < bestDist) then best, bestDist = i, dist end
    end
    return best
end

-- Free position: offsets that put the element's center under (x, y), kept inside the preview.
function ns.MockFreeOffsets(x, y, scale)
    local bar = mockRects()
    scale = scale or 1
    local spec = ns.Layout("floating", "right", MOCK_MEASURE, { offsetX = 0, offsetY = 0, scale = scale })
    local w, h = spec.w * scale, spec.h * scale
    x = math.max(w / 2, math.min(ns.MOCK_W - w / 2, x))
    y = math.max(h / 2, math.min(ns.MOCK_H - h / 2, y))
    return ns.ClampOffset(x - w / 2 - bar.l), ns.ClampOffset(y - h / 2 - bar.t - 3)
end
