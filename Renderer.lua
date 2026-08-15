local addon = SbDamage
local floor = math.floor
local max = math.max
local min = math.min
local sin = math.sin
local pi = math.pi
local tinsert = table.insert
local tremove = table.remove

local MAX_MESSAGES = 60
local NORMAL_DURATION = 1.15
local MESSAGE_PADDING = 8
local RISE_DISTANCE = 42
local CRIT_SHAKE_MARGIN = 8
local AOE_COLLISION_PADDING = 4
local AOE_MOTION_MARGIN = 8
local AOE_SHIFT_STEP = 12
local FALLBACK_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local STREAM_COLUMN = {
    periodic = -1,
    direct = 0,
    pet = 1,
}

local function setDesaturated(texture, enabled)
    texture:SetVertexColor(1, 1, 1)
    if texture.SetDesaturated then
        local ok = pcall(texture.SetDesaturated, texture, enabled)
        if ok then
            return
        end
    end
    if enabled then
        texture:SetVertexColor(0.45, 0.45, 0.45)
    end
end

local function resetMessage(message)
    message:Hide()
    message:ClearAllPoints()
    message:SetAlpha(1)
    message:SetScale(1)
    message.text:SetText("")
    message.icon:SetTexture(nil)
    message.icon:Hide()
    setDesaturated(message.icon, false)
    message.damage = nil
    message.anchor = nil
    message.layoutWidth = nil
    message.layoutHeight = nil
    message.streamTarget = nil
    message.targetFrame = nil
    message.streamType = nil
    message.stackIndex = nil
    message.visualScale = nil
    message.textSize = nil
    message.showIcon = nil
    message.riseDirection = nil
    message.aoeOffsetY = nil
end

function addon:CreateDamageMessage()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetWidth(240)
    frame:SetHeight(56)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text:SetJustifyH("CENTER")
    frame.text:SetShadowColor(0, 0, 0, 0.9)
    frame.text:SetShadowOffset(1, -1)

    frame.icon = frame:CreateTexture(nil, "OVERLAY")
    frame.icon:SetPoint("RIGHT", frame.text, "LEFT", -5, 0)
    frame.icon:Hide()

    self.createdMessages = self.createdMessages + 1
    return frame
end

function addon:ReleaseDamageMessage(message)
    resetMessage(message)
    tinsert(self.freeMessages, message)
end

function addon:AcquireDamageMessage()
    local message = tremove(self.freeMessages)
    if message then
        return message
    end
    if self.createdMessages < MAX_MESSAGES then
        return self:CreateDamageMessage()
    end

    local oldest = tremove(self.activeMessages, 1)
    if not oldest then
        self.createdMessages = 0
        return self:CreateDamageMessage()
    end
    self.pendingRelayoutTarget = oldest.streamTarget
    resetMessage(oldest)
    return oldest
end

function addon:RelayoutPendingTarget(currentTarget)
    local pending = self.pendingRelayoutTarget
    self.pendingRelayoutTarget = nil
    if not pending or pending == currentTarget then
        return
    end
    for _, message in ipairs(self.activeMessages) do
        if message.streamTarget == pending then
            local originX, originY = self:GetDamageOrigin(message.targetFrame)
            self:LayoutDamageCluster(pending, originX, originY)
            return
        end
    end
end

function addon:UpdateDamageMessage(message, elapsed)
    message.elapsed = message.elapsed + elapsed
    local progress = message.elapsed / message.duration
    if progress >= 1 then
        return false
    end

    local x = message.baseX
    local y = message.baseY + RISE_DISTANCE * progress * (message.riseDirection or 1)
    local scale = message.visualScale or 1

    if message.critical then
        local mode = self.db.critAnimation
        if mode == "shake" or mode == "combined" then
            x = x + sin(progress * 70) * 4 * (1 - progress)
        end
        if mode == "scale" or mode == "combined" then
            local pulseProgress = min(progress / 0.35, 1)
            scale = scale * (1 + sin(pulseProgress * pi) * 0.25)
        end
    end

    local alpha = 1
    local fadeStart = self.db.animation and self.db.animation.fadeStart or 0.62
    if progress > fadeStart then
        alpha = max(0, (1 - progress) / (1 - fadeStart))
    end

    message:ClearAllPoints()
    message:SetPoint("CENTER", message.anchor, "CENTER", x, y)
    message.currentX = x
    message.currentY = y
    message:SetScale(scale)
    message:SetAlpha(alpha)
    return true
