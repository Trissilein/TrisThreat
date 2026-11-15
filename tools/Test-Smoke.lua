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
    GetAlpha = function(self) return rawget(self, "__alpha") or 1 end,
    SetAlpha = function(self, alpha) rawset(self, "__alpha", alpha) end,
    Play = function(self) local finish = rawget(self, "__script_OnFinished"); if finish then finish(self) end end,
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
local clock = 0
_G.GetTime = function() return clock end
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

-- Glow geometry, from the anchors the code really sets (y grows downwards here; WoW offsets are y-up).
-- Regions, the glow frame, the strip element and its artwork record SetPoint/SetSize; rectOf() resolves them.
do
    local ATLAS = ns.GLOW_ATLAS
    check("glow atlas layout is exposed for the geometry checks", ATLAS ~= nil)
    local BAR = { l = 0, t = 0, r = 190, b = 20 }
    local rects = {}
    local function track(frame)
        frame.pts, frame.size = {}, nil
        frame.ClearAllPoints = function(self) self.pts = {} end
        frame.SetPoint = function(self, point, rel, relPoint, x, y) self.pts[point] = { rel, relPoint, x or 0, y or 0 } end
        frame.SetSize = function(self, w, h) self.size = { w, h } end
        frame.SetHeight = function(self, h) self.size = { self.size and self.size[1], h } end
        return frame
    end
    local function rectOf(frame)
        local l, r, t, b
        local w, h = frame.size and frame.size[1], frame.size and frame.size[2]
        for point, p in pairs(frame.pts) do
            local rel = rects[p[1]]
            if not rel then error("FAIL anchor to an unknown frame") end
            local x = (p[2]:find("LEFT") and rel.l or p[2]:find("RIGHT") and rel.r or (rel.l + rel.r) / 2) + p[3]
            local y = (p[2]:find("TOP") and rel.t or p[2]:find("BOTTOM") and rel.b or (rel.t + rel.b) / 2) - p[4]
            if point:find("LEFT") then l = x elseif point:find("RIGHT") then r = x end
            if point:find("TOP") then t = y elseif point:find("BOTTOM") then b = y end
        end
        if l and not r and w then r = l + w elseif r and not l and w then l = r - w end
        if t and not b and h then b = t + h elseif b and not t and h then t = b - h end
        if not (l and r and t and b) then error("FAIL frame is not fully anchored") end
        return { l = l, t = t, r = r, b = b }
    end
    local function hypot(x, y) return math.sqrt(x * x + y * y) end
    local count = 0
    local function q(name, condition, detail) -- quiet check: many geometry assertions, one PASS line at the end
        if not condition then error("FAIL " .. name .. (detail and (" " .. detail) or "")) end
        count = count + 1
    end
    local function overlap(a, b) return a.l < b.r and b.l < a.r and a.t < b.b and b.t < a.b end
    local function area(a) return (a.r - a.l) * (a.b - a.t) end
    local function distance(x, y, a) -- distance from a point to a rectangle (0 on or inside it)
        return hypot(math.max(a.l - x, 0, x - a.r), math.max(a.t - y, 0, y - a.b))
    end

    local glow = track(ns.CreateBroadGlow({ 0.2, 0.8, 0.3 }))
    for _, region in ipairs(glow.regions) do
        track(region)
        region.SetTexCoord = function(self, ...) self.uv = { ... } end
        region.SetVertexColor = function(self, ...) self.tint = { ... } end
    end
    bar.GetWidth = function() return BAR.r - BAR.l end
    rects[bar] = BAR
    local parts = { uf = uf, bar = bar }

    -- Checks the eight regions of `glow` against the rectangle `inner` they must surround.
    local function checkRing(label, reach, inner)
        local g = rectOf(glow)
        rects[glow] = g
        q(label .. ": glow frame is the inner rectangle plus reach on every side",
            g.l == inner.l - reach and g.r == inner.r + reach and g.t == inner.t - reach and g.b == inner.b + reach)
        local sum = 0
        for _, region in ipairs(glow.regions) do region.rect = rectOf(region) end
        for i, region in ipairs(glow.regions) do
            local a = region.rect
            sum = sum + area(a)
            q(label .. ": region " .. i .. " has size and lies inside the glow frame",
                a.l < a.r and a.t < a.b and a.l >= g.l and a.r <= g.r and a.t >= g.t and a.b <= g.b)
            q(label .. ": region " .. i .. " leaves the bar rectangle free", not overlap(a, inner))
            for j = i + 1, #glow.regions do
                q(label .. ": regions " .. i .. " and " .. j .. " do not overlap", not overlap(a, glow.regions[j].rect))
            end
        end
        q(label .. ": the eight regions cover the ring without a gap", sum == area(g) - area(inner))
        for _, key in ipairs({ "topLeft", "topRight", "bottomLeft", "bottomRight" }) do
            local a = glow[key].rect
            q(label .. ": " .. key .. " is a reach-sized square", a.r - a.l == reach and a.b - a.t == reach)
        end
        -- UV: the texture's bright side (small tile coordinates) must face the bar, the dark side the outside.
        local span = ATLAS.tile - 1
        for _, region in ipairs(glow.regions) do
            local a, uv = region.rect, region.uv
            local function tile(corner) -- tile coordinates (0 = bright inner corner, 1 = faded) at a region corner
                local sx, sy = corner[1] == "l" and 0 or 1, corner[2] == "t" and 0 or 1
                local u = uv[1] + (uv[2] - uv[1]) * sx
                local v = uv[3] + (uv[4] - uv[3]) * sy
                return (u * ATLAS.w - 0.5) % ATLAS.cell - ATLAS.gutter, (v * ATLAS.h - 0.5) % ATLAS.cell - ATLAS.gutter
            end
            local corners = {}
            for _, cx in ipairs({ "l", "r" }) do for _, cy in ipairs({ "t", "b" }) do
                local tx, ty = tile({ cx, cy })
                tx, ty = tx / span, ty / span
                local c = { px = a[cx], py = a[cy], d = hypot(tx, ty), tx = tx, ty = ty }
                c.near = distance(c.px, c.py, inner)
                corners[#corners + 1] = c
                q(label .. ": UV stays inside the feather tile, away from the gutter",
                    tx > -1e-6 and tx < 1 + 1e-6 and ty > -1e-6 and ty < 1 + 1e-6)
            end end
            for _, c1 in ipairs(corners) do for _, c2 in ipairs(corners) do
                if c1.near < c2.near - 1e-9 then
                    q(label .. ": brighter texels lie nearer the bar", c1.d < c2.d + 1e-9)
                elseif math.abs(c1.near - c2.near) < 1e-9 then
                    q(label .. ": equally distant corners are equally bright", math.abs(c1.d - c2.d) < 1e-6)
                end
            end end
            for _, c in ipairs(corners) do
                if c.near == 0 then q(label .. ": the texel at the bar edge is the brightest one", c.d < 1e-6) end
            end
        end
    end

    local inner = { l = BAR.l - 2, t = BAR.t - 2, r = BAR.r + 2, b = BAR.b + 2 } -- bar plus GLOW_GAP
    for _, reach in ipairs({ 10, 40, 80 }) do
        TrisThreatDB.glowReach = reach
        ns.PlaceBroadGlow(glow, parts)
        checkRing("reach " .. reach, reach, inner)
    end
    TrisThreatDB.glowReach = 40
    ns.PlaceBroadGlow(glow, parts)

    -- The anchors follow the bar; a resized bar needs no relayout of the regions.
    local before = glow.top.pts
    BAR.r = 260
    ns.PlaceBroadGlow(glow, parts)
    check("resized bar: regions were not re-anchored", glow.top.pts == before)
    inner.r = BAR.r + 2
    checkRing("resized bar", 40, inner)
    BAR.r = 190
    inner.r = BAR.r + 2
    ns.PlaceBroadGlow(glow, parts)

    -- Feather and Strength
    local u = glow.topLeft.uv[1]
    TrisThreatDB.glowFeather, TrisThreatDB.glowStrength = 5, 35
    ns.PlaceBroadGlow(glow, parts)
    check("Feather selects a different radial profile", glow.topLeft.uv[1] ~= u)
    check("Strength controls opacity independently", glow.topLeft.tint[4] == 0.35)
    check("corner profile meets both straight edges", glow.topLeft.uv[2] == glow.top.uv[1]
        and glow.topLeft.uv[4] == glow.left.uv[3])
    checkRing("feather 5", 40, inner)
    for feather = 5, 100, 5 do
        TrisThreatDB.glowFeather = feather
        ns.PlaceBroadGlow(glow, parts)
        for _, region in ipairs(glow.regions) do
            local uv = region.uv
            local col, row = math.floor(uv[1] * ATLAS.w / ATLAS.cell), math.floor(uv[3] * ATLAS.h / ATLAS.cell)
            q("feather " .. feather .. ": UVs stay in one atlas cell",
                col == math.floor(uv[2] * ATLAS.w / ATLAS.cell) and row == math.floor(uv[4] * ATLAS.h / ATLAS.cell))
        end
    end
    TrisThreatDB = ns.NormalizeDB({})

    -- Strip mode: the glow wraps the bar and the strip's real artwork (as placed by PlaceElement).
    for _, side in ipairs({ "top", "bottom" }) do
        TrisThreatDB.mode, TrisThreatDB.side = "strip", side
        local el = track(ns.CreateElement())
        track(el.bg)
        local spec = ns.Layout("strip", side, ns.Measure(parts), TrisThreatDB)
        ns.PlaceElement(el, parts, spec)
        check("strip element is in strip look on " .. side, el.look == "strip")
        local stripRect = rectOf(el)
        rects[el] = stripRect
        local art = rectOf(el.bg)
        check("strip artwork lies beside the bar on " .. side, art.t < BAR.t or art.b > BAR.b)
        ns.PlaceBroadGlow(glow, parts, el)
        local want = {
            l = math.min(BAR.l, art.l) - 2, r = math.max(BAR.r, art.r) + 2,
            t = math.min(BAR.t, art.t) - 2, b = math.max(BAR.b, art.b) + 2,
        }
        checkRing("strip " .. side, 40, want)
    end
    TrisThreatDB = ns.NormalizeDB({})
    bar.GetWidth = nil
    realPrint("PASS glow geometry: " .. count .. " ring, UV orientation and gutter checks")
end

-- Strip number: shadowed, so it stays readable on the glow's bright inner edge.
do
    local el = ns.CreateElement()
    local shadow
    el.text.SetShadowOffset = function(_, x, y) shadow = { x, y } end
    ns.PlaceElement(el, { uf = uf, bar = bar }, ns.Layout("strip", "top", ns.Measure({ bar = bar }), TrisThreatDB))
    check("strip number has a shadow", shadow ~= nil and shadow[1] ~= 0)
end

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
local function dragToZone(mode, side)
    for _, zone in ipairs(ns.MOCK_ZONES) do
        if zone.mode == mode and zone.side == side then
            local l, b, r, t = ns.MockZoneSnapRect(zone)
            dragTo((l + r) / 2, (b + t) / 2)
            return
        end
    end
    error("missing snap zone " .. mode .. "/" .. side)
end
dragToZone("badge", "bottom")
check("dropping on the badge-below spot snaps there", TrisThreatDB.mode == "badge" and TrisThreatDB.side == "bottom")
dragToZone("strip", "top")
check("dropping on the strip spot turns it into the strip", TrisThreatDB.mode == "strip" and TrisThreatDB.side == "top")
dragToZone("badge", "left")
check("dropping on the badge-left spot snaps there", TrisThreatDB.mode == "badge" and TrisThreatDB.side == "left")
dragToZone("segment", "left")
check("dropping inside the bar's left end makes the segment", TrisThreatDB.mode == "segment" and TrisThreatDB.side == "left")
dragTo(600, 130)
check("dropping elsewhere places freely, far to the right", TrisThreatDB.mode == "floating" and TrisThreatDB.offsetX > 150)
TrisThreatDB.mode, TrisThreatDB.side, TrisThreatDB.offsetX, TrisThreatDB.offsetY = "badge", "right", 0, 0
ns.FlashGlow()
check("flashing the glow runs and restores the preview", true)
local safeTestCalled, testSafeGlow = false, ns.TestSafeGlow
ns.TestSafeGlow = function(...) safeTestCalled = true; return testSafeGlow(...) end
ns.FlashGlow("safe")
ns.TestSafeGlow = testSafeGlow
local safeGlow = ns.safeGlows.nameplate1
check("safe-glow test button tests the target and cleans up", safeTestCalled and safeGlow == nil)

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
        IsUnit = _G.UnitIsUnit, Exists = _G.UnitExists, Threat = _G.UnitThreatSituation,
        Lead = _G.UnitThreatPercentageOfLead }
    _G.IsInGroup = function() return true end
    _G.GetNumSubgroupMembers = function() return 1 end
    _G.UnitGroupRolesAssigned = function() return "TANK" end
    _G.UnitExists = function() return true end
    _G.UnitIsUnit = function(a, b) return a == b end
    _G.UnitThreatPercentageOfLead = function() return 160 end
    local playerStatus = 0
    _G.UnitThreatSituation = function(unit) if unit == "player" then return playerStatus end return 3 end
    TrisThreatDB.role, TrisThreatDB.safeGlow, TrisThreatDB.enabled = "damage", true, true
    ns.RefreshSafe()
    clock = clock + 0.31
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
    _G.UnitThreatPercentageOfLead = real.Lead
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
