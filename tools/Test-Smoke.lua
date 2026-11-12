-- Smoke test: runs the UI and nameplate code against a permissive WoW API stub, for every mode and side.
local realPrint = print
local function check(name, condition, detail)
    if not condition then error("FAIL " .. name .. (detail and (" " .. detail) or "")) end
    realPrint("PASS " .. name)
end

local calls = {}
local Stub
local returns = {
    GetFrameLevel = function() return 1 end,
    GetWidth = function() return 190 end,
    GetHeight = function() return 20 end,
    GetFrameStrata = function() return "DIALOG" end,
    IsShown = function() return true end,
    IsVisible = function() return true end,
    GetChecked = function() return true end,
    GetPoint = function(self) return "TOPLEFT", Stub(), "TOPRIGHT", 5, 3 end,
    GetAtlas = function() return "atlas" end,
    GetText = function() return "" end,
    GetStatusBarTexture = function() return Stub() end,
    CreateTexture = function() return Stub() end,
    CreateMaskTexture = function() return Stub() end,
    CreateFontString = function() return Stub() end,
    GetName = function() return nil end,
    GetStringWidth = function() return 80 end,
    CreateAnimationGroup = function() return Stub() end,
    CreateAnimation = function() return Stub() end,
    IsPlaying = function() return false end,
    GetEffectiveScale = function() return 1 end,
}
-- Unknown keys return a callable stub: works both as a method (obj:Foo()) and as a child region (obj.Low:SetText()).
function Stub(name)
    local obj = {}
    return setmetatable(obj, {
        __index = function(t, key)
            if returns[key] then return returns[key] end
            -- WoW methods and template regions are capitalized; lowercase keys are plain fields (nil when unset).
            if type(key) ~= "string" or not key:match("^%u") then return nil end
            local child = Stub(key)
            rawset(t, key, child)
            return child
        end,
        __call = function(self, owner, ...)
            calls[name or "?"] = (calls[name or "?"] or 0) + 1
            if name == "SetScript" and type(owner) == "table" then rawset(owner, "__script_" .. tostring(select(1, ...)), select(2, ...)) end
        end,
    })
end

