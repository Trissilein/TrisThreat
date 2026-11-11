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
    colorBar = true,     -- also tint the nameplate bar
    onlyInstances = false,
    hideTrivial = true,
    offTank = true,
    minimap = { hide = false },
}

local VALUE_MODES = { scaled = true, raw = true, lead = true }
local ROLE_CHOICES = { auto = true, tank = true, damage = true, healer = true }

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
    for _, key in ipairs({ "colorBar", "hideTrivial", "offTank" }) do
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
