local _, ns = ...

-- The threat element in Blizzard's own nameplate art (Forever / Retail atlases, see Blizzard_NamePlates):
--   badge    = a second level badge ("ui-hud-nameplates-levelindicator": dark box, gold rim)
--   segment  = a section inside the health bar's end; the bar's health text makes room for it
--   strip    = a thin bar with the nameplate bar's frame and fill atlases
--   floating = the badge, freely positioned

local ATLAS_BADGE = "ui-hud-nameplates-levelindicator"
local ATLAS_BADGE_SELECTED = "ui-hud-nameplates-levelindicator-rectangle-selected"
local ATLAS_BAR_FILL = "UI-HUD-CoolDownManager-Bar"
local ATLAS_BAR_BG = "UI-HUD-CoolDownManager-Bar-BG"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FALLBACK_BADGE = "Interface\\AddOns\\TrisThreat\\Assets\\Tab_Fill.tga"

local atlasCache = {}
local function hasAtlas(name)
    if atlasCache[name] == nil then
        atlasCache[name] = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) ~= nil
    end
    return atlasCache[name]
end

-- Atlas when the client has it, otherwise a tinted file.
function ns.SetArt(texture, atlas, fallback, r, g, b, a)
    if hasAtlas(atlas) then
        texture:SetAtlas(atlas, false)
        texture:SetVertexColor(1, 1, 1, 1)
    else
        texture:SetTexture(fallback or WHITE)
        texture:SetVertexColor(r or 0.06, g or 0.06, b or 0.07, a or 0.95)
    end
end

local function setFont(fontString, objectName, size)
    local object = _G[objectName]
    if object then
        fontString:SetFontObject(object)
    else
        fontString:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    end
end
ns.SetNameplateFont = setFont

function ns.CreateElement()
    local el = CreateFrame("Frame", nil, UIParent)
    el.trisThreatElement = true
    el.bg = el:CreateTexture(nil, "BACKGROUND")
    el.fill = CreateFrame("StatusBar", nil, el)
    el.fill:SetMinMaxValues(0, 100)
    el.fill:SetStatusBarTexture(WHITE)
    el.top = CreateFrame("Frame", nil, el)
    el.top:SetAllPoints()
    el.divider = el.top:CreateTexture(nil, "ARTWORK")
    el.divider:SetColorTexture(0, 0, 0, 1)
    el.selected = el.top:CreateTexture(nil, "OVERLAY")
    el.text = el.top:CreateFontString(nil, "OVERLAY")
    el.text:SetTextColor(1, 1, 1, 1)

    return el
end

-- Glow around the health bar shaped like a pill (rounded ends): 20 nested pills, each one 2 px bigger than the
-- last, each adding a little light (ADD blend), so the sum fades smoothly from bright at the bar to nothing.
-- A pill = a rectangle plus two half circles (circle mask). The light is in the color values, not the alpha
-- (alpha is not reliable with ADD). Red for the aggro warning, green for the safe target.
ns.GLOW_RED, ns.GLOW_GREEN = { 1, 0.12, 0.05 }, { 0.18, 0.85, 0.30 }
local GLOW_LAYERS, GLOW_STEP, GLOW_PEAK = 20, 2, 0.9
local GLOW_GAP = 2 -- starts just outside the bar's own border
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Light of layer i: coverage P(i) of a point i layers out is (1 - (i-1)/N)^1.6; a layer adds P(i) - P(i+1).
local function layerLight(i)
    local function cover(k) return k > GLOW_LAYERS and 0 or (1 - (k - 1) / GLOW_LAYERS) ^ 1.6 end
    return (cover(i) - cover(i + 1)) * GLOW_PEAK
end

function ns.CreateBroadGlow(color)
    local f = CreateFrame("Frame", nil, UIParent)
    f.layers = {}
    for i = 1, GLOW_LAYERS do
        local c = layerLight(i)
        local function part(masked)
            local t = f:CreateTexture(nil, "BACKGROUND")
            t:SetTexture(WHITE)
            t:SetBlendMode("ADD")
            t:SetVertexColor(color[1] * c, color[2] * c, color[3] * c, 1)
            local m
            if masked then
                m = f:CreateMaskTexture()
                m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                t:AddMaskTexture(m)
            end
            return t, m
        end
        local layer = {}
        layer.center = part(false)
        layer.left, layer.leftMask = part(true)
        layer.right, layer.rightMask = part(true)
        f.layers[i] = layer
    end
    f.pulse = f:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local fade = f.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.4)
    fade:SetToAlpha(1)
    fade:SetDuration(0.55)
    return f