end

function addon:OnRendererUpdate(elapsed)
    for index = #self.activeMessages, 1, -1 do
        local message = self.activeMessages[index]
        if not self:UpdateDamageMessage(message, elapsed) then
            tremove(self.activeMessages, index)
            self:ReleaseDamageMessage(message)
        end
    end
    if #self.activeMessages == 0 then
        self.rendererFrame:SetScript("OnUpdate", nil)
        self.rendererRunning = false
    end
end

function addon:StartRenderer()
    if self.rendererRunning then
        return
    end
    self.rendererRunning = true
    self.rendererFrame:SetScript("OnUpdate", function(_, elapsed)
        addon:OnRendererUpdate(elapsed)
    end)
end

function addon:GetAnimationDuration()
    local animation = self.db.animation or self.defaults.animation
    return NORMAL_DURATION / max(0.1, animation.speed or 1)
end

function addon:RefreshAnimationDuration()
    local duration = self:GetAnimationDuration()
    for _, message in ipairs(self.activeMessages) do
        local progress = message.duration > 0 and message.elapsed / message.duration or 0
        message.duration = duration
        message.elapsed = duration * min(progress, 1)
    end
end

function addon:GetFrameOffset(frame)
    if not frame or not frame.GetCenter or not UIParent or not UIParent.GetCenter then
        return nil
    end

    local frameX, frameY = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not frameX or not frameY or not parentX or not parentY then
        return nil
    end

    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    return frameX * frameScale / parentScale - parentX,
        frameY * frameScale / parentScale - parentY
end

function addon:GetDamageStreamType(damage)
    if damage.sourceType == "pet" then
        return "pet"
    end
    if damage.periodic then
        return "periodic"
    end
    return "direct"
end

function addon:GetMovementDirection(mode, roomAbove, roomBelow, requiredHeight)
    if mode == "down" then
        return -1
    end
    if mode == "auto" and roomAbove < requiredHeight and roomBelow > roomAbove then
        return -1
    end
    return 1
end

function addon:GetDamageOrigin(target)
    local targetX, targetY = self:GetFrameOffset(target)
    if targetX then
        local targetOffset = self.db.targetOffset or self.defaults.targetOffset
        return targetX + targetOffset.x, targetY + targetOffset.y
    end

    local anchorX, anchorY = self:GetFrameOffset(self.anchor)
    return anchorX or self.db.position.x, anchorY or self.db.position.y
end

function addon:GetDamagePlacement(damage, now)
    if damage.previewTargetFrame then
        local target = self.db.layout.aoeMode == "focus"
            and damage.previewFocusFrame or damage.previewTargetFrame
        return target, target
    end

    local aoeMode = self.db.layout.aoeMode or self.defaults.layout.aoeMode
    if aoeMode == "focus" then
        local selectedGUID = UnitGUID and UnitGUID("target")
        local selectedName = UnitName and UnitName("target")
        local target = selectedGUID and self.FindNameplate and self:FindNameplate({
            destinationGUID = selectedGUID,
            destinationName = selectedName,
        }, now)
        return target, target or self.anchor
    end

    local target = self.FindNameplate and self:FindNameplate(damage, now)
    if target then
        return target, target
    end
    return nil, self.anchor
end

