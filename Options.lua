local addonName, ns = ...
local L = ns.L

local frame
local controls = {}       -- refresh functions
local floatingOnly = {}   -- controls enabled only in floating mode

local WIDTH, HEIGHT = 660, 732
local COL1, COL2, COLW = 16, 342, 302

-- Same look as the WoWraVox window: dark marble panel, gold corners, thin brown rules.
local function stylePanel(panel, r, g, b)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(r, g, b, 0.97)
    panel:SetBackdropBorderColor(0.52, 0.41, 0.2, 1)
    local marble = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    marble:SetAllPoints()
    marble:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble")
    marble:SetAlpha(0.12)
    for _, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local corner = panel:CreateTexture(nil, "BORDER")
        corner:SetSize(6, 6)
        corner:SetPoint(point, panel, point, 0, 0)
        corner:SetColorTexture(0.88, 0.68, 0.24, 0.95)
    end
end

local function label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetText(L[text] or text)
    -- Explanations and values in a muted, desaturated gold; labels stay white, headings gold.
    if template == "GameFontNormalSmall" then fs:SetTextColor(0.76, 0.72, 0.6) end
    return fs
end

local function heading(parent, text, x, y)
    local fs = label(parent, text, "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
    local rule = parent:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(0.35, 0.29, 0.18, 0.78)
    -- Snap to whole screen pixels: at a fractional window scale a 1 px rule would otherwise look 2 px thick.
    if rule.SetSnapToPixelGrid then rule:SetSnapToPixelGrid(true); rule:SetTexelSnappingBias(0) end
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
    rule:SetWidth(COLW)
    return fs
end

-- Hover help for every control, keyed by the control's label.
local TIPS = {
    ["Make room (move nameplate elements aside)"] = "Moves the nameplate's name, raid icon, elite dragon, crowd-control icons or health text aside so nothing overlaps the element. Blizzard nameplates only.",
    ["Color the number"] = "The threat number takes the threat color (green at 0 %, red at 100 %).",
    ["Color the background"] = "The badge or segment background takes the threat color. With a colored number as well, the background uses a darker shade so the number stays readable.",
    ["Color the health bar"] = "Colors only the filled part of the health bar. The empty track and the rest of the nameplate stay dark. Blizzard nameplates only.",
    ["Number on the strip"] = "Strip mode only: shows the threat number next to the right end of the thin threat bar. Off = the bar alone.",
    ["Safe glow color"] = "Choose the color used around the recommended enemy.",
    ["Tank for safe-target recommendations"] = "Automatic uses the assigned or detected tank. Choose a group member to override that choice for this group.",
    ["Role"] = "Decides the color direction. Automatic detects tanks by stance, form or aura, then by group role or specialization. As a tank, holding the enemy is green; otherwise it is red.",
    ["Size"] = "Only for a freely dragged badge: scales it from half to double size.",
    ["Reset position"] = "Only for a freely dragged badge: back to the bar's top-left corner at normal size.",
    ["Enable TrisThreat"] = "Turns TrisThreat on or off.",
    ["Show solo"] = "Show TrisThreat when you are not in a party or raid.",
    ["Show in group"] = "Show TrisThreat while grouped, including in the open world.",
    ["Hide on trivial mobs"] = "No element on trivial or minor enemies.",
    ["Show minimap icon"] = "Shows the TrisThreat button on the minimap. Right-click the button to hide it.",
    ["Preview threat"] = "Try a threat value: the preview above and your current target show it, no combat needed.",
    ["Off-tank"] = "Preview the off-tank color (blue, tanks only).",
    ["Reach"] = "How far the glow spreads outwards from the health bar.",
    ["Strength"] = "How bright the glow is right at the bar (its opacity).",
    ["Feather"] = "How soft the edge is. 100 % fades smoothly over the whole reach; lower values stay bright longer and then fade faster.",
    ["Safe target glow"] = "Green glow on an enemy only while all three hold: a group tank (or, if no tank is assigned, another group member or your pet) holds it with a clear threat lead, is targeting exactly that enemy, and your own threat on it is low. With several tanks, each tank's target can glow. Unreadable threat counts as no. Not for tanks.",
}

local function addTooltip(widget, text)
    local tip = TIPS[text]
    if not (widget and tip) then return end
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L[text] or text, 1, 0.82, 0.2)
        GameTooltip:AddLine(L[tip] or tip, 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function onLayoutChanged()
    ns.ApplyLayout()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

local function checkbox(parent, text, x, y, key, after)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 2, y)
    check:SetSize(24, 24)
    check.label = label(parent, text)
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check:SetHitRectInsets(0, -(check.label:GetStringWidth() + 4), 0, 0)
    addTooltip(check, text)
    check:SetScript("OnClick", function(self)
        TrisThreatDB[key] = self:GetChecked() and true or false
        onLayoutChanged()
        if after then after() end
    end)
    controls[#controls + 1] = function() check:SetChecked(TrisThreatDB[key] == true) end
    return check
end

-- One row: label left, slider right, value at the end. `after` runs on every change.
local function compactSlider(parent, text, x, y, key, low, high, step, suffix, after)
    local fs = label(parent, text, "GameFontHighlightSmall") -- white like the other labels
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y)
    local valueText = label(parent, "", "GameFontNormalSmall")
    valueText:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + COLW - 2, y)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 74, y - 2)
    s:SetSize(COLW - 74 - 48, 16)
    s:SetMinMaxValues(low, high)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    if s.Low then s.Low:SetText("") end
    if s.High then s.High:SetText("") end
    local loading = false
    s:SetScript("OnValueChanged", function(_, value)
        if loading then return end
        value = math.floor(value / step + 0.5) * step
        TrisThreatDB[key] = value
        valueText:SetText(("%g"):format(value) .. suffix)
        ns.ApplyLayout()
        if after then after() end
    end)
    controls[#controls + 1] = function()
        loading = true
        s:SetValue(TrisThreatDB[key])
        valueText:SetText(("%g"):format(TrisThreatDB[key]) .. suffix)
        loading = false
    end
    s.title = fs -- dimmed together with the slider when it is disabled
    addTooltip(s, text)
    addTooltip(fs, text)
    return s
end

local function dropdown(parent, text, x, y, key, choices)
    local fs = label(parent, text)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y - 6)
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 64, y + 2)
    UIDropDownMenu_SetWidth(dd, COLW - 106)
    local function textOf(value)
        for _, choice in ipairs(choices) do if choice.value == value then return L[choice.text] or choice.text end end
        return ""
    end
    UIDropDownMenu_Initialize(dd, function()
        for _, choice in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = L[choice.text] or choice.text
            info.checked = TrisThreatDB[key] == choice.value
            info.func = function()
                TrisThreatDB[key] = choice.value
                UIDropDownMenu_SetText(dd, textOf(choice.value))
                onLayoutChanged()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    controls[#controls + 1] = function() UIDropDownMenu_SetText(dd, textOf(TrisThreatDB[key])) end
    addTooltip(dd, text)
    if dd.Button then addTooltip(dd.Button, text) end
    return dd
end

----------------------------------------------------------------------------------------------------
-- Mock nameplate: built from the same atlases, fonts and anchors as Blizzard's Forever nameplate
-- (Blizzard_NamePlates: UpdateAnchors, Camelot level badge), and the threat element is placed on it by the
-- exact code that places it in the world.
----------------------------------------------------------------------------------------------------

local mock

local function mockIcon(parent, size, texture)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetTexture(texture)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return t
end

-- Blizzard's layout pass for the mock (mirrors NamePlateUnitFrameMixin:UpdateAnchors for "name above bar").
local function layoutMock()
    local uf, bar = mock.uf, mock.bar
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", uf, "CENTER", -16, -8)
    bar:SetSize(190, 20)
    uf.name:ClearAllPoints()
    uf.name:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2)
    uf.name:SetPoint("RIGHT", uf.PlayerLevelDiffFrame, "RIGHT", 0, 0)
    uf.RaidTargetFrame:ClearAllPoints()
    uf.RaidTargetFrame:SetPoint("RIGHT", bar, "LEFT", 0, 0)
    uf.AurasFrame.CrowdControlListFrame:ClearAllPoints()
    uf.AurasFrame.CrowdControlListFrame:SetPoint("LEFT", uf.PlayerLevelDiffFrame, "RIGHT", 5, 0)
    uf.AurasFrame.LossOfControlFrame:ClearAllPoints()
    uf.AurasFrame.LossOfControlFrame:SetPoint("LEFT", uf.PlayerLevelDiffFrame, "RIGHT", 5, 0)
    bar.LeftText:ClearAllPoints()
    bar.LeftText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    ns.RoomWasReset(uf)
end

local function buildMock(parent, y)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", COL1, y)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -COL1, y)
    panel:SetHeight(150)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.16, 0.17, 0.13, 1)
    panel:SetBackdropBorderColor(0.35, 0.29, 0.18, 0.9)
    panel:SetClipsChildren(true)

    local uf = CreateFrame("Frame", nil, panel)
    uf:SetAllPoints()
    local bar = CreateFrame("StatusBar", nil, uf)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(100)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    ns.SetArt(bar:GetStatusBarTexture(), "UI-HUD-CoolDownManager-Bar", "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill", 1, 1, 1, 1)
    bar.bgTexture = bar:CreateTexture(nil, "BACKGROUND")
    ns.SetArt(bar.bgTexture, "UI-HUD-CoolDownManager-Bar-BG", "Interface\\Buttons\\WHITE8X8", 0, 0, 0, 0.85)
    bar.bgTexture:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
    bar.bgTexture:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -6)
    bar.LeftText = bar:CreateFontString(nil, "OVERLAY")
    ns.SetNameplateFont(bar.LeftText, "SystemFont_NamePlate_Outlined", 9)
    bar.LeftText:SetText("100%")
    bar.RightText = bar:CreateFontString(nil, "OVERLAY")
    ns.SetNameplateFont(bar.RightText, "SystemFont_NamePlate_Outlined", 9)
    bar.RightText:SetText("1,092")
    bar.RightText:SetPoint("RIGHT", bar.LeftText, "LEFT", -2, 0)
    pcall(bar.LeftText.SetTextHeight, bar.LeftText, 14)
    pcall(bar.RightText.SetTextHeight, bar.RightText, 14)
    uf.HealthBarsContainer = { healthBar = bar }

    uf.name = uf:CreateFontString(nil, "OVERLAY")
    ns.SetNameplateFont(uf.name, "SystemFont_NamePlate_Outlined", 9)
    pcall(uf.name.SetTextHeight, uf.name, 14)
    uf.name:SetJustifyH("CENTER")
    uf.name:SetText("Blackrock Outrunner")

    local level = CreateFrame("Frame", nil, uf)
    level:SetPoint("TOPLEFT", bar, "TOPRIGHT", 5, 3)
    level:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 5, -2)
    level:SetWidth(28)
    level.icon = level:CreateTexture(nil, "BACKGROUND")
    level.icon:SetAllPoints()
    ns.SetArt(level.icon, "ui-hud-nameplates-levelindicator", "Interface\\AddOns\\TrisThreat\\Assets\\Tab_Fill.tga")
    level.text = level:CreateFontString(nil, "OVERLAY")
    ns.SetNameplateFont(level.text, "SystemFont_NamePlateLevel", 10)
    level.text:SetPoint("CENTER", 0, 0.5)
    level.text:SetText("22")
    level.text:SetTextColor(1, 0.82, 0)
    uf.PlayerLevelDiffFrame = level

    uf.RaidTargetFrame = CreateFrame("Frame", nil, uf)
    uf.RaidTargetFrame:SetSize(22, 22)
    local elite = uf.RaidTargetFrame:CreateTexture(nil, "ARTWORK")
    elite:SetSize(20, 20)
    elite:SetPoint("RIGHT", uf.RaidTargetFrame, "LEFT", 0, 0)
    ns.SetArt(elite, "nameplates-icon-elite-gold", "Interface\\Buttons\\WHITE8X8", 0, 0, 0, 0)

    uf.AurasFrame = { CrowdControlListFrame = CreateFrame("Frame", nil, uf), LossOfControlFrame = CreateFrame("Frame", nil, uf) }
    uf.AurasFrame.CrowdControlListFrame:SetSize(20, 20)
    mockIcon(uf.AurasFrame.CrowdControlListFrame, 20, "Interface\\Icons\\Spell_Nature_Polymorph"):SetPoint("LEFT")
    uf.AurasFrame.LossOfControlFrame:SetSize(1, 1)
    local debuffs = CreateFrame("Frame", nil, uf)
    debuffs:SetSize(44, 20)
    debuffs:SetPoint("BOTTOM", uf.name, "TOP", 0, 4)
    mockIcon(debuffs, 20, "Interface\\Icons\\Spell_Holy_SealOfMight"):SetPoint("LEFT")
    mockIcon(debuffs, 20, "Interface\\Icons\\Spell_Fire_Immolation"):SetPoint("RIGHT")

    mock = { panel = panel, uf = uf, bar = bar, element = ns.CreateElement() }
    mock.parts = { uf = uf, bar = bar, level = level, mock = true }
    mock.element.parts = mock.parts -- the aggro glow of the mock element wraps the mock plate

    -- Drag the element anywhere in the preview. While the mouse is down, every snap spot is outlined; dropping on
    -- one picks that mode and side, dropping anywhere else places the element freely (what you see is what you get).
    local dragger = CreateFrame("Frame")
    local el = mock.element
    el:EnableMouse(true)
    el:RegisterForDrag("LeftButton")
    mock.caption = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mock.caption:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
    mock.caption:Hide()
    mock.zones = {}
    -- Every snap spot is one small dot (no overlapping areas); only the spot under the cursor shows its result as
    -- an outline. At the start of a drag the dots flash once so they read as places to drop on.
    for i, z in ipairs(ns.MOCK_ZONES) do
        local f = CreateFrame("Frame", nil, panel)
        f:SetFrameLevel(panel:GetFrameLevel() + 20)
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetAllPoints()
        f.tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        local mask = f:CreateMaskTexture()
        mask:SetAllPoints(f.tex)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        f.tex:AddMaskTexture(mask)
        f.zone = z
        f:Hide()
        mock.zones[i] = f
    end
    mock.ghost = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    mock.ghost:SetFrameLevel(panel:GetFrameLevel() + 19)
    mock.ghost:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    mock.ghost:SetBackdropColor(1, 0.82, 0.2, 0.18)
    mock.ghost:SetBackdropBorderColor(1, 0.82, 0.2, 1)
    mock.ghost:Hide()

    local function paintZones(active)
        mock.activeZone = active
        for _, f in ipairs(mock.zones) do
            f:SetSize(9, 9)
            f.tex:SetVertexColor(0.6, 0.85, 1, 0.75)
            if mock.flashing then
                f:SetSize(17, 17)
                f.tex:SetVertexColor(1, 0.95, 0.6, 1)
            elseif f == active then
                f:SetSize(13, 13)
                f.tex:SetVertexColor(1, 0.82, 0.2, 1)
            end
        end
        if active and not mock.flashing then
            local l, b, r, t = active.rect[1], active.rect[2], active.rect[3], active.rect[4]
            mock.ghost:ClearAllPoints()
            mock.ghost:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", l, b)
            mock.ghost:SetSize(r - l, t - b)
            mock.ghost:Show()
        else
            mock.ghost:Hide()
        end
    end
    local function showZones()
        local fresh = not mock.zonesShown
        mock.zonesShown = true
        for _, f in ipairs(mock.zones) do
            local l, b, r, t = ns.MockZoneRect(f.zone)
            f.rect = { l, b, r, t }
            local sl, sb, sr, st = ns.MockZoneSnapRect(f.zone)
            f.snapRect = { sl, sb, sr, st }
            f:ClearAllPoints()
            f:SetPoint("CENTER", panel, "BOTTOMLEFT", (sl + sr) / 2, (sb + st) / 2)
            f:Show()
        end
        if fresh then
            mock.flashing = true
            C_Timer.After(0.35, function()
                mock.flashing = false
                if mock.zonesShown then paintZones(mock.activeZone) end
            end)
        end
        paintZones(nil)
    end
    local function hideZones()
        mock.zonesShown, mock.flashing = false, false
        for _, f in ipairs(mock.zones) do f:Hide() end
        mock.ghost:Hide()
        mock.caption:Hide()
    end
    el:SetScript("OnMouseDown", showZones)
    el:SetScript("OnMouseUp", hideZones)

    el:SetScript("OnDragStart", function()
        local db = TrisThreatDB
        showZones()
        dragger:SetScript("OnUpdate", function()
            local cx, cy = GetCursorPosition()
            local es = panel:GetEffectiveScale()
            local px, py = cx / es - (panel:GetLeft() or 0), cy / es - (panel:GetBottom() or 0)
            local rects = {}
            for i, f in ipairs(mock.zones) do rects[i] = f.snapRect end
            local index = ns.PickMockZone(px, py, rects)
            local active = index and mock.zones[index]
            paintZones(active)
            local mode, side, nx, ny, scale = "floating", db.side, db.offsetX, db.offsetY, db.scale
            if active then
                local z = active.zone
                mode, side = z.mode, z.side or db.side
                mock.caption:SetText(L[z.text] or z.text)
            else
                nx, ny = ns.MockFreeOffsets(px, py, db.scale)
                mock.caption:SetText(L["Free position"])
            end
            mock.caption:Show()
            if mode ~= db.mode or side ~= db.side or nx ~= db.offsetX or ny ~= db.offsetY or scale ~= db.scale then
                db.mode, db.side, db.offsetX, db.offsetY, db.scale = mode, side, nx, ny, scale
                ns.ApplyLayout()
                ns.RefreshMock()
            end
        end)
    end)
    el:SetScript("OnDragStop", function()
        dragger:SetScript("OnUpdate", nil)
        hideZones()
        if ns.RefreshOptions then ns.RefreshOptions() end -- the Mode dropdown follows the drop
    end)
    mock.dragger = dragger -- the smoke test drives the drag through these
    ns.mock = mock
