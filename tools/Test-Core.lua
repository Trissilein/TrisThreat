local function check(name, condition, detail)
    if not condition then error("FAIL " .. name .. (detail and (" " .. detail) or "")) end
    print("PASS " .. name)
end

-- Normalize: defaults, repair, clamp, idempotent
local db = ns.NormalizeDB(nil)
check("empty db gets defaults", db.enabled and db.role == "auto" and db.value == "scaled" and db.offsetX == 0
    and db.scale == 1 and db.minimap.hide == false and db.colorBar == false)
local bad = ns.NormalizeDB({ role = "x", value = "y", offsetX = 500, offsetY = -500, scale = 9, hideTrivial = false,
    minimap = { hide = true } })
check("bad values are repaired", bad.role == "auto" and bad.value == "scaled" and bad.offsetX == 100
    and bad.offsetY == -100 and bad.scale == 2)
check("explicit false and minimap hide survive", bad.hideTrivial == false and bad.minimap.hide == true)
local twice = ns.NormalizeDB(ns.NormalizeDB({ offsetX = 12.4 }))
check("idempotent and rounded offsets", twice.offsetX == 12)
check("offset limit is 100 in every direction", ns.ClampOffset(101) == 100 and ns.ClampOffset(-101) == -100
    and ns.ClampOffset("abc") == 0 and ns.ClampOffset(nil) == 0)

-- Role resolution
local function api(tank, group, spec)
    return { tankAura = function() return tank end, groupRole = function() return group end, specRole = function() return spec end }
end
check("tank aura wins", ns.ResolveRole(api(true, "DAMAGER", nil)) == "tank")
check("group role tank", ns.ResolveRole(api(false, "TANK", nil)) == "tank")
check("group role healer", ns.ResolveRole(api(nil, "HEALER", nil)) == "healer")
check("group role damager", ns.ResolveRole(api(nil, "DAMAGER", "TANK")) == "damage")
check("no group role falls to spec role", ns.ResolveRole(api(nil, "NONE", "TANK")) == "tank")
check("spec healer", ns.ResolveRole(api(nil, nil, "HEALER")) == "healer")
check("nothing known is damage", ns.ResolveRole(api(nil, nil, nil)) == "damage")
check("erroring api is ignored", ns.ResolveRole({ tankAura = function() error("boom") end, groupRole = function() return "HEALER" end }) == "healer")
check("missing api table functions", ns.ResolveRole({}) == "damage")

-- Colors
local function key(status, role, off) return ns.StatusColorKey(status, role, off) end
check("not on threat list hides", key(nil, "tank") == nil and key(nil, "damage") == nil)
check("unreadable is grey", key(false, "tank") == "unknown" and key(false, "damage") == "unknown")
check("dps: 0 green 1 orange 2/3 red", key(0, "damage") == "good" and key(1, "damage") == "warn"
    and key(2, "damage") == "bad" and key(3, "damage") == "bad")
check("healer behaves like dps", key(3, "healer") == "bad" and key(0, "healer") == "good")
check("tank: 3 green 2 orange 1/0 red", key(3, "tank") == "good" and key(2, "tank") == "warn"
    and key(1, "tank") == "bad" and key(0, "tank") == "bad")
check("tank off-tank is blue below 2", key(0, "tank", true) == "offtank" and key(1, "tank", true) == "offtank"
    and key(2, "tank", true) == "warn")
check("off-tank never colors dps", key(0, "damage", true) == "good")

-- Filters
local d = ns.NormalizeDB({})
check("shown by default", ns.ShouldShow(d, "normal", false))
check("trivial hidden", not ns.ShouldShow(d, "trivial", false) and not ns.ShouldShow(d, "minus", false))
d.hideTrivial = false
check("trivial shown when allowed", ns.ShouldShow(d, "trivial", false))
d.onlyInstances = true
check("instances only", not ns.ShouldShow(d, "normal", false) and ns.ShouldShow(d, "normal", true))
d.enabled = false
check("disabled hides all", not ns.ShouldShow(d, "normal", true))

