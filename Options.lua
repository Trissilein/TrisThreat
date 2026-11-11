local addonName, ns = ...
local L = ns.L

local frame
local controls = {}

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
    return fs
end

local function heading(parent, text, y)
    local fs = label(parent, text, "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    local rule = parent:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(0.35, 0.29, 0.18, 0.78)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y - 16)
    rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, y - 16)
    return fs
end

local function checkbox(parent, text, y, key, onChange)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    check:SetSize(24, 24)
    local fs = label(parent, text)
    fs:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check:SetScript("OnClick", function(self)
        TrisThreatDB[key] = self:GetChecked() and true or false
        if onChange then onChange(TrisThreatDB[key]) end
        ns.RefreshAll()
    end)
    controls[#controls + 1] = function() check:SetChecked(TrisThreatDB[key] == true) end
    return check
end

local function slider(parent, text, y, key, low, high, step, onChange)
    local fs = label(parent, text)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    local valueText = label(parent, "", "GameFontNormalSmall")
    valueText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, y)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y - 20)
    s:SetSize(parent:GetWidth() - 44, 16)
    s:SetMinMaxValues(low, high)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    if s.Low then s.Low:SetText(tostring(low)) end
    if s.High then s.High:SetText(tostring(high)) end
    local loading = false
    s:SetScript("OnValueChanged", function(self, value)
        if loading then return end
        value = math.floor(value / step + 0.5) * step
        TrisThreatDB[key] = value
        valueText:SetText(tostring(value))
        if onChange then onChange(value) end
    end)
    controls[#controls + 1] = function()
        loading = true
        s:SetValue(TrisThreatDB[key])
        valueText:SetText(tostring(TrisThreatDB[key]))
        loading = false
    end
    return s
end

local function dropdown(parent, y, key, choices)
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 150, y + 4)
    UIDropDownMenu_SetWidth(dd, 190)
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
                ns.RefreshAll()
                if ns.RefreshOptions then ns.RefreshOptions() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    controls[#controls + 1] = function() UIDropDownMenu_SetText(dd, textOf(TrisThreatDB[key])) end
    return dd
end

local mock  -- mock nameplate in the options window: { panel, bar, capsule, states }

local function refreshMock()
    if not mock then return end
    local db = TrisThreatDB
    ns.AnchorCapsule(mock.capsule, mock.bar, mock.panel)
    -- The in-world capsule uses the HIGH strata, which sits below this DIALOG window: lift it into the preview.
    mock.capsule:SetFrameStrata("DIALOG")
    mock.capsule:SetFrameLevel(mock.panel:GetFrameLevel() + 10)
    local state = ns.previewState
    local c = db.colorBar and ns.COLORS[state] or { 0.78, 0.12, 0.12 }
    mock.bar:SetStatusBarColor(c[1], c[2], c[3])
    ns.PaintCapsule(mock.capsule, c, "70%")
    for key, button in pairs(mock.states) do button.selected:SetShown(key == state) end
end

local function onLayoutChanged()
    ns.ApplyLayout()
    refreshMock()
end

local function buildMock(parent, y)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, y)
    panel:SetHeight(150)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.09, 0.1, 0.06, 1)
    panel:SetBackdropBorderColor(0.35, 0.29, 0.18, 0.9)
    panel:SetClipsChildren(true)
    local name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetText("Blackrock Outrunner")
    name:SetPoint("CENTER", panel, "CENTER", 0, 14)
    -- Default Blizzard nameplate look: flat dark red bar, black background, 1 px black frame.
    local frameBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    frameBox:SetSize(242, 18)
    frameBox:SetPoint("TOP", name, "BOTTOM", 0, -3)
    frameBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frameBox:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    frameBox:SetBackdropBorderColor(0, 0, 0, 1)
    local bar = CreateFrame("StatusBar", nil, frameBox)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(64)
    local capsule = ns.CreateCapsule()
    mock = { panel = panel, bar = bar, capsule = capsule, states = {} }

    -- State buttons double as the legend: click one to preview that threat state here and on your target.
    local x = 8
    for _, entry in ipairs({ { "good", "Good" }, { "warn", "Careful" }, { "bad", "Bad" }, { "offtank", "Off-tank" } }) do
        local button = CreateFrame("Button", nil, panel)
        button:SetSize(86, 16)
        button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x, 6)
        local fill = button:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("LEFT")
        fill:SetSize(12, 12)
        fill:SetColorTexture(unpack(ns.COLORS[entry[1]]))
        local text = label(button, entry[2], "GameFontNormalSmall")
        text:SetPoint("LEFT", fill, "RIGHT", 4, 0)
        button.selected = button:CreateTexture(nil, "BACKGROUND")
        button.selected:SetPoint("TOPLEFT", fill, "TOPLEFT", -2, 2)
        button.selected:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 2, -2)
        button.selected:SetColorTexture(1, 1, 1, 0.9)
        button:SetScript("OnClick", function()
            ns.previewState = entry[1]
            refreshMock()
            ns.ShowPreview()
        end)
        mock.states[entry[1]] = button
        x = x + 92
    end
    return panel
