local loadedAddonName = ...

SbDamage = SbDamage or {}

local addon = SbDamage
local floor = math.floor
local max = math.max
local min = math.min
local pairs = pairs
local tostring = tostring
local type = type

addon.name = type(loadedAddonName) == "string" and loadedAddonName or "SbDamage"
addon.version = "1.6.8"
addon.addonPath = "Interface\\AddOns\\" .. addon.name .. "\\"

function addon:SetRuntimeAddonName(name)
    if type(name) ~= "string" or name == "" then
        return
    end
    self.name = name
    self.addonPath = "Interface\\AddOns\\" .. name .. "\\"
end

function addon:IsOwnAddon(name)
    if name == self.name or name == "SbDamage" or name == "NiceDamage" then
        return true
    end
    if type(name) ~= "string" or not GetAddOnMetadata then
        return false
    end
    local ok, title = pcall(GetAddOnMetadata, name, "Title")
    return ok and title == "SbDamage"
end

addon.fonts = {
    { label = "SbDamage", file = "font.ttf" },
    { label = "Font 2", file = "font2.ttf" },
    { label = "Font 3", file = "font3.ttf" },
    { label = "Font 4", file = "font4.ttf" },
    { label = "Font 5", file = "font5.ttf" },
    { label = "Font 6", file = "font6.ttf" },
    { label = "Font 7", file = "font7.ttf" },
    { label = "Font 8", file = "font8.ttf" },
    { label = "Default WoW", file = "defaultwowfont.ttf" },
}

addon.defaults = {
    schemaVersion = 6,
    enabled = true,
    showPetDamage = true,
    manageBlizzardDamage = true,
    position = {
        x = 0,
        y = 80,
    },
    targetOffset = {
        x = 0,
        y = 36,
    },
    layout = {
        columnGap = 64,
        lineSpacing = 4,
        maxPerColumn = 8,
        petScale = 0.75,
        direction = "up",
        aoeMode = "spread",
        aoeMaxShift = 72,
        secondaryScale = 0.85,
    },
    font = "font.ttf",
    directTextSize = 28,
    periodicTextSize = 28,
    animation = {
        speed = 1,
        fadeStart = 0.62,
    },
    critScale = 1.45,
    critAnimation = "combined",
    icon = {
        mode = "burst",
        size = 24,
        desaturated = false,
    },
    filtering = {
        minimumDirect = 0,
        minimumPeriodic = 0,
        showAutoAttacks = true,
        mode = "off",
        spellIds = "",
    },
    numberFormat = {
        mode = "exact",
        decimals = 1,
    },
    debug = {
        enabled = false,
    },
    colorBySchool = true,
    baseColor = { 1, 1, 1 },
    colors = {
        autoAttack = { 1, 1, 1 },
        physical = { 1, 0.82, 0 },
        holy = { 1, 0.9, 0.5 },
        fire = { 1, 0.25, 0 },
        nature = { 0.3, 1, 0.3 },
        frost = { 0.3, 0.75, 1 },
        shadow = { 0.62, 0.32, 0.82 },
        arcane = { 1, 0.5, 1 },
    },
}

local schoolColors = {
    { mask = 1, key = "physical" },
    { mask = 2, key = "holy" },
    { mask = 4, key = "fire" },
    { mask = 8, key = "nature" },
    { mask = 16, key = "frost" },
    { mask = 32, key = "shadow" },
    { mask = 64, key = "arcane" },
}

local function bitBand(left, right)
    if bit and bit.band then
        return bit.band(left, right)
    end

    local result = 0
    local place = 1
    while left > 0 and right > 0 do
        if left % 2 == 1 and right % 2 == 1 then
            result = result + place
        end
        left = math.floor(left / 2)
        right = math.floor(right / 2)
        place = place * 2
    end
    return result
end

local function copyDefaults(target, defaults)
    for key, defaultValue in pairs(defaults) do
        if type(defaultValue) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            copyDefaults(target[key], defaultValue)
        elseif target[key] == nil then
            target[key] = defaultValue
        end
    end
    return target
end

function addon:ApplyDefaults(settings)
    return copyDefaults(settings or {}, self.defaults)
end

local function clampNumber(value, defaultValue, minimum, maximum)
    if type(value) ~= "number" then
        return defaultValue
    end
    return min(maximum, max(minimum, value))
end

local function validValue(value, allowed, defaultValue)
    return allowed[value] and value or defaultValue
end