-- Gradient: green at 0 %, red at 100 %, mirrored for tanks, clamped
local function near(a, b) return math.abs(a - b) < 0.001 end
local g0, g50, g100 = ns.GradientColor(0, false), ns.GradientColor(50, false), ns.GradientColor(100, false)
check("dps gradient endpoints", near(g0[2], 0.85) and near(g0[1], 0.18) and near(g100[1], 0.90) and near(g100[2], 0.15))
check("dps gradient midpoint is yellow", near(g50[1], 0.97) and near(g50[2], 0.82))
local t0, t100 = ns.GradientColor(0, true), ns.GradientColor(100, true)
check("tank gradient is mirrored", near(t0[1], 0.90) and near(t100[2], 0.85))
local q = ns.GradientColor(25, false)
check("per-percent interpolation", q[1] > g0[1] and q[1] < g50[1] and q[2] < g0[2] and q[2] > g50[2])
check("gradient clamps and tolerates junk", near(ns.GradientColor(250, false)[1], 0.90) and near(ns.GradientColor(-5, false)[2], 0.85)
    and ns.GradientColor("x", false)[1] ~= nil)
check("off-tank color beats the gradient for tanks only", ns.ColorForPercent(10, "tank", true) == ns.COLORS.offtank
    and ns.ColorForPercent(10, "damage", true) ~= ns.COLORS.offtank)

-- Layout
local m = { barW = 190, barH = 20, levelShown = true, levelRight = true, levelW = 28, levelH = 25 }
local db2 = ns.NormalizeDB({})
check("defaults: badge right, make room, color number", db2.mode == "badge" and db2.side == "right" and db2.makeRoom
    and db2.colorText and not db2.colorBackground and not db2.colorBar and db2.stripText)
check("normalize repairs mode and side", ns.NormalizeDB({ mode = "x", side = "y" }).mode == "badge"
    and ns.NormalizeDB({ side = "middle" }).side == "right")
local b = ns.Layout("badge", "right", m, db2)
check("badge right chains to the level badge", b.points[1][2] == "level" and b.points[1][4] == 5 and b.room.rightX == b.w + 5
    and b.h == 25 and b.w == 38)
local bNoLevel = ns.Layout("badge", "right", { barW = 190, barH = 20 }, db2)
check("badge right without level badge sits on the bar", bNoLevel.points[1][2] == "bar" and bNoLevel.h == 25)
local bl = ns.Layout("badge", "left", m, db2)
check("badge left pushes raid icon left", bl.points[1][1] == "RIGHT" and bl.room.leftX == -(bl.w + 5) and bl.room.rightX == 0)
check("badge top pushes the name up", ns.Layout("badge", "top", m, db2).room.nameY == 27)
check("badge bottom needs no room", ns.Layout("badge", "bottom", m, db2).room.nameY == 0)
local seg = ns.Layout("segment", "top", m, db2)
check("segment coerces top to left, no room", seg.look == "segment" and seg.points[1][1] == "LEFT" and seg.h == 20 and seg.room.healthTextX == 0)
check("segment right shifts the health text", ns.Layout("segment", "right", m, db2).room.healthTextX == -40)
local st = ns.Layout("strip", "left", m, db2)
check("strip coerces to top, full bar width, pushes name", st.look == "strip" and #st.points == 2 and st.w == 190
    and st.h == 7 and st.room.nameY == 12)
check("strip bottom", ns.Layout("strip", "bottom", m, db2).points[1][1] == "TOPLEFT")
local fl = ns.Layout("floating", "right", m, ns.NormalizeDB({ offsetX = 20, offsetY = -10, scale = 2 }))
check("floating uses offsets and scale", fl.scale == 2 and fl.points[1][4] == 10 and fl.points[1][5] == -3.5)

-- Tank lead: 100 % red, 150 % yellow, 200 % and more green
check("lead 100 is red", near(ns.LeadColor(100)[1], 0.90) and near(ns.LeadColor(100)[2], 0.15))
check("lead 150 is yellow", near(ns.LeadColor(150)[1], 0.97))
check("lead 200+ is green", near(ns.LeadColor(200)[2], 0.85) and near(ns.LeadColor(400)[2], 0.85))