end

-- Shows the safe-target halo in the preview and briefly on the real target.
local flashToken = 0
ns.glowKind = "safe"
function ns.FlashGlow(_, mockOnly)
    if not mock then return end
    flashToken = flashToken + 1
    local token = flashToken
    ns.ShowBroadGlow(mock, "safeGlow", ns.GetSafeGlowColor(), mock.parts, mock.element)
    if ns.TestSafeGlow and not mockOnly then ns.TestSafeGlow() end
    C_Timer.After(1.6, function()
        if token ~= flashToken then return end
        ns.HideBroadGlow(mock, "safeGlow")
        ns.RefreshMock() -- hides the aggro glow again unless the preview slider really warns
    end)
end

function ns.RefreshMock()
    if not mock then return end
    local db = TrisThreatDB
    layoutMock()
    local color = ns.ColorForPercent(ns.previewPercent, ns.GetRole(), ns.previewOffTank)
    local barColor = db.colorBar and color or { 0.78, 0.12, 0.12 }
    mock.bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3])
    ns.Arrange(mock.element, mock.parts)
    ns.PaintElement(mock.element, color, ns.previewPercent .. "%", ns.previewPercent, true, 0, 100)
    if mock.percentText then mock.percentText:SetText(ns.previewPercent .. "%") end
