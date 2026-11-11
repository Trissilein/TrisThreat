local _, ns = ...

-- The threat element in Blizzard's own nameplate art (Forever / Retail atlases, see Blizzard_NamePlates):
--   badge    = a second level badge ("ui-hud-nameplates-levelindicator": dark box, gold rim)
--   segment  = a section inside the health bar's end
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

    -- Aggro warning: a red halo behind the element that pulses.
    el.glow = el:CreateTexture(nil, "BACKGROUND", nil, -8)
    el.glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
    el.glow:SetBlendMode("ADD")
    el.glow:SetVertexColor(1, 0.12, 0.05, 1)
    el.glow:SetPoint("TOPLEFT", el, "TOPLEFT", -12, 10)
    el.glow:SetPoint("BOTTOMRIGHT", el, "BOTTOMRIGHT", 12, -10)
    el.glow:Hide()
    el.pulse = el.glow:CreateAnimationGroup()
    el.pulse:SetLooping("BOUNCE")
    local fade = el.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.3)
    fade:SetToAlpha(1)
    fade:SetDuration(0.45)
    return el
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
    el:SetFrameLevel(parent:GetFrameLevel() + 60) -- above Blizzard's level badge (frameLevel 50)
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
    local textHeight = spec.look == "strip" and 10 or spec.look == "segment" and spec.h * 0.6 or spec.h * 0.43
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
    if glow and db.glow then
        el.glow:Show()
        if not el.pulse:IsPlaying() then el.pulse:Play() end
    else
        el.pulse:Stop()
        el.glow:Hide()
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
end

-- desired: room table or nil. uf.trisThreatRoom remembers what is applied right now.
function ns.SyncRoom(uf, desired)
    if desired and desired.nameY == 0 and desired.leftX == 0 and desired.rightX == 0 and desired.healthTextX == 0 then
        desired = nil
    end
    uf.trisThreatDesired = desired
    local applied = uf.trisThreatRoom
    if sameRoom(applied, desired) then return end
    if applied then applyDelta(uf, applied, -1) end
    if desired then applyDelta(uf, desired, 1) end
    uf.trisThreatRoom = desired and {
        nameY = desired.nameY, leftX = desired.leftX, rightX = desired.rightX, healthTextX = desired.healthTextX,
    } or nil
end

-- Call after the nameplate re-laid itself out (all Blizzard offsets are fresh again).
function ns.RoomWasReset(uf)
    uf.trisThreatRoom = nil
    if uf.trisThreatDesired then ns.SyncRoom(uf, uf.trisThreatDesired) end
end