end

local ROLE_TEXT = { tank = "Tank", damage = "Damage dealer", healer = "Healer" }

local function build()
    frame = CreateFrame("Frame", "TrisThreatOptions", UIParent, "BackdropTemplate")
    stylePanel(frame, 0.035, 0.04, 0.05)
    frame:SetSize(420, 826)
    frame:SetScale(math.min(1, (UIParent:GetHeight() - 40) / 826))
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
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
    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -2, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    buildMock(frame, -48)
    local y = -208
    checkbox(frame, "Enabled", y, "enabled")
    y = y - 34

    heading(frame, "Role", y); y = y - 28
    dropdown(frame, y, "role", {
        { value = "auto", text = "Automatic" }, { value = "tank", text = "Tank" },
        { value = "damage", text = "Damage dealer" }, { value = "healer", text = "Healer" },
    })
    local roleLabel = label(frame, "Role")
    roleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, y - 2)
    ns.detectedText = label(frame, "", "GameFontNormalSmall")
    ns.detectedText:SetPoint("TOPLEFT", frame, "TOPLEFT", 150, y - 32)
    y = y - 58

    heading(frame, "Value shown", y); y = y - 28
    dropdown(frame, y, "value", {
        { value = "scaled", text = "Threat to pull aggro (scaled)" },
        { value = "raw", text = "Share of the tank's threat (raw)" },
        { value = "lead", text = "Lead over the next player (tank)" },
    })
    y = y - 40

    heading(frame, "Position", y); y = y - 26
    slider(frame, "Horizontal offset", y, "offsetX", -ns.OFFSET_LIMIT, ns.OFFSET_LIMIT, 1, onLayoutChanged); y = y - 48
    slider(frame, "Vertical offset", y, "offsetY", -ns.OFFSET_LIMIT, ns.OFFSET_LIMIT, 1, onLayoutChanged); y = y - 48
    slider(frame, "Size", y, "scale", 0.5, 2, 0.1, onLayoutChanged); y = y - 44
    local hint = label(frame, "Nameplate offsets in pixels. Positive values move the capsule right and up.", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, y)
    hint:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    hint:SetJustifyH("LEFT")
    y = y - 30

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(150, 22)
    reset:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, y)
    reset:SetText(L["Reset position"])
    reset:SetScript("OnClick", function()
        TrisThreatDB.offsetX, TrisThreatDB.offsetY, TrisThreatDB.scale = 0, 0, 1
        ns.RefreshOptions(); onLayoutChanged()
    end)
    local previewButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    previewButton:SetSize(150, 22)
    previewButton:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    previewButton:SetText(L["Preview on target"])
    previewButton:SetScript("OnClick", function()
        if not ns.ShowPreview() then print("|cffe0ad3dTrisThreat|r: " .. L["Target an enemy first."]) end
    end)
    y = y - 38

    heading(frame, "Colors", y); y = y - 26
    checkbox(frame, "Color the nameplate by threat", y, "colorBar", function() onLayoutChanged() end); y = y - 26
    checkbox(frame, "Only in instances", y, "onlyInstances"); y = y - 26
    checkbox(frame, "Hide on trivial mobs", y, "hideTrivial"); y = y - 26
    checkbox(frame, "Off-tank color", y, "offTank"); y = y - 28

    local legend = label(frame, "As tank: green = you hold it. As damage dealer or healer: red = you pulled it.", "GameFontNormalSmall")
    legend:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, y)
    legend:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    legend:SetJustifyH("LEFT")
    y = y - 32

    -- The minimap flag lives in a sub-table and is stored inverted (hide), so this box is built by hand.
    local mini = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    mini:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y)
    mini:SetSize(24, 24)
    label(frame, "Show minimap icon"):SetPoint("LEFT", mini, "RIGHT", 4, 0)
    mini:SetScript("OnClick", function(self)
        TrisThreatDB.minimap.hide = not self:GetChecked()
        if ns.ApplyMinimap then ns.ApplyMinimap() end
    end)
    frame.minimapShow = mini
    frame:SetScript("OnHide", ns.HidePreview)
    frame:SetScript("OnShow", function()
        refreshMock()
        ns.ShowPreview() -- test mode: the target gets a capsule without combat
    end)
end

local function refresh()
    if not frame then return end
    for _, fn in ipairs(controls) do fn() end
    if ns.detectedText then
        local role = ns.DetectRole()
        ns.detectedText:SetText(string.format(L["Detected: %s"], L[ROLE_TEXT[role]] or role))
    end
    refreshMock()
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
SlashCmdList["TRISTHREAT"] = function() ns.ToggleOptions() end
