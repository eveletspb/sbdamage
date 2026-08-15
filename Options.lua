local addon = SbDamage
local floor = math.floor
local max = math.max
local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber
local tostring = tostring

local CONTENT_RIGHT = 344
local COLUMN_WIDTH = 150
local AOE_HELPERS = {
    spread = {
        "Блоки близких целей разводятся по вертикали.",
        "Связь с nameplate сохраняется.",
    },
    exact = {
        "Каждый блок остаётся строго над своей целью.",
        "В плотной группе возможны пересечения.",
    },
    focus = {
        "Все попадания собираются у выбранной цели.",
        "Без выбранной цели используется запасная точка.",
    },
}

local function createLabel(parent, text, template, x, y)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function createWrappedLabel(parent, text, template, x, y, width, height)
    local label = createLabel(parent, text, template, x, y)
    label:SetWidth(width)
    label:SetHeight(height or 34)
    label:SetJustifyH("LEFT")
    return label
end

local function addTooltip(control, text)
    control.tooltipText = text
    control:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function createCheckBox(parent, name, text, x, y, onClick)
    local checkBox = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    checkBox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    _G[name .. "Text"]:SetText(text)
    checkBox:SetScript("OnClick", function(button)
        if not addon.refreshingOptions then
            onClick(button:GetChecked() and true or false)
        end
    end)
    return checkBox
end

local function defaultFormatter(value)
    return tostring(value)
end

local function pixelsFormatter(value)
    return tostring(value) .. " px"
end

local function percentFormatter(value)
    return tostring(value) .. "%"
end

local function createSlider(parent, name, text, x, y, minimum, maximum, step, onValueChanged, formatter)
    formatter = formatter or defaultFormatter
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetWidth(COLUMN_WIDTH)
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider.lowLabel = _G[name .. "Low"]
    slider.highLabel = _G[name .. "High"]
    slider.valueLabel = _G[name .. "Text"]
    slider.lowLabel:SetText(formatter(minimum))
    slider.highLabel:SetText(formatter(maximum))
    slider.valueLabel:SetText(text)
    slider:SetScript("OnValueChanged", function(_, value)
        value = floor(value / step + 0.5) * step
        slider.valueLabel:SetText(text .. ": " .. formatter(value))
        if not addon.refreshingOptions then
            onValueChanged(value)
        end
    end)
    return slider
end

local function dropdownHandler(dropdown, value, onSelect)
    return function()
        UIDropDownMenu_SetSelectedValue(dropdown, value)
        onSelect(value)
    end
end

local function createDropdown(parent, name, labelText, x, y, width, values, onSelect)
    createLabel(parent, labelText, "GameFontNormalSmall", x + 16, y)
    local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 12)
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_Initialize(dropdown, function()
        for _, option in ipairs(values) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.label
            info.value = option.value
            info.func = dropdownHandler(dropdown, option.value, onSelect)
            UIDropDownMenu_AddButton(info)
        end
    end)
    return dropdown
end

