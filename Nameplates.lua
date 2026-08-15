local addon = SbDamage
local ipairs = ipairs
local type = type

local NAMEPLATE_BORDER = "Interface\\Tooltips\\Nameplate-Border"
local SCAN_INTERVAL = 0.1

local function clearTable(values)
    for key in pairs(values) do
        values[key] = nil
    end
end

local function collectValues(target, ...)
    clearTable(target)
    for index = 1, select("#", ...) do
        target[index] = select(index, ...)
    end
    return target
end

local function isVisible(frame)
    if frame.IsVisible then
        return frame:IsVisible()
    end
    return frame.IsShown and frame:IsShown()
end

local function cleanText(text)
    if type(text) ~= "string" then
        return nil
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:match("^%s*(.-)%s*$")
    return text ~= "" and text or nil
end

local function isLikelyName(text)
    return text
        and not text:match("^%d+[%+%-]?$")
        and not text:match("^%?%?%+?$")
        and not text:match("^%d+%%$")
        and not text:match("^%d+%s*/%s*%d+$")
end

local function getText(value)
    if type(value) == "string" then
        return cleanText(value)
    end
    if not value or not value.GetObjectType or value:GetObjectType() ~= "FontString" then
        return nil
    end
    return value.GetText and cleanText(value:GetText())
end

function addon:GetNameplateNames(frame, names, seen)
    names = names or {}
    seen = seen or {}
    clearTable(names)
    clearTable(seen)
    if not frame then
        return names
    end

    local function addName(value)
        local text = getText(value)
        if isLikelyName(text) and not seen[text] then
            seen[text] = true
            names[#names + 1] = text
        end
    end

    addName(frame.nameTextRegion)
    addName(frame.nameText)
    addName(frame.NameText)
    addName(frame.name)
    if type(frame.aloftData) == "table" then
        addName(frame.aloftData.nameTextRegion)
        addName(frame.aloftData.name)
    end

    if not frame.GetRegions then
        return names
    end

    self.nameplateRegionBuffer = collectValues(self.nameplateRegionBuffer or {}, frame:GetRegions())
    local regions = self.nameplateRegionBuffer
    for _, region in ipairs(regions) do
        addName(region)
    end
    return names
end

function addon:GetNameplateName(frame)
    return self:GetNameplateNames(frame)[1]
end

local function hasNameplateBorder(frame, regions)
    regions = collectValues(regions, frame:GetRegions())
    for _, region in ipairs(regions) do
        if region.GetObjectType and region:GetObjectType() == "Texture" and region.GetTexture then
            local texture = region:GetTexture()
            if type(texture) == "string" then
                texture = texture:lower():gsub("/", "\\"):gsub("%.blp$", "")
                if texture == NAMEPLATE_BORDER:lower() then
                    return true
                end
            end
        end
    end
    return false
end

function addon:IsNameplate(frame)
    if not frame or not frame.GetRegions then
        return false
    end
    if frame.extended or frame.aloftData or frame.done then
        return true
    end
    self.nameplateBorderRegions = self.nameplateBorderRegions or {}
    if hasNameplateBorder(frame, self.nameplateBorderRegions) then
        return true
    end
    if frame.GetName and frame:GetName() then
        return false
    end

    local health = frame.GetChildren and frame:GetChildren()
    return health
        and health.GetObjectType
        and health:GetObjectType() == "StatusBar"
        and self:GetNameplateName(frame) ~= nil
end

function addon:ScanNameplates(now)
    if self.nextNameplateScan and now < self.nextNameplateScan then
        return
    end

    self.nextNameplateScan = now + SCAN_INTERVAL
    self.nameplatesByName = self.nameplatesByName or {}
    self.visibleNameplates = self.visibleNameplates or {}
    self.nameplateMatchPool = self.nameplateMatchPool or {}
    for _, matches in pairs(self.nameplatesByName) do
        clearTable(matches)
        self.nameplateMatchPool[#self.nameplateMatchPool + 1] = matches
    end
    clearTable(self.nameplatesByName)
    clearTable(self.visibleNameplates)
    if not WorldFrame or not WorldFrame.GetChildren then
        return
    end

    self.nameplateFrameBuffer = collectValues(self.nameplateFrameBuffer or {}, WorldFrame:GetChildren())
    local frames = self.nameplateFrameBuffer
    for _, frame in ipairs(frames) do
        if self:IsNameplate(frame) and isVisible(frame) then
            self.visibleNameplates[#self.visibleNameplates + 1] = frame
            self.nameplateNameBuffer = self.nameplateNameBuffer or {}
            self.nameplateSeenNames = self.nameplateSeenNames or {}
            self:GetNameplateNames(frame, self.nameplateNameBuffer, self.nameplateSeenNames)
            local names = self.nameplateNameBuffer
            for _, name in ipairs(names) do
                local matches = self.nameplatesByName[name]
                if not matches then
                    matches = table.remove(self.nameplateMatchPool) or {}
                    self.nameplatesByName[name] = matches
                end
                matches[#matches + 1] = frame
            end
        end
    end
end

local function contains(frames, wanted)
    for _, frame in ipairs(frames) do
        if frame == wanted then
            return true
        end
    end
    return false
end

local function findSelectedNameplate(frames)
    local selected
    for _, frame in ipairs(frames) do
        local alpha = frame.npNativeAlpha
        if type(alpha) ~= "number" and frame.GetAlpha then
            alpha = frame:GetAlpha()
        end
        if type(alpha) == "number" and alpha >= 0.99 then
            if selected then
                return nil
            end
            selected = frame
        end
    end
    return selected
end

function addon:FindNameplate(damage, now)
    self.destinationNameplates = self.destinationNameplates or {}
    local guid = damage.destinationGUID
    local assigned = guid and self.destinationNameplates[guid]
    if assigned and isVisible(assigned) then
        self.nameplateLookupNames = self.nameplateLookupNames or {}
        self.nameplateLookupSeen = self.nameplateLookupSeen or {}
        local names = self:GetNameplateNames(assigned, self.nameplateLookupNames, self.nameplateLookupSeen)
        for _, name in ipairs(names) do
            if name == damage.destinationName then
                return assigned
            end
        end
    end

    self:ScanNameplates(now)
    local matches = damage.destinationName
        and self.nameplatesByName
        and self.nameplatesByName[damage.destinationName]
    if guid and UnitGUID and UnitGUID("target") == guid then
        local candidates = matches and #matches > 0 and matches or self.visibleNameplates or {}
        local selected = findSelectedNameplate(candidates)
        if selected then
            self.destinationNameplates[guid] = selected
            return selected
        end
        if matches and #matches > 1 then
            return nil
        end
    end

    if not damage.destinationName then
        return nil
    end
    if not matches or #matches == 0 then
        return nil
    end

    assigned = guid and self.destinationNameplates[guid]
    if assigned then
        if contains(matches, assigned) then
            return assigned
        end
        self.destinationNameplates[guid] = nil
        assigned = nil
    end

    if not assigned then
        self.nameplateSequence = (self.nameplateSequence or 0) + 1
        assigned = matches[(self.nameplateSequence - 1) % #matches + 1]
    end

    if guid then
        self.destinationNameplates[guid] = assigned
    end
    return assigned
end