_G.CreateFrame = function() return Stub() end
_G.UIParent = Stub()
_G.UISpecialFrames = {}
_G.STANDARD_TEXT_FONT = "font"
_G.GetLocale = function() return "enUS" end
_G.hooksecurefunc = function() end
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, GetRGB = function(c) return c.r, c.g, c.b end } end
_G.C_CurveUtil = { CreateColorCurve = function()
    local points = {}
    return { SetType = function() end, AddPoint = function(_, x, c) points[#points + 1] = { x, c } end,
        Evaluate = function(_, x) local best = points[1][2]; for _, p in ipairs(points) do if x >= p[1] then best = p[2] end end; return best end }
end }
_G.Enum = { LuaCurveType = { Linear = 1 } }
_G.C_Texture = { GetAtlasInfo = function() return {} end }
_G.C_Timer = { After = function(_, fn) fn() end }
_G.C_StringUtil = { RoundToNearestString = function(v) return tostring(math.floor(v + 0.5)) end }
_G.UIDropDownMenu_SetWidth = function() end
_G.UIDropDownMenu_Initialize = function(_, fn) fn() end
_G.UIDropDownMenu_CreateInfo = function() return {} end
_G.UIDropDownMenu_AddButton = function() end
_G.UIDropDownMenu_SetText = function() end
_G.SlashCmdList = {}
_G.InCombatLockdown = function() return false end
_G.UnitHasEffectivelyTankAura = function() return false end
_G.UnitGroupRolesAssigned = function() return "NONE" end
_G.UnitThreatSituation = function() return 1 end
_G.UnitDetailedThreatSituation = function() return false, 1, 55, 60, 1000 end
_G.UnitThreatPercentageOfLead = function() return 130 end
_G.UnitCanAttack = function() return true end
_G.UnitIsDead = function() return false end
_G.UnitClassification = function() return "elite" end
_G.UnitExists = function() return false end
_G.IsInInstance = function() return false end
_G.IsInRaid = function() return false end
_G.IsInGroup = function() return false end
_G.print = function() end

local uf = Stub()
local bar = Stub()
bar.LeftText = Stub()
uf.HealthBarsContainer = { healthBar = bar }
uf.PlayerLevelDiffFrame = Stub()
uf.name = Stub()
uf.RaidTargetFrame = Stub()
uf.AurasFrame = { CrowdControlListFrame = Stub(), LossOfControlFrame = Stub() }
uf.UpdateAnchors = function() end
local plate = Stub()
plate.UnitFrame = uf
plate.namePlateUnitToken = "nameplate1"
_G.C_NamePlate = { GetNamePlateForUnit = function() return plate end, GetNamePlates = function() return { plate } end }

for _, chunk in ipairs(MODULES) do chunk("TrisThreat", ns) end
TrisThreatDB = ns.NormalizeDB({})

ns.ToggleOptions()
check("options window builds and opens", calls.Show ~= nil)

local AdjustBefore = calls.AdjustPointsOffset or 0
for _, mode in ipairs({ "badge", "segment", "strip", "floating" }) do
    for _, side in ipairs({ "left", "right", "top", "bottom" }) do
        TrisThreatDB.mode, TrisThreatDB.side = mode, side
        ns.RefreshOptions()
        ns.UpdateUnit("nameplate1")
        ns.ShowPreview()
    end
end
check("every mode and side updates a nameplate and the mock", true)
check("make room moved Blizzard elements", (calls.AdjustPointsOffset or 0) > AdjustBefore)

-- dragging the preview element: snap spots pick mode and side, anywhere else is free placement
local mock = ns.mock
local function dragTo(x, y)
    _G.GetCursorPosition = function() return x, y end
    mock.element.__script_OnDragStart()
    mock.dragger.__script_OnUpdate()
    mock.element.__script_OnDragStop()
end
local l, b, r, t = ns.MockZoneRect({ mode = "badge", side = "bottom" })
dragTo((l + r) / 2, (b + t) / 2)
check("dropping on the badge-below spot snaps there", TrisThreatDB.mode == "badge" and TrisThreatDB.side == "bottom")
l, b, r, t = ns.MockZoneRect({ mode = "strip", side = "top" })
dragTo((l + r) / 2, (b + t) / 2)
check("dropping on the strip spot turns it into the strip", TrisThreatDB.mode == "strip" and TrisThreatDB.side == "top")
l, b, r, t = ns.MockZoneRect({ mode = "badge", side = "left" })
dragTo((l + r) / 2, (b + t) / 2)
check("dropping on the badge-left spot snaps there", TrisThreatDB.mode == "badge" and TrisThreatDB.side == "left")
l, b, r, t = ns.MockZoneRect(ns.MOCK_ZONES[7])
dragTo((l + r) / 2, (b + t) / 2)
check("dropping inside the bar's left end makes the segment", TrisThreatDB.mode == "segment" and TrisThreatDB.side == "left")
dragTo(600, 130)
check("dropping elsewhere places freely, far to the right", TrisThreatDB.mode == "floating" and TrisThreatDB.offsetX > 150)
TrisThreatDB.mode, TrisThreatDB.side, TrisThreatDB.offsetX, TrisThreatDB.offsetY = "badge", "right", 0, 0
ns.FlashGlow()
check("flashing the glow runs and restores the preview", true)
ns.FlashGlow("safe")
check("flashing the safe glow runs, tests the target and cleans up", ns.safeGlows.nameplate1 == nil and ns.warnTest == nil)
ns.TestWarn()
check("the aggro Test button forces and clears the warning", ns.warnTest == nil)

-- room bookkeeping: switching back to floating leaves nothing applied
TrisThreatDB.mode = "badge"; TrisThreatDB.side = "left"
ns.UpdateUnit("nameplate1")
check("badge left applies room", uf.trisThreatRoom ~= nil and uf.trisThreatRoom.leftX < 0)
TrisThreatDB.mode = "floating"
ns.UpdateUnit("nameplate1")
check("floating gives the room back", uf.trisThreatRoom == nil)
TrisThreatDB.makeRoom = false; TrisThreatDB.mode = "strip"
ns.UpdateUnit("nameplate1")
check("make room off applies nothing", uf.trisThreatRoom == nil)

-- not on the threat list: element released and room restored
TrisThreatDB.makeRoom = true; TrisThreatDB.mode = "badge"; TrisThreatDB.side = "top"
ns.UpdateUnit("nameplate1")
_G.UnitThreatSituation = function() return nil end
ns.UpdateUnit("nameplate1")
check("leaving the threat list restores the layout", uf.trisThreatRoom == nil)

-- Tank holding the enemy: strip fill runs on the lead (100..200)
TrisThreatDB.role = "tank"; TrisThreatDB.mode = "strip"
_G.UnitThreatSituation = function() return 3 end
ns.UpdateUnit("nameplate1")
check("tank strip updates with the lead", true)
TrisThreatDB.role = "auto"

-- Safe target: a TANK party member holds the mob, the player is not on its list -> green halo; off when it is.
do
    local real = { IsInGroup = _G.IsInGroup, GetNum = _G.GetNumSubgroupMembers, Roles = _G.UnitGroupRolesAssigned,
        IsUnit = _G.UnitIsUnit, Exists = _G.UnitExists, Threat = _G.UnitThreatSituation }
    _G.IsInGroup = function() return true end
    _G.GetNumSubgroupMembers = function() return 1 end
    _G.UnitGroupRolesAssigned = function() return "TANK" end
    _G.UnitExists = function() return true end
    _G.UnitIsUnit = function(a, b) return a == b end
    local playerStatus = 0
    _G.UnitThreatSituation = function(unit) if unit == "player" then return playerStatus end return 3 end
    TrisThreatDB.role, TrisThreatDB.safeGlow, TrisThreatDB.enabled = "damage", true, true
    ns.RefreshSafe()
    check("tank holds it, you are not on it: safe glow on", ns.safeGlows.nameplate1 ~= nil)
    playerStatus = 2
    ns.RefreshSafe()
    check("you pulled it: safe glow off", ns.safeGlows.nameplate1 == nil)
    playerStatus = 0
    TrisThreatDB.role = "tank"
    ns.RefreshSafe()
    check("tanks get no safe glow", ns.safeGlows.nameplate1 == nil)
    TrisThreatDB.role, TrisThreatDB.safeGlow = "damage", false
    ns.RefreshSafe()
    check("option off: no safe glow", ns.safeGlows.nameplate1 == nil)
    TrisThreatDB.safeGlow = true
    _G.IsInGroup, _G.GetNumSubgroupMembers, _G.UnitGroupRolesAssigned = real.IsInGroup, real.GetNum, real.Roles
    _G.UnitIsUnit, _G.UnitExists, _G.UnitThreatSituation = real.IsUnit, real.Exists, real.Threat
    TrisThreatDB.role = "auto"
end

-- Foreign icon (Questie style): pushed out of a left badge and kept there when its addon re-anchors it.
do
    local realHook = _G.hooksecurefunc
    _G.hooksecurefunc = function(obj, name, post)
        local orig = obj[name]
        obj[name] = function(...) local r = orig(...); post(...); return r end
    end
    local function plainFrame(left, bottom, w, h)
        local f = { x = 0, y = 0 }
        function f:GetRect() return left + self.x, bottom + self.y, w, h end
        function f:GetEffectiveScale() return 1 end
        function f:IsVisible() return true end
        function f:SetPoint(_, x, y) self.x, self.y = x or 0, y or 0 end
        function f:AdjustPointsOffset(dx, dy) self.x, self.y = self.x + dx, self.y + dy end
        return f
    end
    local icon = plainFrame(95, 4, 16, 16)          -- overlaps the badge's left part
    local holder = Stub()
    holder.GetChildren = function() return icon end
    holder.GetParent = function() return nil end
    local el = plainFrame(100, 0, 50, 25)
    ns.PushForeign(el, { uf = holder }, "left")
    check("overlapping icon is pushed left of the badge", icon.x == -(95 + 16 - (100 - 2)))
    local pushed = icon.x
    icon:SetPoint("LEFT", 0, 0)                     -- its addon re-anchors it
    check("the push survives the other addon's SetPoint", icon.x == pushed)
    ns.ReleaseForeign(el)
    check("release gives the icon its own position back", icon.x == 0)
    _G.hooksecurefunc = realHook
end