local function createButton(parent, text, x, y, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(24)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function createNumberInput(parent, name, labelText, x, y, onValueChanged)
    createLabel(parent, labelText, "GameFontNormalSmall", x, y)
    local input = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    input:SetWidth(72)
    input:SetHeight(22)
    input:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
    input:SetAutoFocus(false)
    input:SetMaxLetters(6)

    local function commitValue(frame)
        if frame.committingValue then
            return
        end
        frame.committingValue = true
        local value = tonumber(frame:GetText())
        if value then
            local rounded = value >= 0 and floor(value + 0.5) or -floor(-value + 0.5)
            onValueChanged(rounded)
        end
        addon:RefreshOptions()
        frame:ClearFocus()
        frame.committingValue = nil
    end

    input:SetScript("OnEnterPressed", commitValue)
    input:SetScript("OnEditFocusLost", commitValue)
    input:SetScript("OnEscapePressed", function(frame)
        addon:RefreshOptions()
        frame:ClearFocus()
    end)
    return input
end

local function createTextInput(parent, name, labelText, x, y, width, onValueChanged)
    createLabel(parent, labelText, "GameFontNormalSmall", x, y)
    local input = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    input:SetWidth(width)
    input:SetHeight(22)
    input:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
    input:SetAutoFocus(false)
    input:SetMaxLetters(240)
    input:SetScript("OnEnterPressed", function(frame)
        onValueChanged(frame:GetText() or "")
        frame:ClearFocus()
    end)
    input:SetScript("OnEditFocusLost", function(frame)
        onValueChanged(frame:GetText() or "")
    end)
    return input
end

local function setEnabled(control, enabled)
    if enabled then
        if control.Enable then
            control:Enable()
        elseif control.EnableMouse then
            control:EnableMouse(true)
        end
        control:SetAlpha(1)
    else
        if control.Disable then
            control:Disable()
        elseif control.EnableMouse then
            control:EnableMouse(false)
        end
        control:SetAlpha(0.45)
    end
end

local function setVisible(control, visible)
    if visible then
        control:Show()
    else
        control:Hide()
    end
end

local function createDivider(parent, x, y, width)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(0.35, 0.35, 0.35, 0.55)
    divider:SetWidth(width)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return divider
end

local function createPanel(name, title, parentName)
    local panel = CreateFrame("Frame", name, InterfaceOptionsFramePanelContainer)
    panel.name = title
    panel.parent = parentName
    panel:Hide()
    panel:SetScript("OnShow", function()
        addon:RefreshOptions()
    end)
    panel:SetScript("OnHide", function()
        addon:SetConfigMode(false)
    end)
    return panel
end

local function createPageHeader(panel, title, subtitle)
    createLabel(panel, title, "GameFontNormalLarge", 16, -16)
    createLabel(panel, subtitle, "GameFontHighlightSmall", 16, -42)
    createDivider(panel, 16, -64, CONTENT_RIGHT - 16)
end

function addon:OpenOptionsPanel(panel)
    if not panel then
        return
    end
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
    local alreadyDisplayed = InterfaceOptionsFramePanelContainer
        and InterfaceOptionsFramePanelContainer.displayedPanel == panel
    if InterfaceOptionsList_DisplayPanel and not alreadyDisplayed then
        InterfaceOptionsList_DisplayPanel(panel)
    elseif not InterfaceOptionsList_DisplayPanel and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

local function openOptionsPanel(panel)
    addon:OpenOptionsPanel(panel)
end

local colorDefinitions = {
    { key = "baseColor", label = "Выбрать цвет" },
    { key = "autoAttack", label = "Автоатака" },
    { key = "physical", label = "Физическое умение" },
    { key = "holy", label = "Свет" },
    { key = "fire", label = "Огонь" },
    { key = "nature", label = "Природа" },
    { key = "frost", label = "Лёд" },
    { key = "shadow", label = "Тьма" },
    { key = "arcane", label = "Тайная магия" },
}

function addon:GetConfiguredColor(key)
    if key == "baseColor" then
        return self.db.baseColor
    end
    return self.db.colors[key]
end

function addon:OpenColorPicker(key, button)
    local color = self:GetConfiguredColor(key)
    local previous = { color[1], color[2], color[3] }
    ColorPickerFrame:Hide()
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.opacity = 1
    ColorPickerFrame.previousValues = previous
    ColorPickerFrame.opacityFunc = nil
    ColorPickerFrame.func = function()
        local red, green, blue = ColorPickerFrame:GetColorRGB()
        color[1], color[2], color[3] = red, green, blue
        button.swatch:SetVertexColor(red, green, blue)
        addon:RefreshActiveMessageStyles()
    end
    ColorPickerFrame.cancelFunc = function(oldColor)
        local value = oldColor or previous
        color[1], color[2], color[3] = value[1], value[2], value[3]
        button.swatch:SetVertexColor(value[1], value[2], value[3])
        addon:RefreshActiveMessageStyles()
    end
    ColorPickerFrame:SetColorRGB(color[1], color[2], color[3])
    ColorPickerFrame:Show()
end

local function createColorButton(parent, definition, x, y)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(154)
    button:SetHeight(26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText("")
    button.swatch = button:CreateTexture(nil, "OVERLAY")
    button.swatch:SetWidth(18)
    button.swatch:SetHeight(18)
    button.swatch:SetPoint("LEFT", button, "LEFT", 7, 0)
    button.swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.label:SetPoint("LEFT", button.swatch, "RIGHT", 7, 0)
    button.label:SetText(definition.label)
    button:SetScript("OnClick", function()
        addon:OpenColorPicker(definition.key, button)
    end)
    button.colorKey = definition.key
    return button
end

function addon:ResetColors()
    for index = 1, 3 do
        self.db.baseColor[index] = self.defaults.baseColor[index]
    end
    for key, defaultColor in pairs(self.defaults.colors) do
        for index = 1, 3 do
            self.db.colors[key][index] = defaultColor[index]
        end
    end
    self:RefreshActiveMessageStyles()
    self:RefreshOptions()
end

function addon:ResetLayoutSettings()
    self.db.targetOffset.x = self.defaults.targetOffset.x
    self.db.targetOffset.y = self.defaults.targetOffset.y
    self.db.position.x = self.defaults.position.x
    self.db.position.y = self.defaults.position.y
    self.db.layout.columnGap = self.defaults.layout.columnGap
    self.db.layout.lineSpacing = self.defaults.layout.lineSpacing
    self.db.layout.maxPerColumn = self.defaults.layout.maxPerColumn
    self.db.layout.direction = self.defaults.layout.direction
    self:UpdateRendererSettings()
    self:RefreshOptions()
end

function addon:ResetStreamSettings()
    self.db.layout.columnGap = self.defaults.layout.columnGap
    self.db.layout.lineSpacing = self.defaults.layout.lineSpacing
    self.db.layout.maxPerColumn = self.defaults.layout.maxPerColumn
    self.db.layout.direction = self.defaults.layout.direction
    self:RefreshDamageLayouts()
    self:RefreshOptions()
end

function addon:ResetAoeSettings()
    self.db.layout.aoeMode = self.defaults.layout.aoeMode
    self.db.layout.aoeMaxShift = self.defaults.layout.aoeMaxShift
    self.db.layout.secondaryScale = self.defaults.layout.secondaryScale
    self.iconHistory = {}
    self:RefreshDamageLayouts()
    self:RefreshOptions()
end

function addon:ResetAppearanceSettings()
    self.db.font = self.defaults.font
    self.db.animation.speed = self.defaults.animation.speed
    self.db.critScale = self.defaults.critScale
    self.db.critAnimation = self.defaults.critAnimation
    self.db.icon.mode = self.defaults.icon.mode
    self.db.icon.size = self.defaults.icon.size
    self.db.icon.desaturated = self.defaults.icon.desaturated
    self.db.layout.petScale = self.defaults.layout.petScale
    self.iconHistory = {}
    self:RefreshAnimationDuration()
    self:RefreshActiveMessageStyles()
    self:RefreshOptions()
end

function addon:ResetTextSizeSettings()
    self.db.directTextSize = self.defaults.directTextSize
    self.db.periodicTextSize = self.defaults.periodicTextSize
    self:RefreshDamageLayouts()
    self:RefreshOptions()
end

function addon:ResetFilteringSettings()
    self.db.manageBlizzardDamage = self.defaults.manageBlizzardDamage
    self.db.filtering.minimumDirect = self.defaults.filtering.minimumDirect
    self.db.filtering.minimumPeriodic = self.defaults.filtering.minimumPeriodic
    self.db.filtering.showAutoAttacks = self.defaults.filtering.showAutoAttacks
    self.db.filtering.mode = self.defaults.filtering.mode
    self.db.filtering.spellIds = self.defaults.filtering.spellIds
    self.db.debug.enabled = self.defaults.debug.enabled
    self:RebuildSpellFilter()
    self:ApplyRuntimeSettings()
    self:RefreshOptions()
end

function addon:ResetFormatSettings()
    self.db.numberFormat.mode = self.defaults.numberFormat.mode
    self.db.numberFormat.decimals = self.defaults.numberFormat.decimals
    self.db.animation.fadeStart = self.defaults.animation.fadeStart
    self:RefreshAnimationDuration()
    self:RefreshActiveMessageStyles()
    self:RefreshOptions()
end

function addon:ApplyPreset(name)
    if name == "clean" then
        self.db.numberFormat.mode = "short"
        self.db.numberFormat.decimals = 1
        self.db.filtering.minimumDirect = 100
        self.db.filtering.minimumPeriodic = 50
        self.db.filtering.showAutoAttacks = false
        self.db.icon.mode = "burst"
        self.db.layout.maxPerColumn = 6
        self.db.animation.speed = 1.3
        self.db.animation.fadeStart = 0.55
    elseif name == "critical" then
        self.db.numberFormat.mode = "exact"
        self.db.filtering.minimumDirect = 0
        self.db.filtering.minimumPeriodic = 0
        self.db.filtering.showAutoAttacks = true
        self.db.critScale = 1.75
        self.db.critAnimation = "combined"
        self.db.directTextSize = 30
        self.db.periodicTextSize = 24
        self.db.icon.mode = "every"
        self.db.animation.speed = 0.9
        self.db.animation.fadeStart = 0.68
    elseif name == "classic" then
        self:ResetFilteringSettings()
        self:ResetFormatSettings()
        self:ResetAppearanceSettings()
        self:ResetTextSizeSettings()
        self:ResetStreamSettings()
        return
    else
        return
    end
    self:RebuildSpellFilter()
    self:EnforceActiveStreamLimits()
    self:RefreshAnimationDuration()
    self:RefreshActiveMessageStyles()
    self:RefreshOptions()
end

function addon:ResetAllSettings()
    local originalCVars = self.db.originalCVars
    local settings = self:ApplyDefaults({})
    settings.schemaVersion = self.defaults.schemaVersion
    settings.originalCVars = originalCVars
    SbDamageDB = settings
    self.db = settings
    self.iconHistory = {}
    self:SetConfigMode(false)
    self:HideAllMessages()
    self:ApplyRuntimeSettings()
    self:RefreshOptions()
end

function addon:RefreshOptions()
    if not self.controls or not self.db then
        return
    end

    self.refreshingOptions = true
    local controls = self.controls
    self.db.position.x, self.db.position.y = self:ClampPosition(self.db.position.x, self.db.position.y)
    controls.enabled:SetChecked(self.db.enabled)
    controls.pet:SetChecked(self.db.showPetDamage)
    controls.manageBlizzardDamage:SetChecked(self.db.manageBlizzardDamage)
    controls.targetOffsetX:SetValue(self.db.targetOffset.x)
    controls.targetOffsetY:SetValue(self.db.targetOffset.y)
    controls.columnGap:SetValue(self.db.layout.columnGap)
    controls.lineSpacing:SetValue(self.db.layout.lineSpacing)
    controls.maxPerColumn:SetValue(self.db.layout.maxPerColumn)
    controls.aoeMaxShift:SetValue(self.db.layout.aoeMaxShift)
    controls.secondaryScale:SetValue(floor(self.db.layout.secondaryScale * 100 + 0.5))
    UIDropDownMenu_SetSelectedValue(controls.movementDirection, self.db.layout.direction)
    UIDropDownMenu_SetText(
        controls.movementDirection,
        self:GetOptionLabel(self.movementDirections, self.db.layout.direction))
    UIDropDownMenu_SetSelectedValue(controls.aoeMode, self.db.layout.aoeMode)
    UIDropDownMenu_SetText(controls.aoeMode, self:GetOptionLabel(self.aoeModes, self.db.layout.aoeMode))
    controls.petScale:SetValue(floor(self.db.layout.petScale * 100 + 0.5))
    controls.positionX:SetText(tostring(self.db.position.x))
    controls.positionY:SetText(tostring(self.db.position.y))
    controls.directTextSize:SetValue(self.db.directTextSize)
    controls.periodicTextSize:SetValue(self.db.periodicTextSize)
    controls.minimumDirect:SetText(tostring(self.db.filtering.minimumDirect))
    controls.minimumPeriodic:SetText(tostring(self.db.filtering.minimumPeriodic))
    controls.showAutoAttacks:SetChecked(self.db.filtering.showAutoAttacks)
    controls.debugEnabled:SetChecked(self.db.debug.enabled)
    controls.spellIds:SetText(self.db.filtering.spellIds)
    controls.numberDecimals:SetValue(self.db.numberFormat.decimals)
    controls.animationSpeed:SetValue(floor(self.db.animation.speed * 100 + 0.5))
    controls.fadeStart:SetValue(floor(self.db.animation.fadeStart * 100 + 0.5))
    controls.iconSize:SetValue(self.db.icon.size)
    controls.desaturated:SetChecked(self.db.icon.desaturated)
    controls.schoolColors:SetChecked(self.db.colorBySchool)
    controls.critScale:SetValue(floor(self.db.critScale * 100 + 0.5))
    UIDropDownMenu_SetSelectedValue(controls.font, self.db.font)
    UIDropDownMenu_SetText(controls.font, self:GetFontLabel(self.db.font))
    UIDropDownMenu_SetSelectedValue(controls.iconMode, self.db.icon.mode)
    UIDropDownMenu_SetText(controls.iconMode, self:GetOptionLabel(self.iconModes, self.db.icon.mode))
    UIDropDownMenu_SetSelectedValue(controls.critAnimation, self.db.critAnimation)
    UIDropDownMenu_SetText(controls.critAnimation, self:GetOptionLabel(self.critAnimations, self.db.critAnimation))
    UIDropDownMenu_SetSelectedValue(controls.filterMode, self.db.filtering.mode)
    UIDropDownMenu_SetText(controls.filterMode, self:GetOptionLabel(self.filterModes, self.db.filtering.mode))
    UIDropDownMenu_SetSelectedValue(controls.numberFormat, self.db.numberFormat.mode)
    UIDropDownMenu_SetText(
        controls.numberFormat,
        self:GetOptionLabel(self.numberFormats, self.db.numberFormat.mode))
    setEnabled(controls.iconSize, self.db.icon.mode ~= "off")
    setEnabled(controls.desaturated, self.db.icon.mode ~= "off")
    setEnabled(controls.petScale, self.db.showPetDamage)
    setEnabled(controls.aoeMaxShift, self.db.layout.aoeMode == "spread")
    setEnabled(controls.spellIds, self.db.filtering.mode ~= "off")
    setEnabled(controls.numberDecimals, self.db.numberFormat.mode == "short")
    setEnabled(controls.debugStatsButton, self.db.debug.enabled)

    local helper = AOE_HELPERS[self.db.layout.aoeMode] or AOE_HELPERS.spread
    controls.aoeHelperPrimary:SetText(helper[1])
    controls.aoeHelperSecondary:SetText(helper[2])

    for index, button in ipairs(controls.colorButtons) do
        local color = self:GetConfiguredColor(button.colorKey)
        button.swatch:SetVertexColor(color[1], color[2], color[3])
        local isBaseColor = index == 1
        setEnabled(button, isBaseColor and not self.db.colorBySchool or self.db.colorBySchool)
        setVisible(button, isBaseColor and not self.db.colorBySchool or not isBaseColor and self.db.colorBySchool)
    end
    setVisible(controls.baseColorHeading, not self.db.colorBySchool)
    for _, control in ipairs(controls.schoolColorDecorations) do
        setVisible(control, self.db.colorBySchool)
    end
    self.refreshingOptions = false
end

function addon:GetFontLabel(file)
    for _, font in ipairs(self.fonts) do
        if font.file == file then
            return font.label
        end
    end
    return file
end

function addon:GetOptionLabel(options, value)
    for _, option in ipairs(options) do
        if option.value == value then
            return option.label
        end
    end
    return value
end

function addon:CreatePreviewButton(panel, x, y, previewMethod)
    local button = createButton(panel, "Показать пример", x, y, 128, function()
        addon[previewMethod or "ShowPreview"](addon)
    end)
    self.controls.previewButtons[#self.controls.previewButtons + 1] = button
    return button
end

function addon:InitializeOptions()
    if self.optionsInitialized then
        self:RefreshOptions()
        return
    end

    self.iconModes = {
        { label = "Не показывать", value = "off" },
        { label = "Серия: общая", value = "burst" },
        { label = "Серия: на цель", value = "target" },
        { label = "Каждый удар", value = "every" },
    }
    self.critAnimations = {
        { label = "Без анимации", value = "none" },
        { label = "Встряска", value = "shake" },
        { label = "Увеличение", value = "scale" },
        { label = "Комбинированная", value = "combined" },
    }
    self.movementDirections = {
        { label = "Всегда вверх", value = "up" },
        { label = "Всегда вниз", value = "down" },
        { label = "Автоматически", value = "auto" },
    }
    self.aoeModes = {
        { label = "Умное разнесение", value = "spread" },
        { label = "Строго над целями", value = "exact" },
        { label = "У выбранной цели", value = "focus" },
    }
    self.filterModes = {
        { label = "Не фильтровать", value = "off" },
        { label = "Чёрный список", value = "blacklist" },
        { label = "Белый список", value = "whitelist" },
    }
    self.numberFormats = {
        { label = "Точное: 123456", value = "exact" },
        { label = "Разряды: 123 456", value = "grouped" },
        { label = "Короткое: 123.5k", value = "short" },
    }

    local fontOptions = {}
    for _, font in ipairs(self.fonts) do
        fontOptions[#fontOptions + 1] = { label = font.label, value = font.file }
    end

    local rootPanel = createPanel("SbDamageOptionsPanel", "SbDamage")
    local layoutPanel = createPanel("SbDamageLayoutOptionsPanel", "Компоновка", "SbDamage")
    local aoePanel = createPanel("SbDamageAoeOptionsPanel", "Несколько целей", "SbDamage")
    local appearancePanel = createPanel("SbDamageAppearanceOptionsPanel", "Оформление", "SbDamage")
    local textSizePanel = createPanel("SbDamageTextSizeOptionsPanel", "Размер текста", "SbDamage")
    local colorsPanel = createPanel("SbDamageColorsOptionsPanel", "Цвета", "SbDamage")
    local filtersPanel = createPanel("SbDamageFiltersOptionsPanel", "Фильтры", "SbDamage")
    local formatPanel = createPanel("SbDamageFormatOptionsPanel", "Формат и время", "SbDamage")
    local presetsPanel = createPanel("SbDamagePresetsOptionsPanel", "Пресеты", "SbDamage")
    local controls = {
        colorButtons = {},
        previewButtons = {},
        schoolColorDecorations = {},
    }
    self.controls = controls

    createPageHeader(rootPanel, "SbDamage", "Урон игрока и питомца · WoW 3.3.5a")
    self:CreatePreviewButton(rootPanel, 216, -14)
    createLabel(rootPanel, "Основное", "GameFontNormal", 16, -84)
    controls.enabled = createCheckBox(rootPanel, "SbDamageEnabledCheck", "Включить SbDamage", 16, -100, function(value)
        addon:SetEnabled(value)
    end)
    controls.pet = createCheckBox(rootPanel, "SbDamagePetCheck", "Показывать урон питомца", 16, -130, function(value)
        addon.db.showPetDamage = value
        addon:RefreshOptions()
    end)
    controls.manageBlizzardDamage = createCheckBox(
        rootPanel,
        "SbDamageManageBlizzardDamageCheck",
        "Отключать стандартные цифры урона",
        16,
        -160,
        function(value)
            addon.db.manageBlizzardDamage = value
            addon:ApplyRuntimeSettings()
        end)
    createLabel(rootPanel, "Как отображается урон", "GameFontNormal", 16, -202)
    createLabel(rootPanel, "Слева — периодический · По центру — прямой · Справа — питомец", "GameFontHighlightSmall", 16, -224)
    createLabel(rootPanel, "Для привязки к целям включите nameplate клавишей V.", "GameFontDisableSmall", 16, -244)

    controls.openLayout = createButton(rootPanel, "Компоновка", 16, -264, 160, function()
        openOptionsPanel(layoutPanel)
    end)
    controls.openAoe = createButton(rootPanel, "Несколько целей", 184, -264, 160, function()
        openOptionsPanel(aoePanel)
    end)
    controls.openAppearance = createButton(rootPanel, "Оформление", 16, -294, 160, function()
        openOptionsPanel(appearancePanel)
    end)
    controls.openTextSize = createButton(rootPanel, "Размер прямого/DoT", 184, -294, 160, function()
        openOptionsPanel(textSizePanel)
    end)
    controls.openColors = createButton(rootPanel, "Цвета", 16, -324, 160, function()
        openOptionsPanel(colorsPanel)
    end)
    controls.openFilters = createButton(rootPanel, "Фильтры", 184, -324, 160, function()
        openOptionsPanel(filtersPanel)
    end)
    controls.openFormat = createButton(rootPanel, "Формат и время", 16, -354, 160, function()
        openOptionsPanel(formatPanel)
    end)
    controls.openPresets = createButton(rootPanel, "Пресеты", 184, -354, 76, function()
        openOptionsPanel(presetsPanel)
    end)
    controls.resetAll = createButton(rootPanel, "Сброс…", 266, -354, 78, function()
        StaticPopup_Show("SBDAMAGE_RESET_ALL")
    end)
    rootPanel.default = function()
        StaticPopup_Show("SBDAMAGE_RESET_ALL")
    end

    createPageHeader(layoutPanel, "Компоновка", "Положение цифр над целью и на экране")
    self:CreatePreviewButton(layoutPanel, 216, -14)
    createLabel(layoutPanel, "Над полоской цели", "GameFontNormal", 16, -84)
    controls.targetOffsetX = createSlider(layoutPanel, "SbDamageTargetOffsetXSlider", "Смещение X", 18, -112, -120, 120, 1, function(value)
        addon.db.targetOffset.x = value
        addon:RefreshDamageLayouts()
    end, pixelsFormatter)
    controls.targetOffsetY = createSlider(layoutPanel, "SbDamageTargetOffsetYSlider", "Смещение Y", 18, -166, -20, 180, 1, function(value)
        addon.db.targetOffset.y = value
        addon:RefreshDamageLayouts()
    end, pixelsFormatter)
    createButton(layoutPanel, "Сбросить", 16, -220, 104, function()
        addon.db.targetOffset.x = addon.defaults.targetOffset.x
        addon.db.targetOffset.y = addon.defaults.targetOffset.y
        addon:RefreshDamageLayouts()
        addon:RefreshOptions()
    end)

    createLabel(layoutPanel, "Запасная позиция", "GameFontNormal", 16, -266)
    createLabel(layoutPanel, "Когда nameplate цели не виден", "GameFontDisableSmall", 16, -286)
    controls.positionX = createNumberInput(layoutPanel, "SbDamageFallbackXInput", "X", 16, -310, function(value)
        addon.db.position.x = value
        addon:UpdateRendererSettings()
    end)
    controls.positionY = createNumberInput(layoutPanel, "SbDamageFallbackYInput", "Y", 92, -310, function(value)
        addon.db.position.y = value
        addon:UpdateRendererSettings()
    end)
    local moveButton = createButton(layoutPanel, "Переместить", 176, -326, 108, function()
        addon:ToggleConfigMode()
    end)
    controls.moveButton = moveButton
    createButton(layoutPanel, "Сброс", 290, -326, 54, function()
        addon.db.position.x = addon.defaults.position.x
        addon.db.position.y = addon.defaults.position.y
        addon:UpdateRendererSettings()
        addon:RefreshOptions()
    end)

    createLabel(layoutPanel, "Движение и колонки", "GameFontNormal", 190, -84)
    controls.movementDirection = createDropdown(
        layoutPanel,
        "SbDamageMovementDirectionDropdown",
        "Направление",
        174,
        -106,
        126,
        self.movementDirections,
        function(value)
            addon.db.layout.direction = value
            addon:RefreshDamageLayouts()
        end)
    controls.columnGap = createSlider(layoutPanel, "SbDamageColumnGapSlider", "Между колонками", 194, -168, 40, 100, 2, function(value)
        addon.db.layout.columnGap = value
        addon:RefreshDamageLayouts()
    end, pixelsFormatter)
    controls.lineSpacing = createSlider(layoutPanel, "SbDamageLineSpacingSlider", "Между цифрами", 194, -220, 0, 12, 1, function(value)
        addon.db.layout.lineSpacing = value
        addon:RefreshDamageLayouts()
    end, pixelsFormatter)
    controls.maxPerColumn = createSlider(layoutPanel, "SbDamageMaxPerColumnSlider", "Цифр в колонке", 194, -272, 3, 12, 1, function(value)
        addon.db.layout.maxPerColumn = value
        addon:EnforceActiveStreamLimits()
        addon:RefreshDamageLayouts()
    end)
    addTooltip(controls.maxPerColumn, "При превышении лимита самая старая цифра исчезает раньше.")
    createButton(layoutPanel, "Сбросить", 190, -354, 104, function()
        addon:ResetStreamSettings()
    end)
    layoutPanel.default = function()
        addon:ResetLayoutSettings()
    end

    createPageHeader(aoePanel, "Несколько целей", "AoE и урон вне выбранной цели")
    self:CreatePreviewButton(aoePanel, 216, -14, "ShowAoePreview")
    createLabel(aoePanel, "Расположение", "GameFontNormal", 16, -84)
    controls.aoeMode = createDropdown(
        aoePanel,
        "SbDamageAoeModeDropdown",
        "Режим",
        0,
        -106,
        286,
        self.aoeModes,
        function(value)
            addon.db.layout.aoeMode = value
            addon:RefreshDamageLayouts()
            addon:RefreshOptions()
        end)
    controls.aoeHelperPrimary = createLabel(aoePanel, "", "GameFontHighlightSmall", 16, -166)
    controls.aoeHelperSecondary = createLabel(aoePanel, "", "GameFontDisableSmall", 16, -186)

    createLabel(aoePanel, "Разнесение", "GameFontNormal", 16, -224)
    controls.aoeMaxShift = createSlider(
        aoePanel,
        "SbDamageAoeMaxShiftSlider",
        "Макс. сдвиг",
        18,
        -252,
        0,
        120,
        12,
        function(value)
            addon.db.layout.aoeMaxShift = value
            addon:RefreshDamageLayouts()
        end,
        pixelsFormatter)
    createLabel(aoePanel, "Дополнительные цели", "GameFontNormal", 190, -224)
    controls.secondaryScale = createSlider(
        aoePanel,
        "SbDamageSecondaryScaleSlider",
        "Размер цифр",
        194,
        -252,
        65,
        100,
        5,
        function(value)
            addon.db.layout.secondaryScale = value / 100
            addon:RefreshDamageLayouts()
        end,
        percentFormatter)
    createLabel(aoePanel, "Иконки AoE настраиваются на странице оформления.", "GameFontDisableSmall", 16, -316)
    createButton(aoePanel, "Настроить иконки", 16, -340, 160, function()
        openOptionsPanel(appearancePanel)
    end)
    aoePanel.default = function()
        addon:ResetAoeSettings()
    end

    createPageHeader(appearancePanel, "Оформление", "Шрифт, иконки, крит и питомец")
    self:CreatePreviewButton(appearancePanel, 216, -14)
    createLabel(appearancePanel, "Общие параметры", "GameFontNormal", 16, -84)
    controls.font = createDropdown(appearancePanel, "SbDamageFontDropdown", "Шрифт", 0, -104, 126, fontOptions, function(value)
        addon.db.font = value
        addon:RefreshActiveMessageStyles()
    end)
    controls.animationSpeed = createSlider(
        appearancePanel,
        "SbDamageAnimationSpeedSlider",
        "Скорость анимации",
        18,
        -166,
        50,
        200,
        10,
        function(value)
            addon.db.animation.speed = value / 100
            addon:RefreshAnimationDuration()
        end,
        percentFormatter)
    addTooltip(controls.animationSpeed,
        "100% — обычная скорость; 50% — вдвое медленнее; 200% — вдвое быстрее.")

    createLabel(appearancePanel, "Критический урон", "GameFontNormal", 16, -218)
    controls.critAnimation = createDropdown(appearancePanel, "SbDamageCritDropdown", "Анимация", 0, -238, 126, self.critAnimations, function(value)
        addon.db.critAnimation = value
        addon:RefreshDamageLayouts()
    end)
    controls.critScale = createSlider(appearancePanel, "SbDamageCritScaleSlider", "Размер крита", 18, -300, 100, 200, 5, function(value)
        addon.db.critScale = value / 100
        addon:RefreshDamageLayouts()
    end, percentFormatter)
    addTooltip(controls.critScale,
        "Масштабирует цифру и иконку. Анимация увеличения кратковременно добавляет ещё до 25%.")

    createLabel(appearancePanel, "Иконки способностей", "GameFontNormal", 190, -84)
    controls.iconMode = createDropdown(appearancePanel, "SbDamageIconModeDropdown", "Режим", 174, -104, 126, self.iconModes, function(value)
        addon.db.icon.mode = value
        addon.iconHistory = {}
        addon:RefreshActiveMessageStyles()
        addon:RefreshOptions()
    end)
    addTooltip(controls.iconMode,
        "Серия объединяет только повтор иконки одной способности за 0,18–0,30 с. Все цифры остаются отдельными.")
    createLabel(appearancePanel, "Повтор: 0,2–0,3 с.", "GameFontDisableSmall", 190, -160)
    controls.iconSize = createSlider(appearancePanel, "SbDamageIconSizeSlider", "Размер иконки", 194, -186, 12, 48, 1, function(value)
        addon.db.icon.size = value
        addon:RefreshActiveMessageStyles()
    end, pixelsFormatter)
    controls.desaturated = createCheckBox(appearancePanel, "SbDamageDesaturateCheck", "Обесцвечивать", 190, -240, function(value)
        addon.db.icon.desaturated = value
        addon:RefreshActiveMessageStyles()
    end)

    createLabel(appearancePanel, "Урон питомца", "GameFontNormal", 190, -286)
    controls.petScale = createSlider(appearancePanel, "SbDamagePetScaleSlider", "Размер", 194, -318, 50, 100, 5, function(value)
        addon.db.layout.petScale = value / 100
        addon:RefreshDamageLayouts()
    end, percentFormatter)
    addTooltip(controls.petScale, "Доступно, когда на главной странице включён урон питомца.")
    appearancePanel.default = function()
        addon:ResetAppearanceSettings()
    end

    createPageHeader(textSizePanel, "Размер текста", "Независимый размер прямого и периодического урона")
    self:CreatePreviewButton(textSizePanel, 216, -14)
    createLabel(textSizePanel, "Прямой урон", "GameFontNormal", 16, -84)
    createLabel(textSizePanel, "Основные умения, автоатаки и обычные промахи", "GameFontHighlightSmall", 16, -106)
    controls.directTextSize = createSlider(
        textSizePanel,
        "SbDamageDirectTextSizeSlider",
        "Размер текста",
        18,
        -142,
        14,
        48,
        1,
        function(value)
            addon.db.directTextSize = value
            addon:RefreshDamageLayouts()
        end,
        pixelsFormatter)
    createDivider(textSizePanel, 16, -210, CONTENT_RIGHT - 16)
    createLabel(textSizePanel, "Периодический урон", "GameFontNormal", 16, -236)
    createLabel(textSizePanel, "Периодические эффекты и их промахи", "GameFontHighlightSmall", 16, -258)
    controls.periodicTextSize = createSlider(
        textSizePanel,
        "SbDamagePeriodicTextSizeSlider",
        "Размер текста",
        18,
        -294,
        14,
        48,
        1,
        function(value)
            addon.db.periodicTextSize = value
            addon:RefreshDamageLayouts()
        end,
        pixelsFormatter)
    addTooltip(controls.periodicTextSize,
        "Периодический урон питомца использует этот размер и дополнительный масштаб питомца.")
    createButton(textSizePanel, "Сбросить размеры", 16, -354, 148, function()
        addon:ResetTextSizeSettings()
    end)
    textSizePanel.default = function()
        addon:ResetTextSizeSettings()
    end

    createPageHeader(filtersPanel, "Фильтры", "Пороги, автоатаки и списки способностей")
    self:CreatePreviewButton(filtersPanel, 216, -14)
    createLabel(filtersPanel, "Минимальный урон", "GameFontNormal", 16, -84)
    controls.minimumDirect = createNumberInput(
        filtersPanel,
        "SbDamageMinimumDirectInput",
        "Прямой",
        16,
        -108,
        function(value)
            addon.db.filtering.minimumDirect = max(0, value)
            addon:RefreshOptions()
        end)
    controls.minimumPeriodic = createNumberInput(
        filtersPanel,
        "SbDamageMinimumPeriodicInput",
        "Периодический",
        104,
        -108,
        function(value)
            addon.db.filtering.minimumPeriodic = max(0, value)
            addon:RefreshOptions()
        end)
    createLabel(filtersPanel, "Нулевое значение отключает порог.", "GameFontDisableSmall", 16, -160)
    controls.showAutoAttacks = createCheckBox(
        filtersPanel,
        "SbDamageShowAutoAttacksCheck",
        "Показывать автоатаки",
        16,
        -188,
        function(value)
            addon.db.filtering.showAutoAttacks = value
        end)
    controls.debugEnabled = createCheckBox(
        filtersPanel,
        "SbDamageDebugEnabledCheck",
        "Собирать debug-счётчики",
        16,
        -218,
        function(value)
            addon.db.debug.enabled = value
            addon:ResetDebugStats()
            addon:RefreshOptions()
        end)

    createLabel(filtersPanel, "Фильтр spell ID", "GameFontNormal", 190, -84)
    controls.filterMode = createDropdown(
        filtersPanel,
        "SbDamageFilterModeDropdown",
        "Режим",
        174,
        -106,
        154,
        self.filterModes,
        function(value)
            addon.db.filtering.mode = value
            addon:RebuildSpellFilter()
            addon:RefreshOptions()
        end)
    controls.spellIds = createTextInput(
        filtersPanel,
        "SbDamageSpellIdsInput",
        "ID через запятую или пробел",
        190,
        -178,
        154,
        function(value)
            addon.db.filtering.spellIds = value
            addon:RebuildSpellFilter()
            addon:RefreshOptions()
        end)
    createWrappedLabel(filtersPanel, "Blacklist скрывает указанные ID.", "GameFontDisableSmall", 190, -230, 154, 18)
    createWrappedLabel(filtersPanel, "Whitelist показывает только указанные ID.", "GameFontDisableSmall", 190, -250, 154, 18)
    controls.debugStatsButton = createButton(filtersPanel, "Показать статистику", 190, -286, 154, function()
        addon:PrintDebugStats()
    end)
    createButton(filtersPanel, "Сбросить фильтры", 16, -340, 154, function()
        addon:ResetFilteringSettings()
    end)
    filtersPanel.default = function()
        addon:ResetFilteringSettings()
    end

    createPageHeader(formatPanel, "Формат и время", "Числа и начало исчезновения")
    self:CreatePreviewButton(formatPanel, 216, -14)
    createLabel(formatPanel, "Формат чисел", "GameFontNormal", 16, -84)
    controls.numberFormat = createDropdown(
        formatPanel,
        "SbDamageNumberFormatDropdown",
        "Вид",
        0,
        -106,
        154,
        self.numberFormats,
        function(value)
            addon.db.numberFormat.mode = value
            addon:RefreshActiveMessageStyles()
            addon:RefreshOptions()
        end)
    controls.numberDecimals = createSlider(
        formatPanel,
        "SbDamageNumberDecimalsSlider",
        "Знаков после точки",
        18,
        -180,
        0,
        2,
        1,
        function(value)
            addon.db.numberFormat.decimals = value
            addon:RefreshActiveMessageStyles()
        end)
    addTooltip(controls.numberDecimals, "Используется только для короткого формата k/m.")

    createLabel(formatPanel, "Исчезновение", "GameFontNormal", 190, -84)
    controls.fadeStart = createSlider(
        formatPanel,
        "SbDamageFadeStartSlider",
        "Начало исчезновения",
        194,
        -184,
        20,
        90,
        1,
        function(value)
            addon.db.animation.fadeStart = value / 100
        end,
        percentFormatter)
    createWrappedLabel(formatPanel, "Скорость движения находится на странице оформления.", "GameFontDisableSmall", 190, -250, 154, 34)
    createWrappedLabel(formatPanel, "Fade определяет долю пути до исчезновения.", "GameFontDisableSmall", 190, -286, 154, 34)
    createButton(formatPanel, "Сбросить формат и время", 16, -340, 174, function()
        addon:ResetFormatSettings()
    end)
    formatPanel.default = function()
        addon:ResetFormatSettings()
    end

    createPageHeader(presetsPanel, "Пресеты", "Готовые стартовые наборы настроек")
    self:CreatePreviewButton(presetsPanel, 216, -14)
    createWrappedLabel(
        presetsPanel,
        "Пресеты изменяют оформление, фильтры, размеры и компоновку.",
        "GameFontHighlightSmall",
        16,
        -84,
        328,
        34)
    controls.presetClassic = createButton(presetsPanel, "Классический", 16, -126, 154, function()
        addon:ApplyPreset("classic")
    end)
    createWrappedLabel(presetsPanel, "Стандартные значения без фильтрации.", "GameFontDisableSmall", 184, -126, 160, 34)
    controls.presetClean = createButton(presetsPanel, "Чистый экран", 16, -186, 154, function()
        addon:ApplyPreset("clean")
    end)
    createWrappedLabel(presetsPanel, "Короткие числа, меньше тиков, без автоатак.", "GameFontDisableSmall", 184, -186, 160, 34)
    controls.presetCritical = createButton(presetsPanel, "Яркие криты", 16, -246, 154, function()
        addon:ApplyPreset("critical")
    end)
    createWrappedLabel(presetsPanel, "Крупные криты и иконка каждого попадания.", "GameFontDisableSmall", 184, -246, 160, 34)
    presetsPanel.default = function()
        addon:ApplyPreset("classic")
    end

    createPageHeader(colorsPanel, "Цвета урона", "Палитра по физическому типу и школе магии")
    self:CreatePreviewButton(colorsPanel, 216, -14)
    controls.schoolColors = createCheckBox(colorsPanel, "SbDamageSchoolColorCheck", "Красить по школе урона", 16, -84, function(value)
        addon.db.colorBySchool = value
        addon:RefreshActiveMessageStyles()
        addon:RefreshOptions()
    end)
    controls.baseColorHeading = createLabel(colorsPanel, "Единый цвет", "GameFontNormal", 16, -132)
    controls.schoolColorDecorations[1] = createLabel(colorsPanel, "Физический урон", "GameFontNormal", 16, -132)
    controls.schoolColorDecorations[2] = createLabel(colorsPanel, "Магия", "GameFontNormal", 16, -204)

    controls.colorButtons[1] = createColorButton(colorsPanel, colorDefinitions[1], 16, -158)
    controls.colorButtons[2] = createColorButton(colorsPanel, colorDefinitions[2], 16, -158)
    controls.colorButtons[3] = createColorButton(colorsPanel, colorDefinitions[3], 190, -158)
    local magicPositions = {
        { 16, -230 }, { 190, -230 },
        { 16, -264 }, { 190, -264 },
        { 16, -298 }, { 190, -298 },
    }
    for index = 4, #colorDefinitions do
        local position = magicPositions[index - 3]
        controls.colorButtons[index] = createColorButton(colorsPanel, colorDefinitions[index], position[1], position[2])
    end
    createButton(colorsPanel, "Вернуть стандартную палитру", 16, -340, 218, function()
        addon:ResetColors()
    end)
    colorsPanel.default = function()
        addon.db.colorBySchool = addon.defaults.colorBySchool
        addon:ResetColors()
    end

    StaticPopupDialogs.SBDAMAGE_RESET_ALL = {
        text = "Сбросить все настройки SbDamage?",
        button1 = YES or "Да",
        button2 = NO or "Нет",
        OnAccept = function()
            addon:ResetAllSettings()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    InterfaceOptions_AddCategory(rootPanel)
    InterfaceOptions_AddCategory(layoutPanel)
    InterfaceOptions_AddCategory(aoePanel)
    InterfaceOptions_AddCategory(appearancePanel)
    InterfaceOptions_AddCategory(textSizePanel)
    InterfaceOptions_AddCategory(colorsPanel)
    InterfaceOptions_AddCategory(filtersPanel)
    InterfaceOptions_AddCategory(formatPanel)
    InterfaceOptions_AddCategory(presetsPanel)
    self.optionsPanel = rootPanel
    self.layoutOptionsPanel = layoutPanel
    self.aoeOptionsPanel = aoePanel
    self.appearanceOptionsPanel = appearancePanel
    self.textSizeOptionsPanel = textSizePanel
    self.colorsOptionsPanel = colorsPanel
    self.filtersOptionsPanel = filtersPanel
    self.formatOptionsPanel = formatPanel
    self.presetsOptionsPanel = presetsPanel
    self.optionsScroll = nil

    SLASH_SBDAMAGE1 = "/sbdamage"
    SLASH_SBDAMAGE2 = "/sbd"
    SlashCmdList.SBDAMAGE = function(command)
        command = command and command:lower() or ""
        if command == "test" then
            addon:ShowPreview()
        elseif command == "move" then
            addon:ToggleConfigMode()
        elseif command == "debug" then
            addon:PrintDebugStats()
        elseif command == "debug reset" then
            addon:ResetDebugStats()
        else
            openOptionsPanel(rootPanel)
        end
    end

    self.optionsInitialized = true
    self:RefreshOptions()
end