end

local ROLE_TEXT = { tank = "Tank", damage = "Damage dealer", healer = "Healer" }

local function build()
    frame = CreateFrame("Frame", "TrisThreatOptions", UIParent, "BackdropTemplate")
    stylePanel(frame, 0.035, 0.04, 0.05)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetScale(math.min(1, (UIParent:GetHeight() - 40) / HEIGHT, (UIParent:GetWidth() - 40) / WIDTH))
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    -- Raises above other addon windows (WoWraVox ...) when clicked, and drops behind them when they are.
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:Hide()
    table.insert(UISpecialFrames, "TrisThreatOptions")

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(40)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", 12, 0)
    icon:SetTexture("Interface\\AddOns\\TrisThreat\\Assets\\TrisThreatIcon.tga")
    local title = label(header, "TrisThreat", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    -- Current mode right next to the title, so every review screenshot shows it.
    local modeText = label(header, "", "GameFontHighlightLarge")
    modeText:SetPoint("LEFT", title, "RIGHT", 12, 0)
    modeText:SetTextColor(0.55, 0.85, 1)
    ns.OnModeChanged = function(text) modeText:SetText("· " .. text) end
    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -2, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    buildMock(frame, -44)

    -- Preview row (own row, below the mock)
    local y = -202
    label(frame, "Preview threat"):SetPoint("TOPLEFT", frame, "TOPLEFT", COL1 + 2, y)
    local previewSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
    previewSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", COL1 + 130, y + 1)
    previewSlider:SetSize(300, 16)
    previewSlider:SetMinMaxValues(0, 100)
    previewSlider:SetValueStep(1)
    previewSlider:SetObeyStepOnDrag(true)
    previewSlider:SetValue(ns.previewPercent)
    if previewSlider.Low then previewSlider.Low:SetText("") end
    if previewSlider.High then previewSlider.High:SetText("") end
    addTooltip(previewSlider, "Preview threat")
    previewSlider:SetScript("OnValueChanged", function(_, value)
        ns.previewPercent = math.floor(value + 0.5)
        ns.RefreshMock()
        ns.ShowPreview()
    end)
    mock.percentText = label(frame, "", "GameFontNormal")
    mock.percentText:SetPoint("LEFT", previewSlider, "RIGHT", 10, 0)
    local off = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    off:SetSize(24, 24)
    off:SetPoint("TOPLEFT", frame, "TOPLEFT", COL2 + 176, y + 5)
    label(frame, "Off-tank"):SetPoint("LEFT", off, "RIGHT", 2, 0)
    addTooltip(off, "Off-tank")
    off:SetScript("OnClick", function(self)
        ns.previewOffTank = self:GetChecked() and true or false
        ns.RefreshMock()
        ns.ShowPreview()
    end)

    -- Both columns share the same section rows, so every heading and rule sits at the same height.
    local ROW1, ROW2, ROW3 = -236, -344, -520
    -- Left column: display, colors, glows
    local yl = ROW1
    heading(frame, "Display", COL1, yl); yl = yl - 28
    local drag = label(frame, "Drag the element in the preview. Dots mark where it snaps: badge beside or above the bar, strip at the top or bottom center, segment in the bar ends. Anywhere else places it freely.", "GameFontNormalSmall")
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", COL1 + 2, yl + 4)
    drag:SetWidth(COLW)
    drag:SetJustifyH("LEFT"); yl = yl - 48
    checkbox(frame, "Make room (move nameplate elements aside)", COL1, yl, "makeRoom")

    yl = ROW2
    heading(frame, "Colors", COL1, yl); yl = yl - 24
    -- One checkbox per row: two columns clipped the longer labels under their neighbour.
    for _, c in ipairs({ { "Color the number", "colorText" }, { "Color the background", "colorBackground" },
        { "Color the health bar", "colorBar" }, { "Number on the strip", "stripText" } }) do
        checkbox(frame, c[1], COL1, yl, c[2]); yl = yl - 24
    end
    yl = yl - 6
    local legend = label(frame, "Green at 0 % threat, red at 100 %. As a tank holding the enemy, it follows your lead: full and green with a big lead, shrinking and turning red as the next player closes in.", "GameFontNormalSmall")
    legend:SetPoint("TOPLEFT", frame, "TOPLEFT", COL1 + 2, yl)
    legend:SetWidth(COLW)
    legend:SetJustifyH("LEFT")

    -- Safe indicator controls: the recommendation glow stays outside the health bar.
    yl = ROW3
    heading(frame, "Safe indicator", COL1, yl); yl = yl - 24
    checkbox(frame, "Safe target glow", COL1, yl, "safeGlow", function() ns.FlashGlow("safe") end)
    yl = yl - 28

    local safeColorButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    safeColorButton:SetSize(92, 22)
    safeColorButton:SetPoint("TOPLEFT", frame, "TOPLEFT", COL1 + 2, yl)
    safeColorButton:SetText("")
    safeColorButton.caption = safeColorButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    safeColorButton.caption:SetPoint("CENTER", safeColorButton, "CENTER", 4, 0)
    safeColorButton.caption:SetText("Glow color")
    safeColorButton.swatch = safeColorButton:CreateTexture(nil, "OVERLAY")
    safeColorButton.swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
    safeColorButton.swatch:SetSize(12, 12)
    safeColorButton.swatch:SetPoint("LEFT", safeColorButton, "LEFT", 5, 0)
    addTooltip(safeColorButton, "Safe glow color")
    local safeTankButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    safeTankButton:SetSize(132, 22)
    safeTankButton:SetPoint("LEFT", safeColorButton, "RIGHT", 6, 0)
    local safeTankMenu = CreateFrame("Frame", "TrisThreatSafeTankMenu", UIParent, "UIDropDownMenuTemplate")
    safeTankButton:SetScript("OnClick", function(self)
        UIDropDownMenu_Initialize(safeTankMenu, function(menu, level)
            local function addChoice(text, guid)
                local info = UIDropDownMenu_CreateInfo()
                info.text = text
                info.checked = TrisThreatDB.safeTankGUID == guid
                info.func = function()
                    TrisThreatDB.safeTankGUID = guid
                    UIDropDownMenu_SetText(safeTankMenu, guid and "Tank: Manual" or "Tank: Auto")
                    CloseDropDownMenus()
                    ns.RefreshAll()
                    if ns.RefreshOptions then ns.RefreshOptions() end
                end
                UIDropDownMenu_AddButton(info, level)
            end
            addChoice("Automatic", nil)
            local prefix, count
            if IsInRaid and IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
            elseif IsInGroup and IsInGroup() then prefix, count = "party", GetNumSubgroupMembers() end
            for index = 1, count or 0 do
                local unit = prefix .. index
                local same = UnitIsUnit(unit, "player")
                local guid = UnitGUID(unit)
                if guid and not issecretvalue(guid) and (same == false or issecretvalue(same)) then
                    local ok, name = pcall(UnitName, unit)
                    if not ok or issecretvalue(name) or type(name) ~= "string" then name = unit end
                    addChoice(name, guid)
                end
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, safeTankMenu, self, 0, 0)
    end)
    safeColorButton:SetScript("OnClick", function()
        local picker = ColorPickerFrame
        if not picker then return end
        local color = ns.GetSafeGlowColor()
        local previous = { color[1], color[2], color[3] }
        local function apply(r, g, b)
            TrisThreatDB.safeGlowColor = { r, g, b }
            safeColorButton.swatch:SetVertexColor(r, g, b, 1)
            ns.RefreshAll()
            ns.RefreshMock()
        end
        local function restore(old)
            if old then apply(old.r or old[1], old.g or old[2], old.b or old[3]) end
        end
        if picker.SetupColorPickerAndShow then
            picker:SetupColorPickerAndShow({
                r = previous[1], g = previous[2], b = previous[3], hasOpacity = false,
                swatchFunc = function() local r, g, b = picker:GetColorRGB(); apply(r, g, b) end,
                cancelFunc = restore,
            })
        else
            picker.func = function() apply(picker:GetColorRGB()) end
            picker.cancelFunc = restore
            picker.previousValues = { previous[1], previous[2], previous[3] }
            picker:SetColorRGB(previous[1], previous[2], previous[3])
            picker:Show()
        end
    end)
    local function refreshSafeTankButton()
        local guid = TrisThreatDB.safeTankGUID
        if not guid then safeTankButton:SetText("Tank: Auto"); return end
        local prefix, count
        if IsInRaid and IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
        elseif IsInGroup and IsInGroup() then prefix, count = "party", GetNumSubgroupMembers() end
        for index = 1, count or 0 do
            local unit = prefix .. index
            if UnitGUID(unit) == guid then
                local ok, name = pcall(UnitName, unit)
                if ok and not issecretvalue(name) and type(name) == "string" then
                    safeTankButton:SetText(name)
                    return
                end
            end
        end
        safeTankButton:SetText("Tank: Manual")
    end
    controls[#controls + 1] = refreshSafeTankButton
    controls[#controls + 1] = function()
        local color = ns.GetSafeGlowColor()
        safeColorButton.swatch:SetVertexColor(color[1], color[2], color[3], 1)
    end
    safeTankButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Tank for safe-target recommendations", 1, 0.82, 0.2)
        local unit = ns.GetSafeTankUnit()
        if unit then
            local ok, name = pcall(UnitName, unit)
            GameTooltip:AddLine(ok and not issecretvalue(name) and type(name) == "string" and name or unit, 1, 1, 1)
        else
            GameTooltip:AddLine("No tank detected", 1, 1, 1)
        end
        GameTooltip:AddLine("Click to choose a group member or use automatic detection.", 0.85, 0.88, 0.94)
        GameTooltip:Show()
    end)
    safeTankButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    yl = yl - 30
    -- Reach controls only the outside glow; the glow ring never crosses the health-bar rectangle.
    for _, s in ipairs({ { "Reach", "glowReach", 10, 80, 2, " px" }, { "Strength", "glowStrength", 10, 100, 5, " %" },
        { "Width", "glowWidth", -90, 40, 2, " px" }, { "Position", "glowOffset", -30, 60, 2, " px" } }) do
        compactSlider(frame, s[1], COL1, yl, s[2], s[3], s[4], s[5], s[6], function() ns.FlashGlow(ns.glowKind, true) end)
        yl = yl - 28
    end

    -- Right column: role, floating position, general
    local yr = ROW1
    heading(frame, "Role and value", COL2, yr); yr = yr - 28
    dropdown(frame, "Role", COL2, yr, "role", {
        { value = "auto", text = "Automatic" }, { value = "tank", text = "Tank" },
        { value = "damage", text = "Damage dealer" }, { value = "healer", text = "Healer" },
    }); yr = yr - 36 -- the dropdown frame is taller than its row: leave room so the text below is not covered
    ns.detectedText = label(frame, "", "GameFontNormalSmall")
    ns.detectedText:SetPoint("TOPLEFT", frame, "TOPLEFT", COL2 + 2, yr)
    ns.detectedText:SetWidth(COLW)
    ns.detectedText:SetJustifyH("LEFT")

    yr = ROW2
    heading(frame, "Free position", COL2, yr); yr = yr - 26
    local size = compactSlider(frame, "Size", COL2, yr, "scale", 0.5, 2, 0.1, "", ns.RefreshMock)
    floatingOnly[#floatingOnly + 1] = size; yr = yr - 34
    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(140, 22)
    reset:SetPoint("TOPLEFT", frame, "TOPLEFT", COL2, yr)
    reset:SetText(L["Reset position"])
    addTooltip(reset, "Reset position")
    reset:SetScript("OnClick", function()
        TrisThreatDB.offsetX, TrisThreatDB.offsetY, TrisThreatDB.scale = 0, 0, 1
        onLayoutChanged()
    end)
    floatingOnly[#floatingOnly + 1] = reset

    yr = ROW3
    heading(frame, "General", COL2, yr); yr = yr - 24
    checkbox(frame, "Enable TrisThreat", COL2, yr, "enabled"); yr = yr - 26
    checkbox(frame, "Show solo", COL2, yr, "showSolo"); yr = yr - 26
    checkbox(frame, "Show in group", COL2, yr, "showInGroup"); yr = yr - 26
    checkbox(frame, "Hide on trivial mobs", COL2, yr, "hideTrivial"); yr = yr - 26
    -- The minimap flag lives in a sub-table and is stored inverted (hide), so this box is built by hand.
    local mini = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    mini:SetPoint("TOPLEFT", frame, "TOPLEFT", COL2 - 2, yr)
    mini:SetSize(24, 24)
    label(frame, "Show minimap icon"):SetPoint("LEFT", mini, "RIGHT", 2, 0)
    addTooltip(mini, "Show minimap icon")
    mini:SetScript("OnClick", function(self)
        TrisThreatDB.minimap.hide = not self:GetChecked()
        if ns.ApplyMinimap then ns.ApplyMinimap() end
    end)
    frame.minimapShow = mini

    frame:SetScript("OnHide", ns.HidePreview)
    frame:SetScript("OnShow", function()
        ns.RefreshMock()
        ns.ShowPreview() -- test mode: the target gets the element without combat
    end)
end

local function setEnabled(control, enabled)
    if control.SetEnabled then control:SetEnabled(enabled) end
    control:SetAlpha(enabled and 1 or 0.4)
    if control.title then control.title:SetAlpha(enabled and 1 or 0.4) end
end

local function refresh()
    if not frame then return end
    for _, fn in ipairs(controls) do fn() end
    if ns.detectedText then
        local role, key = ns.DetectRole()
        local reason = ns.ROLE_REASONS[key] or key
        ns.detectedText:SetText(string.format(L["Detected: %s"], (L[ROLE_TEXT[role]] or role) .. " (" .. L[reason] .. ")"))
    end
    if ns.OnModeChanged and ns.RoleModeText then
        local text, manual = ns.RoleModeText()
        ns.OnModeChanged(L[text] .. (manual and "*" or ""))
    end
    local floating = TrisThreatDB.mode == "floating"
    for _, control in ipairs(floatingOnly) do setEnabled(control, floating) end
    ns.RefreshMock()
    if frame.minimapShow then frame.minimapShow:SetChecked(not TrisThreatDB.minimap.hide) end
end
ns.RefreshOptions = refresh

function ns.previewWanted() return frame ~= nil and frame:IsShown() end

function ns.ToggleOptions()
    if not frame then build(); refresh() end
    if frame:IsShown() then frame:Hide() else refresh(); frame:Show() end
end

SLASH_TRISTHREAT1 = "/tristhreat"
SLASH_TRISTHREAT2 = "/tt"
-- /tt dump: writes the structure of the target's nameplate (frames, regions, anchors, textures) to
-- TrisThreatDB.dump (saved on /reload) so the skin integration can be built against what the client really has.
local function dumpNameplate()
    local plate = C_NamePlate.GetNamePlateForUnit("target") or (C_NamePlate.GetNamePlates()[1])
    if not plate then print("|cffe0ad3dTrisThreat|r: " .. L["Target an enemy first."]); return end
    local out = {}
    local function safe(fn, ...)
        local ok, a, b, c, d, e = pcall(fn, ...)
        if not ok then return "?" end
        if issecretvalue and issecretvalue(a) then return "<secret>" end
        return a, b, c, d, e
    end
    local function keyOf(parent, child)
        for k, v in pairs(parent) do
            if v == child and type(k) == "string" then return k end
        end
        return "-"
    end
    local function describe(obj, key, depth)
        local indent = string.rep("  ", depth)
        local kind = safe(obj.GetObjectType, obj)
        local name = obj.GetName and safe(obj.GetName, obj) or nil
        local parts = { indent .. tostring(key) .. " [" .. tostring(kind) .. "]" .. (name and (" name=" .. tostring(name)) or "") }
        if obj.GetWidth then
            parts[#parts + 1] = string.format("size=%sx%s", tostring(safe(obj.GetWidth, obj)), tostring(safe(obj.GetHeight, obj)))
        end
        if obj.IsShown then parts[#parts + 1] = "shown=" .. tostring(safe(obj.IsShown, obj)) end
        if obj.GetAlpha then parts[#parts + 1] = "alpha=" .. tostring(safe(obj.GetAlpha, obj)) end
        if obj.GetNumPoints then
            for i = 1, (safe(obj.GetNumPoints, obj) or 0) do
                local point, rel, relPoint, x, y = safe(obj.GetPoint, obj, i)
                local relName = "?"
                if type(rel) == "table" then
                    relName = (rel.GetName and safe(rel.GetName, rel)) or (rel.GetObjectType and safe(rel.GetObjectType, rel)) or "?"
                end
                parts[#parts + 1] = string.format("pt%d=%s>%s:%s(%s,%s)", i, tostring(point), tostring(relName), tostring(relPoint), tostring(x), tostring(y))
            end
        end
        if kind == "Texture" then
            parts[#parts + 1] = "atlas=" .. tostring(safe(obj.GetAtlas, obj)) .. " tex=" .. tostring(safe(obj.GetTexture, obj))
            local r, g, b, a = safe(obj.GetVertexColor, obj)
            parts[#parts + 1] = string.format("vc=%s,%s,%s,%s layer=%s", tostring(r), tostring(g), tostring(b), tostring(a), tostring(safe(obj.GetDrawLayer, obj)))
        elseif kind == "FontString" then
            local font, size, flags = safe(obj.GetFont, obj)
            parts[#parts + 1] = string.format("font=%s,%s,%s text=%s", tostring(font), tostring(size), tostring(flags), tostring(safe(obj.GetText, obj)))
        elseif kind == "StatusBar" then
            local tex = safe(obj.GetStatusBarTexture, obj)
            if type(tex) == "table" then
                parts[#parts + 1] = "barTex=" .. tostring(safe(tex.GetTexture, tex)) .. " atlas=" .. tostring(safe(tex.GetAtlas, tex))
            end
        end
        out[#out + 1] = table.concat(parts, " ")
        if depth >= 5 then return end
        if obj.GetRegions then
            for _, region in ipairs({ obj:GetRegions() }) do describe(region, keyOf(obj, region), depth + 1) end
        end
        if obj.GetChildren then
            for _, child in ipairs({ obj:GetChildren() }) do describe(child, keyOf(obj, child), depth + 1) end
        end
    end
    describe(plate, "plate", 0)
    TrisThreatDB.dump = { build = (select(4, GetBuildInfo())), lines = out }
    print("|cffe0ad3dTrisThreat|r: dumped " .. #out .. " nameplate elements. /reload to save them to the SavedVariables.")
end

SlashCmdList["TRISTHREAT"] = function(message)
    if (message or ""):lower():match("^%s*dump") then dumpNameplate(); return end
    if (message or ""):lower():match("^%s*probe") then
        local ok = ns.ProbeCurve(70)
        print("|cffe0ad3dTrisThreat|r probe: color curve " .. (ok and "works for plain numbers" or "NOT available"))
        if UnitExists("target") then
            local _, _, scaled = UnitDetailedThreatSituation("player", "target")
            local okTarget, color = ns.ProbeCurve(scaled)
            print("|cffe0ad3dTrisThreat|r probe: target threat " .. (scaled == nil and "none" or "read")
                .. ", curve " .. (okTarget and "OK" or "FAILED") .. (color and "" or ""))
            local lead = UnitThreatPercentageOfLead and UnitThreatPercentageOfLead("player", "target")
            local okLead = ns.ProbeCurve(lead)
            print("|cffe0ad3dTrisThreat|r probe: lead " .. (lead == nil and "none" or (issecretvalue and issecretvalue(lead)) and "secret" or tostring(lead))
                .. ", curve " .. (okLead and "OK" or "FAILED"))
        end
        if UnitExists("target") then
            -- Show the same target, holder-role, status, and lead inputs used by the safe-target selection.
            local seen = {}
            local tokens = { "pet" }
            if IsInRaid and IsInRaid() then
                for index = 1, GetNumGroupMembers() do tokens[#tokens + 1] = "raid" .. index end
            elseif IsInGroup and IsInGroup() then
                for index = 1, GetNumSubgroupMembers() do tokens[#tokens + 1] = "party" .. index end
            end
            local function probeValue(value)
                if value == nil then return "none" end
                if issecretvalue and issecretvalue(value) then return "secret" end
                return tostring(value)
            end
            for _, token in ipairs(tokens) do
                if UnitExists(token) then
                    local same = UnitIsUnit(token .. "target", "target")
                    local status = UnitThreatSituation(token, "target")
                    local role = token == "pet" and "pet" or UnitGroupRolesAssigned(token)
                    local leadStatus, leadAvailable = nil, type(UnitThreatLeadSituation) == "function"
                    if leadAvailable then
                        local ok, value = pcall(UnitThreatLeadSituation, token, "target")
                        if ok then leadStatus = value else leadStatus = "error" end
                    end
                    seen[#seen + 1] = token .. " role: " .. probeValue(role)
                        .. ", targets: " .. probeValue(same)
                        .. ", threat status: " .. probeValue(status)
                        .. ", lead state: " .. (leadAvailable and probeValue(leadStatus) or "API unavailable")
                end
            end
            print("|cffe0ad3dTrisThreat|r probe: safe target - " .. (#seen > 0 and table.concat(seen, "; ") or "no group member or pet"))
        end
        if not UnitExists("target") then
            print("|cffe0ad3dTrisThreat|r probe: no target - target an enemy in combat and run /tt probe again")
        end
        return
    end
    ns.ToggleOptions()
end