function addon:RefreshDamageLayouts()
    if not self.activeMessages or #self.activeMessages == 0 then
        return
    end

    for _, message in ipairs(self.activeMessages) do
        local target, streamTarget = self:GetDamagePlacement(message.damage, GetTime())
        message.targetFrame = target
        message.streamTarget = streamTarget
        self:RefreshMessageLayout(message)
    end
    self:EnforceActiveStreamLimits()

    local targets = {}
    local seen = {}
    for _, message in ipairs(self.activeMessages) do
        local streamTarget = message.streamTarget
        if streamTarget and not seen[streamTarget] then
            seen[streamTarget] = true
            targets[#targets + 1] = {
                key = streamTarget,
                frame = message.targetFrame,
            }
        end
    end

    for _, target in ipairs(targets) do
        local originX, originY = self:GetDamageOrigin(target.frame)
        self:LayoutDamageCluster(target.key, originX, originY)
    end
end

function addon:RefreshActiveMessageStyles()
    if not self.activeMessages then
        return
    end
    local iconMode = self.db.icon.mode
    for _, message in ipairs(self.activeMessages) do
        local damage = message.damage
        message.text:SetText(damage.text or self:FormatDamageAmount(damage.amount))
        message.text:SetTextColor(self:GetDamageColor(damage, self.db))

        local showIcon = damage.texture and iconMode ~= "off"
            and (iconMode == "every" or message.showIcon)
        message.showIcon = showIcon and true or false
        if message.showIcon then
            message.icon:SetTexture(damage.texture)
            message.icon:SetWidth(self.db.icon.size)
            message.icon:SetHeight(self.db.icon.size)
            setDesaturated(message.icon, self.db.icon.desaturated)
            message.icon:Show()
        else
            message.icon:SetTexture(nil)
            message.icon:Hide()
        end
    end
    self:RefreshDamageLayouts()
end

function addon:EnforceActiveStreamLimits()
    local limit = floor(self.db.layout.maxPerColumn + 0.5)
    local excess = {}
    for _, message in ipairs(self.activeMessages) do
        local targetCounts = excess[message.streamTarget]
        if not targetCounts then
            targetCounts = {}
            excess[message.streamTarget] = targetCounts
        end
        targetCounts[message.streamType] = (targetCounts[message.streamType] or 0) + 1
    end
    for _, targetCounts in pairs(excess) do
        for streamType, count in pairs(targetCounts) do
            targetCounts[streamType] = max(0, count - limit)
        end
    end

    local index = 1
    while index <= #self.activeMessages do
        local message = self.activeMessages[index]
        local removeCount = excess[message.streamTarget][message.streamType]
        if removeCount > 0 then
            excess[message.streamTarget][message.streamType] = removeCount - 1
            tremove(self.activeMessages, index)
            self:ReleaseDamageMessage(message)
        else
            index = index + 1
        end
    end
end

function addon:RemoveOldestStreamMessage(streamTarget, streamType)
    for index, message in ipairs(self.activeMessages) do
        if message.streamTarget == streamTarget and message.streamType == streamType then
            tremove(self.activeMessages, index)
            self:ReleaseDamageMessage(message)
            return
        end
    end
end

function addon:RemoveOldestClusterMessage(streamTarget)
    for index, message in ipairs(self.activeMessages) do
        if message.streamTarget == streamTarget then
            tremove(self.activeMessages, index)
            self:ReleaseDamageMessage(message)
            return true
        end
    end
    return false
end

function addon:TrimDamageStream(streamTarget, streamType)
    local limit = floor(self.db.layout.maxPerColumn + 0.5)
    local count = 0
    for _, message in ipairs(self.activeMessages) do
        if message.streamTarget == streamTarget and message.streamType == streamType then
            count = count + 1
        end
    end
    if count >= limit then
        self:RemoveOldestStreamMessage(streamTarget, streamType)
    end
end