local function normalizeSpellIds(value)
    local ids = {}
    local seen = {}
    for token in tostring(value or ""):gmatch("%d+") do
        local spellId = tonumber(token)
        if spellId and spellId > 0 and not seen[spellId] then
            seen[spellId] = true
            ids[#ids + 1] = spellId
        end
    end
    table.sort(ids)
    for index, spellId in ipairs(ids) do
        ids[index] = tostring(spellId)
    end
    return table.concat(ids, ", ")
end

local function sanitizeColor(color, defaultColor)
    for index = 1, 3 do
        color[index] = clampNumber(color[index], defaultColor[index], 0, 1)
    end
end

function addon:SanitizeSettings(settings)
    settings = self:ApplyDefaults(settings or {})
    settings.enabled = settings.enabled ~= false
    settings.showPetDamage = settings.showPetDamage ~= false
    settings.manageBlizzardDamage = settings.manageBlizzardDamage ~= false
    settings.position.x = clampNumber(settings.position.x, self.defaults.position.x, -10000, 10000)
    settings.position.y = clampNumber(settings.position.y, self.defaults.position.y, -10000, 10000)
    settings.targetOffset.x = clampNumber(settings.targetOffset.x, self.defaults.targetOffset.x, -120, 120)
    settings.targetOffset.y = clampNumber(settings.targetOffset.y, self.defaults.targetOffset.y, -20, 180)
    settings.directTextSize = clampNumber(settings.directTextSize, self.defaults.directTextSize, 14, 48)
    settings.periodicTextSize = clampNumber(settings.periodicTextSize, self.defaults.periodicTextSize, 14, 48)
    settings.animation.speed = clampNumber(settings.animation.speed, self.defaults.animation.speed, 0.5, 2)
    settings.animation.fadeStart = clampNumber(settings.animation.fadeStart, self.defaults.animation.fadeStart, 0.2, 0.9)
    settings.critScale = clampNumber(settings.critScale, self.defaults.critScale, 1, 2)
    settings.critAnimation = validValue(settings.critAnimation, {
        none = true, shake = true, scale = true, combined = true,
    }, self.defaults.critAnimation)

    local knownFont = false
    for _, font in ipairs(self.fonts) do
        if settings.font == font.file then
            knownFont = true
            break
        end
    end
    if not knownFont then
        settings.font = self.defaults.font
    end

    settings.layout.columnGap = clampNumber(settings.layout.columnGap, self.defaults.layout.columnGap, 0, 120)
    settings.layout.lineSpacing = clampNumber(settings.layout.lineSpacing, self.defaults.layout.lineSpacing, 0, 20)
    settings.layout.maxPerColumn = clampNumber(settings.layout.maxPerColumn, self.defaults.layout.maxPerColumn, 3, 12)
    settings.layout.petScale = clampNumber(settings.layout.petScale, self.defaults.layout.petScale, 0.5, 1)
    settings.layout.aoeMaxShift = clampNumber(settings.layout.aoeMaxShift, self.defaults.layout.aoeMaxShift, 0, 120)
    settings.layout.secondaryScale = clampNumber(settings.layout.secondaryScale, self.defaults.layout.secondaryScale, 0.5, 1)
    settings.layout.direction = validValue(settings.layout.direction, {
        up = true, down = true, auto = true,
    }, self.defaults.layout.direction)
    settings.layout.aoeMode = validValue(settings.layout.aoeMode, {
        spread = true, exact = true, focus = true,
    }, self.defaults.layout.aoeMode)

    settings.icon.mode = validValue(settings.icon.mode, {
        off = true, burst = true, target = true, every = true,
    }, self.defaults.icon.mode)
    settings.icon.size = clampNumber(settings.icon.size, self.defaults.icon.size, 12, 48)
    settings.icon.desaturated = settings.icon.desaturated == true

    settings.filtering.minimumDirect = clampNumber(settings.filtering.minimumDirect, 0, 0, 99999999)
    settings.filtering.minimumPeriodic = clampNumber(settings.filtering.minimumPeriodic, 0, 0, 99999999)
    settings.filtering.showAutoAttacks = settings.filtering.showAutoAttacks ~= false
    settings.filtering.mode = validValue(settings.filtering.mode, {
        off = true, blacklist = true, whitelist = true,
    }, self.defaults.filtering.mode)
    settings.filtering.spellIds = normalizeSpellIds(settings.filtering.spellIds)
    settings.numberFormat.mode = validValue(settings.numberFormat.mode, {
        exact = true, grouped = true, short = true,
    }, self.defaults.numberFormat.mode)
    settings.numberFormat.decimals = floor(clampNumber(
        settings.numberFormat.decimals, self.defaults.numberFormat.decimals, 0, 2) + 0.5)
    settings.debug.enabled = settings.debug.enabled == true
    settings.colorBySchool = settings.colorBySchool ~= false
    sanitizeColor(settings.baseColor, self.defaults.baseColor)
    for key, defaultColor in pairs(self.defaults.colors) do
        sanitizeColor(settings.colors[key], defaultColor)
    end
    if type(settings.originalCVars) ~= "table" then
        settings.originalCVars = nil
    end
    return settings
end

function addon:FormatDamageAmount(amount)
    amount = floor((amount or 0) + 0.5)
    local format = self.db and self.db.numberFormat or self.defaults.numberFormat
    if format.mode == "short" then
        local divisor, suffix
        if amount >= 1000000 then
            divisor, suffix = 1000000, "m"
        elseif amount >= 1000 then
            divisor, suffix = 1000, "k"
        end
        if divisor then
            local decimals = format.decimals or 0
            local value = string.format("%." .. decimals .. "f", amount / divisor)
            value = value:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
            return value .. suffix
        end
    elseif format.mode == "grouped" then
        local value = tostring(amount)
        while true do
            local grouped, replacements = value:gsub("^(%-?%d+)(%d%d%d)", "%1 %2")
            value = grouped
            if replacements == 0 then
                break
            end
        end
        return value
    end
    return tostring(amount)
end

function addon:RebuildSpellFilter()
    self.spellFilter = {}
    local filtering = self.db and self.db.filtering or self.defaults.filtering
    filtering.spellIds = normalizeSpellIds(filtering.spellIds)
    self.spellFilterSource = filtering.spellIds
    for token in filtering.spellIds:gmatch("%d+") do
        self.spellFilter[tonumber(token)] = true
    end
end

function addon:ShouldDisplayDamage(damage)
    local filtering = self.db and self.db.filtering or self.defaults.filtering
    if damage.damageKind == "autoAttack" and not filtering.showAutoAttacks then
        return false
    end
    if damage.amount then
        local minimum = damage.periodic and filtering.minimumPeriodic or filtering.minimumDirect
        if damage.amount < minimum then
            return false
        end
    end
    if filtering.mode ~= "off" then
        if not self.spellFilter or self.spellFilterSource ~= filtering.spellIds then
            self:RebuildSpellFilter()
        end
        local listed = self.spellFilter[damage.spellId] == true
        if filtering.mode == "blacklist" and listed then
            return false
        end
        if filtering.mode == "whitelist" and not listed then
            return false
        end
    end
    return true
end

function addon:MigrateSettings(settings)
    settings = settings or {}
    if type(settings.textSize) == "number" then
        if settings.directTextSize == nil then
            settings.directTextSize = settings.textSize
        end
        if settings.periodicTextSize == nil then
            settings.periodicTextSize = settings.textSize
        end
        settings.textSize = nil
    end
    if type(settings.animation) ~= "table" then
        local speed = type(settings.animationSpeed) == "number" and max(0.1, settings.animationSpeed) or 1
        settings.animation = {
            speed = speed,
            fadeStart = 0.62,
        }
    elseif type(settings.animation.speed) ~= "number" then
        local duration = type(settings.animation.duration) == "number" and max(0.1, settings.animation.duration) or 1.15
        settings.animation.speed = 1.15 / duration
    end
    settings.animation.duration = nil
    settings.animationSpeed = nil
    return settings
end

function addon:GetFontPath()
    local file = self.db and self.db.font or self.defaults.font
    return self.addonPath .. file
end

function addon:GetPositionLimits()
    local width = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 1000
    local height = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 800
    return max(0, floor(width / 2 - 90)), max(0, floor(height / 2 - 24))
end

function addon:ClampPosition(x, y)
    local limitX, limitY = self:GetPositionLimits()
    x = max(-limitX, math.min(limitX, x))
    y = max(-limitY, math.min(limitY, y))
    return floor(x + 0.5), floor(y + 0.5)
end

function addon:GetDamageColor(damage, settings)
    settings = settings or self.db or self.defaults
    if not settings.colorBySchool then
        local color = settings.baseColor or self.defaults.baseColor
        return color[1], color[2], color[3]
    end

    local colors = settings.colors or self.defaults.colors
    local schoolMask = damage.schoolMask or 1
    if schoolMask == 1 and damage.damageKind == "autoAttack" then
        local autoAttack = colors.autoAttack or self.defaults.colors.autoAttack
        return autoAttack[1], autoAttack[2], autoAttack[3]
    end

    local red, green, blue, count = 0, 0, 0, 0
    for _, school in pairs(schoolColors) do
        if bitBand(schoolMask, school.mask) ~= 0 then
            local color = colors[school.key] or self.defaults.colors[school.key]
            red = red + color[1]
            green = green + color[2]
            blue = blue + color[3]
            count = count + 1
        end
    end

    if count == 0 then
        local color = settings.baseColor or self.defaults.baseColor
        return color[1], color[2], color[3]
    end
    return red / count, green / count, blue / count
end

local managedCVars = {
    "CombatDamage",
    "CombatLogPeriodicSpells",
    "PetMeleeDamage",
    "PetSpellDamage",
}

function addon:RefreshUnitGuids()
    if UnitGUID then
        self.playerGUID = UnitGUID("player")
        self.petGUID = UnitGUID("pet")
    end
end

function addon:DisableBlizzardDamage()
    if not GetCVar or not SetCVar or not self.db or not self.db.manageBlizzardDamage then
        return
    end

    self.db.originalCVars = self.db.originalCVars or {}
    for _, cvar in pairs(managedCVars) do
        local ok, value = pcall(GetCVar, cvar)
        if ok and value ~= nil then
            if self.db.originalCVars[cvar] == nil then
                self.db.originalCVars[cvar] = value
            end
            pcall(SetCVar, cvar, "0")
        end
    end
end

function addon:RestoreBlizzardDamage()
    if not SetCVar or not self.db or not self.db.originalCVars then
        return
    end

    for cvar, value in pairs(self.db.originalCVars) do
        local shouldRestore = true
        if GetCVar then
            local ok, current = pcall(GetCVar, cvar)
            shouldRestore = not ok or tostring(current) == "0"
        end
        if shouldRestore then
            pcall(SetCVar, cvar, value)
        end
    end
    self.db.originalCVars = nil
end

function addon:ApplyRuntimeSettings()
    if not self.db then
        return
    end

    if self.db.enabled and self.db.manageBlizzardDamage then
        self:DisableBlizzardDamage()
    else
        self:RestoreBlizzardDamage()
        if not self.db.enabled and self.HideAllMessages then
            self:HideAllMessages()
        end
    end

    if self.UpdateRendererSettings then
        self:UpdateRendererSettings()
    end
end

function addon:SetEnabled(enabled)
    self.db.enabled = enabled and true or false
    self:ApplyRuntimeSettings()
end

function addon:ResetDebugStats()
    self.debugStats = {
        received = 0,
        displayed = 0,
        filtered = 0,
    }
end

function addon:PrintDebugStats()
    local stats = self.debugStats or {}
    local message = "SbDamage: получено " .. tostring(stats.received or 0)
        .. ", показано " .. tostring(stats.displayed or 0)
        .. ", отфильтровано " .. tostring(stats.filtered or 0)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    elseif print then
        print(message)
    end
end

function addon:Initialize()
    if self.initialized then
        return
    end
    SbDamageDB = self:MigrateSettings(SbDamageDB or {})
    SbDamageDB = self:ApplyDefaults(SbDamageDB)
    SbDamageDB = self:SanitizeSettings(SbDamageDB)
    SbDamageDB.schemaVersion = self.defaults.schemaVersion
    self.db = SbDamageDB
    self:RefreshUnitGuids()
    self.iconHistory = {}
    self:RebuildSpellFilter()
    self:ResetDebugStats()

    if self.InitializeRenderer then
        self:InitializeRenderer()
    end
    if self.InitializeOptions then
        self:InitializeOptions()
    end

    self:ApplyRuntimeSettings()
    self.initialized = true

    if self.eventFrame then
        self.eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self.eventFrame:RegisterEvent("PLAYER_LOGOUT")
        self.eventFrame:RegisterEvent("UNIT_PET")
        self.eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    end
end

function addon:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if self:IsOwnAddon(loadedAddon) then
            self:SetRuntimeAddonName(loadedAddon)
            self:Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        self:Initialize()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if self.db and self.db.enabled then
            local damage = self:ParseCombatLogEvent(...)
            if damage and self.DisplayDamage then
                if self.db.debug.enabled then
                    self.debugStats.received = self.debugStats.received + 1
                end
                self:DisplayDamage(damage)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:RefreshUnitGuids()
        self.iconHistory = {}
        self.destinationNameplates = {}
        self.nextNameplateScan = nil
        self:ApplyRuntimeSettings()
    elseif event == "UNIT_PET" then
        local unit = ...
        if unit == "player" then
            self:RefreshUnitGuids()
            self.petAttackTexture = nil
        end
    elseif event == "PLAYER_LOGOUT" then
        self:RestoreBlizzardDamage()
    elseif event == "DISPLAY_SIZE_CHANGED" then
        if self.UpdateRendererSettings then
            self:UpdateRendererSettings()
        end
        if self.RefreshOptions then
            self:RefreshOptions()
        end
    end
end

if CreateFrame and not addon.eventFrame then
    addon.eventFrame = CreateFrame("Frame")
    addon.eventFrame:RegisterEvent("ADDON_LOADED")
    addon.eventFrame:RegisterEvent("PLAYER_LOGIN")
    addon.eventFrame:SetScript("OnEvent", function(_, event, ...)
        addon:OnEvent(event, ...)
    end)
end