end

-- Lays the pills out for a glow frame of w x h: every layer grows by GLOW_STEP, its ends are half circles of
-- radius h/2 + growth (a left and a right cap, each cut at the pill's middle section).
local function layoutGlow(g, w, h)
    g.layW, g.layH = w, h
    w = math.max(w, h)
    local half = h / 2
    for i, layer in ipairs(g.layers) do
        local e = (i - 1) * GLOW_STEP
        local full = h + 2 * e
        local function put(region, p1, rel1, x1, y1, p2, rel2, x2, y2)
            region:ClearAllPoints()
            region:SetPoint(p1, g, rel1, x1, y1)
            region:SetPoint(p2, g, rel2, x2, y2)
        end
        put(layer.center, "TOPLEFT", "TOPLEFT", half, e, "BOTTOMRIGHT", "TOPRIGHT", -half, -(h + e))
        put(layer.left, "TOPLEFT", "TOPLEFT", -e, e, "BOTTOMRIGHT", "TOPLEFT", half, -(h + e))
        put(layer.leftMask, "TOPLEFT", "TOPLEFT", -e, e, "BOTTOMRIGHT", "TOPLEFT", -e + full, e - full)
        put(layer.right, "TOPLEFT", "TOPRIGHT", -half, e, "BOTTOMRIGHT", "TOPRIGHT", e, -(h + e))
        put(layer.rightMask, "TOPLEFT", "TOPRIGHT", e - full, e, "BOTTOMRIGHT", "TOPRIGHT", e, e - full)
    end
end

-- el (optional): the threat element. In strip mode it is part of the outline, so the glow wraps bar AND strip
-- (above or below the bar); badge and segment sit beside or inside the bar and need nothing extra.
function ns.PlaceBroadGlow(g, parts, el)
    local parent = parts.uf
    g:SetParent(parent)
    g:SetFrameStrata(parent:GetFrameStrata())
    -- On real plates one level behind the plate's own art, so the name and icons stay on top of the light.
    g:SetFrameLevel(parts.mock and parent:GetFrameLevel() or math.max(0, parent:GetFrameLevel() - 1))
    g:ClearAllPoints()
    local stripSide = el and el.look == "strip" and el:IsShown()
        and ns.EffectiveSide(TrisThreatDB.mode, TrisThreatDB.side)
    if stripSide == "top" then
        g:SetPoint("TOPLEFT", el, "TOPLEFT", -2 - GLOW_GAP, 3 + GLOW_GAP)
        g:SetPoint("BOTTOMRIGHT", parts.bar, "BOTTOMRIGHT", GLOW_GAP, -GLOW_GAP)
    elseif stripSide == "bottom" then
        g:SetPoint("TOPLEFT", parts.bar, "TOPLEFT", -GLOW_GAP, GLOW_GAP)
        g:SetPoint("BOTTOMRIGHT", el, "BOTTOMRIGHT", 6 + GLOW_GAP, -6 - GLOW_GAP)
    else
        g:SetPoint("TOPLEFT", parts.bar, "TOPLEFT", -GLOW_GAP, GLOW_GAP)
        g:SetPoint("BOTTOMRIGHT", parts.bar, "BOTTOMRIGHT", GLOW_GAP, -GLOW_GAP)
    end
    -- The pills need the frame's size; if the engine has not resolved the anchors yet, use the bar's size.
    local w, h = g:GetWidth(), g:GetHeight()
    if type(w) ~= "number" or type(h) ~= "number" or w < 2 or h < 2 then
        local m = ns.Measure(parts)
        w, h = m.barW + 2 * GLOW_GAP, m.barH + 2 * GLOW_GAP
    end
    if g.layW ~= w or g.layH ~= h then layoutGlow(g, w, h) end
end

-- A glow kept on `owner[key]` (an element, so each plate has its own). el = the threat element, see above.
function ns.ShowBroadGlow(owner, key, color, parts, el)
    local g = owner[key]
    if not g then g = ns.CreateBroadGlow(color); owner[key] = g end
    ns.PlaceBroadGlow(g, parts, el)
    g:Show()
    if not g.pulse:IsPlaying() then g.pulse:Play() end
end

function ns.HideBroadGlow(owner, key)
    local g = owner and owner[key]
    if g then g.pulse:Stop(); g:Hide() end
end

-- Switches the regions to one look. Only runs when the look or side changes.
local function configure(el, look, side)
    if el.look == look and el.side == side then return end
    el.look, el.side = look, side
    el.bg:ClearAllPoints()
    el.fill:ClearAllPoints()
    el.divider:ClearAllPoints()
    el.selected:ClearAllPoints()
    el.text:ClearAllPoints()
    el.divider:Hide()
    el.selected:Hide()

    if look == "strip" then
        ns.SetArt(el.bg, ATLAS_BAR_BG, WHITE, 0, 0, 0, 0.8)
        el.bg:SetPoint("TOPLEFT", el, "TOPLEFT", -2, 3)
        el.bg:SetPoint("BOTTOMRIGHT", el, "BOTTOMRIGHT", 6, -6)
        el.fill:SetAllPoints()
        if hasAtlas(ATLAS_BAR_FILL) then el.fill:GetStatusBarTexture():SetAtlas(ATLAS_BAR_FILL, false) end
        setFont(el.text, "SystemFont_NamePlate_Outlined", 9)
        el.text:SetPoint("LEFT", el, "RIGHT", 8, 0)
    elseif look == "segment" then
        el.bg:SetTexture(WHITE)
        el.bg:SetVertexColor(0.03, 0.03, 0.04, 0.88)
        el.bg:SetAllPoints()
        el.fill:SetAllPoints()
        el.fill:SetStatusBarTexture(WHITE)
        el.divider:SetWidth(1)
        local edge = side == "right" and "LEFT" or "RIGHT"
        el.divider:SetPoint("TOP" .. edge, el, "TOP" .. edge, 0, 0)
        el.divider:SetPoint("BOTTOM" .. edge, el, "BOTTOM" .. edge, 0, 0)
        el.divider:Show()
        setFont(el.text, "SystemFont_NamePlate_Outlined", 9)
        el.text:SetPoint("LEFT", el, "LEFT", 2, 0)
        el.text:SetPoint("RIGHT", el, "RIGHT", -2, 0)
        el.text:SetJustifyH("CENTER")
        el.text:SetWordWrap(false)
    else -- badge / floating
        ns.SetArt(el.bg, ATLAS_BADGE, FALLBACK_BADGE)
        el.bg:SetAllPoints()
        el.fill:SetPoint("TOPLEFT", el, "TOPLEFT", 3, -3)
        el.fill:SetPoint("BOTTOMRIGHT", el, "BOTTOMRIGHT", -3, 3)
        el.fill:SetStatusBarTexture(WHITE)
        if hasAtlas(ATLAS_BADGE_SELECTED) then
            el.selected:SetAtlas(ATLAS_BADGE_SELECTED, false)
            el.selected:SetPoint("TOPLEFT", el, "TOPLEFT", -3, 3)
            el.selected:SetPoint("BOTTOMRIGHT", el, "BOTTOMRIGHT", 3, -4)
        end
        setFont(el.text, "SystemFont_NamePlateLevel", 10)
        -- Pinned to both inner edges and centered: stays centered whatever the plate's font size or scale is.
        el.text:SetPoint("LEFT", el, "LEFT", 3, 0.5)
        el.text:SetPoint("RIGHT", el, "RIGHT", -3, 0.5)
        el.text:SetJustifyH("CENTER")
        el.text:SetWordWrap(false)
    end
end

-- parts = { uf = frame to parent to, bar = health bar, level = level badge frame or nil }.
function ns.PlaceElement(el, parts, spec)
    local parent = parts.uf
    el:SetParent(parent)
    el:SetFrameStrata(parent:GetFrameStrata())
    -- In the world: above Blizzard's level badge (frameLevel 50). In the options preview only a few levels
    -- above the mock, so it never pokes through other windows of the same strata.
    el:SetFrameLevel(parent:GetFrameLevel() + (parts.mock and 5 or 60))
    el:SetScale(spec.scale or 1)
    el:ClearAllPoints()
    if #spec.points == 1 then el:SetSize(spec.w, spec.h) else el:SetHeight(spec.h) end
    for _, p in ipairs(spec.points) do
        local rel = (p[2] == "level" and parts.level) or parts.bar
        el:SetPoint(p[1], rel, p[3], p[4], p[5])
    end
    configure(el, spec.look, ns.EffectiveSide(TrisThreatDB.mode, TrisThreatDB.side))
    -- Text height follows the element like Blizzard's level text (10 on a 23 px badge), not the font object's
    -- size, which the nameplate size setting changes in the world but not in the options preview.
    local textHeight = spec.look == "strip" and 10 or spec.look == "segment" and spec.h * 0.6 or spec.h * 0.4
    pcall(el.text.SetTextHeight, el.text, math.max(7, math.floor(textHeight + 0.5)))
end

local function setBarColor(bar, color, alpha)
    pcall(bar.SetStatusBarColor, bar, color[1], color[2], color[3], alpha or 1)
end

-- color = { r, g, b } (may hold secret numbers); value = threat percentage for the strip fill.
function ns.PaintElement(el, color, text, value, selected, low, high, glow)
    local db = TrisThreatDB
    color = color or ns.COLORS.unknown
    if el.look == "strip" then
        el.fill:Show()
        el.fill:SetMinMaxValues(low or 0, high or 100)
        el.fill:SetValue(value or (low or 0))
        setBarColor(el.fill, color)
        el.text:SetShown(db.stripText)
    else
        el.fill:SetMinMaxValues(0, 100)
        el.fill:SetValue(100)
        if db.colorBackground then
            el.fill:Show()
            -- With a colored number on top, the background takes a darker shade so the number stays readable.
            if db.colorText then
                pcall(el.fill.SetStatusBarColor, el.fill, color[1], color[2], color[3], 0.35)
            else
                setBarColor(el.fill, color, 0.9)
            end
        else
            el.fill:Hide()
        end
        el.text:Show()
    end
    if text ~= nil then el.text:SetText(text) end
    if db.colorText then
        if not pcall(el.text.SetTextColor, el.text, color[1], color[2], color[3], 1) then el.text:SetTextColor(1, 1, 1, 1) end
    else
        el.text:SetTextColor(1, 1, 1, 1)
    end
    el.selected:SetShown(selected == true and (el.look == "badge") and el.selected:GetAtlas() ~= nil)
    if glow and db.glow and el.parts then
        ns.ShowBroadGlow(el, "warnGlow", ns.GLOW_RED, el.parts, el)
    else
        ns.HideBroadGlow(el, "warnGlow")
    end
    el:Show()
end

----------------------------------------------------------------------------------------------------
-- Make room: move Blizzard elements aside by the element's size (undone exactly, never accumulated)
----------------------------------------------------------------------------------------------------

local function shift(region, dx, dy)
    if region and region.AdjustPointsOffset and (dx ~= 0 or dy ~= 0) then
        pcall(region.AdjustPointsOffset, region, dx, dy)
    end
end

local function applyDelta(uf, room, sign)
    shift(uf.HealthBarsContainer, 0, sign * (room.barY or 0))
    shift(uf.name, 0, sign * room.nameY)
    shift(uf.RaidTargetFrame, sign * room.leftX, 0)
    local auras = uf.AurasFrame
    if auras then
        shift(auras.CrowdControlListFrame, sign * room.rightX, 0)
        shift(auras.LossOfControlFrame, sign * room.rightX, 0)
    end
    local bar = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    if bar then shift(bar.LeftText, sign * room.healthTextX, 0) end -- RightText and Text chain to LeftText
end

local function sameRoom(a, b)
    if a == nil or b == nil then return a == b end
    return a.nameY == b.nameY and a.leftX == b.leftX and a.rightX == b.rightX and a.healthTextX == b.healthTextX
        and (a.barY or 0) == (b.barY or 0)
end

-- desired: room table or nil. uf.trisThreatRoom remembers what is applied right now.
function ns.SyncRoom(uf, desired)
    if desired and desired.nameY == 0 and desired.leftX == 0 and desired.rightX == 0 and desired.healthTextX == 0
        and (desired.barY or 0) == 0 then
        desired = nil
    end
    uf.trisThreatDesired = desired
    local applied = uf.trisThreatRoom
    if sameRoom(applied, desired) then return end
    if applied then applyDelta(uf, applied, -1) end
    if desired then applyDelta(uf, desired, 1) end
    uf.trisThreatRoom = desired and {
        nameY = desired.nameY, leftX = desired.leftX, rightX = desired.rightX, healthTextX = desired.healthTextX,
        barY = desired.barY or 0,
    } or nil
end

-- Call after the nameplate re-laid itself out (all Blizzard offsets are fresh again).
function ns.RoomWasReset(uf)
    uf.trisThreatRoom = nil
    if uf.trisThreatDesired then ns.SyncRoom(uf, uf.trisThreatDesired) end
end

----------------------------------------------------------------------------------------------------
-- Make room for other addons' icons (quest markers and the like) that sit where the element now is.
-- Only small, visible frames of the nameplate that overlap the element are pushed outward by exactly the
-- overlap; the shift is undone before every re-placement and when the element goes away. When the other
-- addon re-anchors its icon by itself, the stored offset no longer matches and the undo is skipped.
----------------------------------------------------------------------------------------------------

local BLIZZARD_KEYS = { "HealthBarsContainer", "CastBarsContainer", "AurasFrame", "PlayerLevelDiffFrame",
    "RaidTargetFrame", "ClassificationFrame", "LevelFrame", "SoftTargetFrame", "name", "selectionHighlight" }

local function screenRect(frame)
    local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
    if not ok or type(left) ~= "number" or type(width) ~= "number" then return nil end
    if issecretvalue and (issecretvalue(left) or issecretvalue(width)) then return nil end
    local scale = frame:GetEffectiveScale()
    return left * scale, (left + width) * scale, (bottom + height) * scale, bottom * scale, width, height
end

-- Other addons re-anchor their icons on their own schedule (Questie calls SetPoint("LEFT", x, y) on every
-- refresh). A post-hook on that icon's SetPoint adds our shift to whatever it sets, so the icon stays out of
-- the way between our own updates; with no shift stored the hook does nothing.
local function hookSetPoint(frame)
    if frame.trisThreatShiftHooked then return end
    frame.trisThreatShiftHooked = true
    hooksecurefunc(frame, "SetPoint", function(self, point, a, b, c, d)
        local shift = self.trisThreatShift
        if self.trisThreatApplying or not shift then return end
        self.trisThreatApplying = true
        if type(a) == "number" then                       -- (point, x, y)
            pcall(self.SetPoint, self, point, a + shift.dx, (b or 0) + shift.dy)
        elseif type(b) == "number" then                   -- (point, relativeTo, x, y)
            pcall(self.SetPoint, self, point, a, b + shift.dx, (c or 0) + shift.dy)
        elseif type(c) == "number" then                   -- (point, relativeTo, relativePoint, x, y)
            pcall(self.SetPoint, self, point, a, b, c + shift.dx, (d or 0) + shift.dy)
        elseif a ~= nil then                              -- (point, relativeTo[, relativePoint])
            pcall(self.SetPoint, self, point, a, b or point, shift.dx, shift.dy)
        else                                              -- (point)
            pcall(self.SetPoint, self, point, shift.dx, shift.dy)
        end
        self.trisThreatApplying = nil
    end)
end

local function shiftForeign(frame, dx, dy)
    hookSetPoint(frame)
    frame.trisThreatShift = { dx = dx, dy = dy }
    frame.trisThreatApplying = true
    local ok = pcall(frame.AdjustPointsOffset, frame, dx, dy)
    frame.trisThreatApplying = nil
    if not ok then frame.trisThreatShift = nil end
    return ok
end

local function unshiftForeign(frame)
    local shift = frame.trisThreatShift
    if not shift then return end
    frame.trisThreatShift = nil
    frame.trisThreatApplying = true
    pcall(frame.AdjustPointsOffset, frame, -shift.dx, -shift.dy)
    frame.trisThreatApplying = nil
end

function ns.ReleaseForeign(el)
    for _, frame in ipairs(el.movedForeign or {}) do unshiftForeign(frame) end
    el.movedForeign = nil
end

-- side: "left" | "right" | "top" | "bottom" (the direction to push).
function ns.PushForeign(el, parts, side)
    ns.ReleaseForeign(el)
    local L, R, T, B = screenRect(el)
    if not L then return end
    local gap = 2 * el:GetEffectiveScale()
    local skip = { [el] = true, [parts.uf] = true }
    for _, key in ipairs(BLIZZARD_KEYS) do
        local region = parts.uf[key]
        if type(region) == "table" then skip[region] = true end
    end
    local moved = {}
    local function consider(frame)
        if skip[frame] or frame.trisThreatElement or not frame.IsVisible or not frame:IsVisible() then return end
        if not frame.AdjustPointsOffset then return end
        local l, r, t, b, w, h = screenRect(frame)
        if not l or w > 64 or h > 64 then return end -- icons only, never whole bars or containers
        if r <= L or l >= R or t <= B or b >= T then return end
        local dx, dy = 0, 0
        if side == "left" then dx = (L - gap) - r
        elseif side == "right" then dx = (R + gap) - l
        elseif side == "top" then dy = (T + gap) - b
        else dy = (B - gap) - t end
        local scale = frame:GetEffectiveScale()
        dx, dy = dx / scale, dy / scale
        if shiftForeign(frame, dx, dy) then moved[#moved + 1] = frame end
    end
    for _, child in ipairs({ parts.uf:GetChildren() }) do consider(child) end
    local plate = parts.uf:GetParent()
    if plate and plate ~= UIParent then
        for _, child in ipairs({ plate:GetChildren() }) do consider(child) end
    end
    el.movedForeign = moved
end