function addon:GetMessageBounds(message, critical, showIcon, visualScale)
    local textSize = message.textSize or self:GetDamageTextSize(message.damage)
    local textWidth = message.text.GetStringWidth and message.text:GetStringWidth() or textSize * 4
    local textHeight = message.text.GetStringHeight and message.text:GetStringHeight() or textSize
    local iconWidth = showIcon and self.db.icon.size + 5 or 0
    local iconHeight = showIcon and self.db.icon.size or 0
    local peakScale = critical
        and (self.db.critAnimation == "scale" or self.db.critAnimation == "combined")
        and 1.25 or 1
    local contentWidth = textWidth + iconWidth
    local shakeMargin = critical and CRIT_SHAKE_MARGIN or 0
    return (contentWidth + MESSAGE_PADDING) * peakScale * visualScale + shakeMargin,
        (max(textHeight, iconHeight) + MESSAGE_PADDING) * peakScale * visualScale,
        contentWidth
end

local function messagesOverlap(left, right)
    return math.abs(left.baseX - right.baseX) < (left.layoutWidth + right.layoutWidth) / 2
        and math.abs(left.baseY - right.baseY) < (left.layoutHeight + right.layoutHeight) / 2
end

local function getClusterBounds(messages)
    local bounds = {}
    for _, message in ipairs(messages) do
        local left = message.baseX - message.layoutWidth / 2
        local right = message.baseX + message.layoutWidth / 2
        local bottom = message.baseY - message.layoutHeight / 2 - AOE_MOTION_MARGIN
        local top = message.baseY + message.layoutHeight / 2 + AOE_MOTION_MARGIN
        if message.riseDirection and message.riseDirection < 0 then
            bottom = bottom - RISE_DISTANCE
        else
            top = top + RISE_DISTANCE
        end
        bounds.left = bounds.left and min(bounds.left, left) or left
        bounds.right = bounds.right and max(bounds.right, right) or right
        bounds.bottom = bounds.bottom and min(bounds.bottom, bottom) or bottom
        bounds.top = bounds.top and max(bounds.top, top) or top
    end
    return bounds
end

local function shiftedBounds(bounds, offsetY)
    return {
        left = bounds.left,
        right = bounds.right,
        bottom = bounds.bottom + offsetY,
        top = bounds.top + offsetY,
    }
end

local function clusterBoundsOverlap(left, right)
    return left.left < right.right + AOE_COLLISION_PADDING
        and left.right > right.left - AOE_COLLISION_PADDING
        and left.bottom < right.top + AOE_COLLISION_PADDING
        and left.top > right.bottom - AOE_COLLISION_PADDING
end

local function clusterOverlapArea(left, right)
    local width = min(left.right, right.right) - max(left.left, right.left)
    local height = min(left.top, right.top) - max(left.bottom, right.bottom)
    if width <= 0 or height <= 0 then
        return 0
    end
    return width * height
end

