local addonName, ns = ...
ns.name = addonName

local issecretvalue = issecretvalue or function() return false end

-- Everything that is pure logic (defaults, role, colors, filters) lives here so the Fengari harness can test it.

ns.OFFSET_LIMIT = 100

ns.defaults = {
    enabled = true,
    role = "auto",       -- auto | tank | damage | healer
    value = "scaled",    -- scaled | raw | lead
    offsetX = 0,
    offsetY = 0,
    scale = 1,
    mode = "badge",      -- floating | badge | segment | strip
    side = "right",      -- left | right | top | bottom (segment: left/right, strip: top/bottom)
    makeRoom = true,     -- move Blizzard elements aside for the integrated modes
    colorText = true,    -- threat color on the number
    colorBackground = false, -- threat color on the badge/segment background (the strip fill is always colored)
    stripText = true,    -- strip mode shows the number at its right end
    glow = true,         -- pulsing red halo: tank lost aggro, or anybody else pulled it
    colorBar = false,    -- also tint the nameplate health bar
    onlyInstances = false,
    hideTrivial = true,
    offTank = true,
    minimap = { hide = false },
}

local VALUE_MODES = { scaled = true, raw = true, lead = true }
local ROLE_CHOICES = { auto = true, tank = true, damage = true, healer = true }
local DISPLAY_MODES = { floating = true, badge = true, segment = true, strip = true }
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
    db.value = VALUE_MODES[db.value] and db.value or d.value
    db.offsetX = ns.ClampOffset(db.offsetX)
    db.offsetY = ns.ClampOffset(db.offsetY)
    db.scale = clamp(db.scale, 0.5, 2, 1)
    db.mode = DISPLAY_MODES[db.mode] and db.mode or d.mode
    db.side = SIDES[db.side] and db.side or d.side
    for _, key in ipairs({ "makeRoom", "colorText", "colorBackground", "stripText", "glow", "colorBar", "hideTrivial", "offTank" }) do
        if db[key] == nil then db[key] = d[key] end
        db[key] = db[key] == true
    end
    db.onlyInstances = db.onlyInstances == true
    db.minimap = type(db.minimap) == "table" and db.minimap or {}
    db.minimap.hide = db.minimap.hide == true
    return db
end

----------------------------------------------------------------------------------------------------
-- Role
----------------------------------------------------------------------------------------------------

-- api = { tankAura(), groupRole(), specRole() } each returning a value or nil (any may be secret or missing).
-- Order: effective tank (stance, form, aura) -> assigned group role -> spec role -> damage.
-- The offhand shield is deliberately not a signal: Holy Paladins and Restoration Shamans carry one too.
function ns.ResolveRole(api)
    local function read(fn)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn)
        if not ok or value == nil or issecretvalue(value) then return nil end
        return value
    end
    if read(api.tankAura) == true then return "tank" end
    local group = read(api.groupRole)
    if group == "TANK" then return "tank" end
    if group == "HEALER" then return "healer" end
    if group == "DAMAGER" then return "damage" end
    local spec = read(api.specRole)
    if spec == "TANK" then return "tank" end
    if spec == "HEALER" then return "healer" end
    return "damage"
end

function ns.DetectRole()
    return ns.ResolveRole({
        tankAura = function()
            if UnitHasEffectivelyTankAura then return UnitHasEffectivelyTankAura("player") end
            if PlayerUtil and PlayerUtil.IsPlayerEffectivelyTank then return PlayerUtil.IsPlayerEffectivelyTank() end
        end,
        groupRole = function() return UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") end,
        specRole = function()
            local getSpec = GetSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
            if getSpec and GetSpecializationRole then return GetSpecializationRole(getSpec()) end
        end,
    })
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

-- Effective side per mode: segments sit in the bar's left/right end, strips above/below it.
function ns.EffectiveSide(mode, side)
    if mode == "segment" then return side == "right" and "right" or "left" end
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
    local room = { nameY = 0, leftX = 0, rightX = 0, healthTextX = 0 }
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
        end
        return spec
    end

    if mode == "segment" then
        spec.look = "segment"
        spec.h = barH
        spec.w = math.floor(barH * 2 + 0.5)
        if side == "right" then
            spec.points = { { "RIGHT", "bar", "RIGHT", 0, 0 } }
            room.healthTextX = -spec.w
        else
            spec.points = { { "LEFT", "bar", "LEFT", 0, 0 } }
        end
        return spec
    end

    -- strip
    spec.look = "strip"
    spec.w = barW
    spec.h = math.max(4, math.floor(barH * 0.35 + 0.5))
    if side == "bottom" then
        spec.points = { { "TOPLEFT", "bar", "BOTTOMLEFT", 0, -7 }, { "TOPRIGHT", "bar", "BOTTOMRIGHT", 0, -7 } }
    else
        spec.points = { { "BOTTOMLEFT", "bar", "TOPLEFT", 0, 5 }, { "BOTTOMRIGHT", "bar", "TOPRIGHT", 0, 5 } }
        room.nameY = spec.h + 5
    end
    return spec
end