function addon:GetAoeClusterOffset(streamTarget, messages, direction, screenTop, screenBottom)
    local layout = self.db.layout
    if layout.aoeMode ~= "spread" or #messages == 0 then
        return 0
    end

    local obstacleMessages = {}
    for _, message in ipairs(self.activeMessages) do
        if message.streamTarget ~= streamTarget and message.baseX and message.baseY then
            local group = obstacleMessages[message.streamTarget]
            if not group then
                group = {}
                obstacleMessages[message.streamTarget] = group
            end
            group[#group + 1] = message
        end
    end

    local obstacles = {}
    for _, group in pairs(obstacleMessages) do
        obstacles[#obstacles + 1] = getClusterBounds(group)
    end
    if #obstacles == 0 then
        return 0
    end

    local bounds = getClusterBounds(messages)
    local preferredOffset
    for _, message in ipairs(messages) do
        if message.aoeOffsetY then
            preferredOffset = message.aoeOffsetY
            break
        end
    end
    local candidates = {}
    local seen = {}
    local function addCandidate(offset)
        if offset and not seen[offset] then
            seen[offset] = true
            candidates[#candidates + 1] = offset
        end
    end
    addCandidate(preferredOffset)
    addCandidate(0)
    local maxShift = floor((layout.aoeMaxShift or self.defaults.layout.aoeMaxShift) + 0.5)
    for offset = AOE_SHIFT_STEP, maxShift, AOE_SHIFT_STEP do
        addCandidate(direction * offset)
        addCandidate(-direction * offset)
    end

    local bestOffset = 0
    local bestOverlap
    for _, offset in ipairs(candidates) do
        local candidate = shiftedBounds(bounds, offset)
        if candidate.bottom >= screenBottom and candidate.top <= screenTop then
            local overlaps = false
            local overlapArea = 0
            for _, obstacle in ipairs(obstacles) do
                if clusterBoundsOverlap(candidate, obstacle) then
                    overlaps = true
                    overlapArea = overlapArea + clusterOverlapArea(candidate, obstacle)
                end
            end
            if not overlaps then
                return offset
            end
            if not bestOverlap or overlapArea < bestOverlap then
                bestOverlap = overlapArea
                bestOffset = offset
            end
        end
    end
    return bestOffset
end

function addon:LayoutDamageCluster(streamTarget, originX, originY)
    local streams = {
        direct = {},
        periodic = {},
        pet = {},
    }
    local streamWidths = {
        direct = 0,
        periodic = 0,
        pet = 0,
    }
    for index = #self.activeMessages, 1, -1 do
        local message = self.activeMessages[index]
        if message.streamTarget == streamTarget then
            local stream = streams[message.streamType]
            stream[#stream + 1] = message
            streamWidths[message.streamType] = max(streamWidths[message.streamType], message.layoutWidth)
        end
    end

    local layout = self.db.layout
    local parentWidth = UIParent:GetWidth()
    local parentHeight = UIParent:GetHeight()
    local screenMargin = 8
    local columnGap = layout.columnGap
    local leftExtent = columnGap + streamWidths.periodic / 2
    local rightExtent = columnGap + streamWidths.pet / 2
    local centerExtent = streamWidths.direct / 2
    local minOriginX = -parentWidth / 2 + screenMargin + max(leftExtent, centerExtent)
    local maxOriginX = parentWidth / 2 - screenMargin - max(rightExtent, centerExtent)
    while minOriginX > maxOriginX and columnGap > 0 do
        columnGap = max(0, columnGap - 2)
        leftExtent = columnGap + streamWidths.periodic / 2
        rightExtent = columnGap + streamWidths.pet / 2
        minOriginX = -parentWidth / 2 + screenMargin + max(leftExtent, centerExtent)
        maxOriginX = parentWidth / 2 - screenMargin - max(rightExtent, centerExtent)
    end
    if minOriginX <= maxOriginX then
        originX = max(minOriginX, min(maxOriginX, originX))
    else
        originX = 0
    end

    local estimatedHeight = 0
    for _, stream in pairs(streams) do
        local height = 0
        for index, message in ipairs(stream) do
            height = height + message.layoutHeight
            if index > 1 then
                height = height + layout.lineSpacing
            end
        end
        estimatedHeight = max(estimatedHeight, height)
    end
    local top = parentHeight / 2 - screenMargin
    local bottom = -parentHeight / 2 + screenMargin
    local roomAbove = top - originY
    local roomBelow = originY - bottom
    local direction = self:GetMovementDirection(
        layout.direction,
        roomAbove,
        roomBelow,
        estimatedHeight + RISE_DISTANCE)

    local placed = {}
    local streamOrder = { "direct", "periodic", "pet" }
    for _, streamType in ipairs(streamOrder) do
        local previous
        for index, message in ipairs(streams[streamType]) do
            message.stackIndex = index - 1
            message.baseX = originX + STREAM_COLUMN[streamType] * columnGap
            if previous then
                message.baseY = previous.baseY + direction
                    * ((previous.layoutHeight + message.layoutHeight) / 2 + layout.lineSpacing)
            else
                message.baseY = originY
            end

            local moved = true
            while moved do
                moved = false
                for _, other in ipairs(placed) do
                    if messagesOverlap(message, other) then
                        local separatedY = other.baseY + direction
                            * ((other.layoutHeight + message.layoutHeight) / 2 + layout.lineSpacing)
                        local nextY = direction > 0 and max(message.baseY, separatedY)
                            or min(message.baseY, separatedY)
                        if nextY ~= message.baseY then
                            message.baseY = nextY
                            moved = true
                        end
                    end
                end
            end
            placed[#placed + 1] = message
            previous = message
        end
    end

    local lowest, highest
    for _, message in ipairs(placed) do
        message.riseDirection = direction
        local messageBottom = message.baseY - message.layoutHeight / 2
        local messageTop = message.baseY + message.layoutHeight / 2
        if direction > 0 then
            messageTop = messageTop + RISE_DISTANCE
        else
            messageBottom = messageBottom - RISE_DISTANCE
        end
        lowest = lowest and min(lowest, messageBottom) or messageBottom
        highest = highest and max(highest, messageTop) or messageTop
    end
    if highest and highest - lowest > top - bottom and #placed > 1 then
        self:RemoveOldestClusterMessage(streamTarget)
        return self:LayoutDamageCluster(streamTarget, originX, originY)
    end
    local shiftY = 0
    if highest and highest > top then
        shiftY = top - highest
    end
    if lowest and lowest + shiftY < bottom then
        shiftY = bottom - lowest
    end

    for _, message in ipairs(placed) do
        message.baseY = message.baseY + shiftY
    end

    local aoeOffsetY = self:GetAoeClusterOffset(streamTarget, placed, direction, top, bottom)
    for _, message in ipairs(placed) do
        message.baseY = message.baseY + aoeOffsetY
        message.aoeOffsetY = aoeOffsetY
        message.currentX = message.baseX
        message.currentY = message.baseY
        self:UpdateDamageMessage(message, 0)
    end
end

function addon:CenterMessageContents(message, showIcon, contentWidth)
    message.text:ClearAllPoints()
    message.icon:ClearAllPoints()
    if showIcon then
        message.text:SetPoint("RIGHT", message, "CENTER", contentWidth / 2, 0)
        message.icon:SetPoint("RIGHT", message.text, "LEFT", -5, 0)
    else
        message.text:SetPoint("CENTER", message, "CENTER", 0, 0)
    end
end

function addon:GetDamageVisualScale(damage, streamType)
    local scale = 1
    if streamType == "pet" then
        scale = self.db.layout.petScale
    else
        local selectedGUID = UnitGUID and UnitGUID("target")
        if damage.isSecondaryTarget
            or selectedGUID and damage.destinationGUID and damage.destinationGUID ~= selectedGUID then
            scale = self.db.layout.secondaryScale or self.defaults.layout.secondaryScale
        end
    end
    if damage.critical then
        scale = scale * self.db.critScale
    end
    return scale
end

function addon:GetDamageTextSize(damage)
    if damage.periodic then
        return self.db.periodicTextSize or self.defaults.periodicTextSize
    end
    return self.db.directTextSize or self.defaults.directTextSize
end

function addon:RefreshMessageLayout(message)
    message.textSize = self:GetDamageTextSize(message.damage)
    local fontApplied = message.text:SetFont(self:GetFontPath(), message.textSize, "OUTLINE")
    if message.text.GetFont then
        fontApplied = message.text:GetFont() ~= nil
    end
    if not fontApplied then
        local fallback = FALLBACK_FONT
        if GameFontNormal and GameFontNormal.GetFont then
            fallback = GameFontNormal:GetFont() or fallback
        end
        message.text:SetFont(fallback, message.textSize, "OUTLINE")
    end
    message.text:Show()
    message.visualScale = self:GetDamageVisualScale(message.damage, message.streamType)
    local contentWidth
    message.layoutWidth, message.layoutHeight, contentWidth = self:GetMessageBounds(
        message, message.damage.critical, message.showIcon, message.visualScale)
    self:CenterMessageContents(message, message.showIcon, contentWidth)
end

function addon:DisplayDamage(damage, isPreview)
    if not self.db or (not self.db.enabled and not isPreview) then
        return
    end
    if not isPreview and not self:ShouldDisplayDamage(damage) then
        if self.db.debug.enabled then
            self.debugStats.filtered = self.debugStats.filtered + 1
        end
        return
    end

    local now = GetTime()
    local target, streamTarget = self:GetDamagePlacement(damage, now)
    local streamType = self:GetDamageStreamType(damage)
    self:TrimDamageStream(streamTarget, streamType)
    local message = self:AcquireDamageMessage()

    message.elapsed = 0
    message.duration = self:GetAnimationDuration()
    message.critical = damage.critical
    message.damage = damage
    message.streamTarget = streamTarget
    message.targetFrame = target
    message.streamType = streamType

    local displayText = damage.text or self:FormatDamageAmount(damage.amount)
    message.text:SetText(displayText)
    message.text:SetTextColor(self:GetDamageColor(damage, self.db))

    local showIcon = damage.texture
        and self:ShouldShowIcon(damage, self.db.icon.mode, now)
    message.showIcon = showIcon and true or false
    if showIcon then
        message.icon:SetTexture(damage.texture)
        message.icon:SetWidth(self.db.icon.size)
        message.icon:SetHeight(self.db.icon.size)
        setDesaturated(message.icon, self.db.icon.desaturated)
        message.icon:Show()
    else
        message.icon:SetTexture(nil)
        message.icon:Hide()
    end

    local originX, originY = self:GetDamageOrigin(target)

    self:RefreshMessageLayout(message)
    message.anchor = UIParent
    message:Show()
    tinsert(self.activeMessages, message)
    if not isPreview and self.db.debug.enabled then
        self.debugStats.displayed = self.debugStats.displayed + 1
    end
    self:LayoutDamageCluster(streamTarget, originX, originY)
    self:RelayoutPendingTarget(streamTarget)
    self:StartRenderer()
end

function addon:HideAllMessages()
    for index = #self.activeMessages, 1, -1 do
        local message = tremove(self.activeMessages, index)
        self:ReleaseDamageMessage(message)
    end
    if self.rendererFrame then
        self.rendererFrame:SetScript("OnUpdate", nil)
        self.rendererRunning = false
    end
end

function addon:UpdateAnchorLabel()
    if self.anchorLabel and self.db then
        self.anchorLabel:SetText("SbDamage\nX: " .. self.db.position.x .. "  Y: " .. self.db.position.y)
    end
end

function addon:UpdateRendererSettings()
    if not self.anchor or not self.db then
        return
    end
    self.db.position.x, self.db.position.y = self:ClampPosition(self.db.position.x, self.db.position.y)
    self.anchor:ClearAllPoints()
    self.anchor:SetPoint("CENTER", UIParent, "CENTER", self.db.position.x, self.db.position.y)
    self:UpdateAnchorLabel()
    self:RefreshDamageLayouts()
end

function addon:SetConfigMode(enabled)
    if not self.anchor then
        return
    end

    self.configMode = enabled and true or false
    self.anchor:EnableMouse(self.configMode)
    if self.configMode then
        self.anchor:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        self.anchor:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
        self.anchor:SetBackdropBorderColor(1, 0.82, 0, 1)
        self.anchorLabel:Show()
        self.anchor:Show()
    else
        self.anchor:SetBackdrop(nil)
        self.anchorLabel:Hide()
    end
    if self.controls and self.controls.moveButton then
        self.controls.moveButton:SetText(self.configMode and "Закончить" or "Переместить")
    end
end

function addon:ToggleConfigMode()
    self:SetConfigMode(not self.configMode)
end

function addon:ShowPreview()
    local preview = {
        { amount = 1248, spellId = 6603, schoolMask = 1, damageKind = "autoAttack", critical = false, periodic = false, sourceType = "player" },
        { amount = 3870, spellId = 19434, schoolMask = 1, damageKind = "ability", critical = true, periodic = false, sourceType = "player" },
        { amount = 2205, spellId = 133, schoolMask = 4, damageKind = "ability", critical = false, periodic = false, sourceType = "player" },
        { amount = 915, spellId = 686, schoolMask = 32, damageKind = "ability", critical = false, periodic = true, sourceType = "player" },
        { amount = 742, spellId = 172, schoolMask = 32, damageKind = "ability", critical = false, periodic = true, sourceType = "pet" },
    }

    local previousIconHistory = self.iconHistory
    local targetGUID = UnitGUID and UnitGUID("target")
    local targetName = UnitName and UnitName("target")
    self.iconHistory = {}
    for _, damage in ipairs(preview) do
        if damage.sourceType ~= "pet" or self.db.showPetDamage then
            damage.texture = GetSpellInfo and select(3, GetSpellInfo(damage.spellId))
            damage.destinationGUID = targetGUID
            damage.destinationName = targetName
            self:DisplayDamage(damage, true)
        end
    end
    self.iconHistory = previousIconHistory
end

function addon:ShowAoePreview()
    self:HideAllMessages()
    local previousIconHistory = self.iconHistory
    local selectedGUID = UnitGUID and UnitGUID("target") or "SbDamage-Preview-Primary"
    self.iconHistory = {}

    local samples = {
        { amount = 2480, spellId = 133, schoolMask = 4, critical = true, offset = -18 },
        { amount = 1840, spellId = 133, schoolMask = 4, critical = false, offset = 0 },
        { amount = 1260, spellId = 133, schoolMask = 4, critical = false, offset = 18 },
    }
    local focusFrame = self.aoePreviewTargets[2]
    local position = self.db.position or self.defaults.position
    local targetOffset = self.db.targetOffset or self.defaults.targetOffset
    for index, sample in ipairs(samples) do
        local frame = self.aoePreviewTargets[index]
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER",
            position.x + sample.offset - targetOffset.x,
            position.y - targetOffset.y)
        sample.damageKind = "ability"
        sample.periodic = false
        sample.sourceType = "player"
        sample.texture = GetSpellInfo and select(3, GetSpellInfo(sample.spellId))
        sample.destinationGUID = index == 2 and selectedGUID or "SbDamage-Preview-" .. index
        sample.destinationName = "Preview " .. index
        sample.isSecondaryTarget = index ~= 2
        sample.previewTargetFrame = frame
        sample.previewFocusFrame = focusFrame
        self:DisplayDamage(sample, true)
    end
    self.iconHistory = previousIconHistory
end

function addon:InitializeRenderer()
    if self.rendererInitialized then
        return
    end

    self.activeMessages = {}
    self.freeMessages = {}
    self.createdMessages = 0
    self.destinationNameplates = {}
    self.aoePreviewTargets = {}
    for index = 1, 3 do
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetWidth(1)
        frame:SetHeight(1)
        self.aoePreviewTargets[index] = frame
    end

    self.anchor = CreateFrame("Frame", "SbDamageAnchor", UIParent)
    self.anchor:SetWidth(180)
    self.anchor:SetHeight(48)
    self.anchor:SetFrameStrata("DIALOG")
    self.anchor:SetMovable(true)
    self.anchor:SetClampedToScreen(true)
    self.anchor:RegisterForDrag("LeftButton")
    self.anchor:SetScript("OnDragStart", function(frame)
        frame:StartMoving()
    end)
    self.anchor:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local centerX, centerY = frame:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        addon.db.position.x, addon.db.position.y = addon:ClampPosition(centerX - parentX, centerY - parentY)
        addon:UpdateRendererSettings()
        if addon.RefreshOptions then
            addon:RefreshOptions()
        end
    end)

    self.anchorLabel = self.anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.anchorLabel:SetPoint("CENTER", self.anchor, "CENTER", 0, 0)
    self.anchorLabel:SetJustifyH("CENTER")
    self.anchorLabel:Hide()
    self.anchor:Show()
    self:UpdateRendererSettings()

    self.rendererFrame = CreateFrame("Frame", "SbDamageRendererFrame", UIParent)
    self.rendererInitialized = true
end
