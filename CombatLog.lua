local addon = SbDamage
local select = select
local tostring = tostring

local AUTO_ATTACK_SPELL_IDS = {
    [75] = true,   -- Auto Shot
    [5019] = true, -- Shoot
    [6603] = true, -- Attack
}

local SPELL_DAMAGE_EVENTS = {
    RANGE_DAMAGE = true,
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    DAMAGE_SHIELD = true,
    DAMAGE_SPLIT = true,
}

local SPELL_MISS_EVENTS = {
    RANGE_MISSED = true,
    SPELL_MISSED = true,
    SPELL_PERIODIC_MISSED = true,
    DAMAGE_SHIELD_MISSED = true,
}

local MISS_FALLBACK_TEXT = {
    ABSORB = "Absorb",
    BLOCK = "Block",
    DEFLECT = "Deflect",
    DODGE = "Dodge",
    EVADE = "Evade",
    IMMUNE = "Immune",
    MISS = "Miss",
    PARRY = "Parry",
    REFLECT = "Reflect",
    RESIST = "Resist",
}

local DEFAULT_PET_ATTACK_TEXTURE = "Interface\\Icons\\Ability_GhoulFrenzy"

local function hasFlag(flags, flag)
    return flags and flag and bit and bit.band and bit.band(flags, flag) ~= 0
end

function addon:IsOwnedSource(sourceGUID, sourceFlags)
    local playerGUID = self.playerGUID or (UnitGUID and UnitGUID("player"))
    if sourceGUID and sourceGUID == playerGUID then
        return "player"
    end

    local petGUID = self.petGUID or (UnitGUID and UnitGUID("pet"))
    if sourceGUID and sourceGUID == petGUID then
        return "pet"
    end

    local isMine = hasFlag(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE)
    local isPet = hasFlag(sourceFlags, COMBATLOG_OBJECT_TYPE_PET)
    local isGuardian = hasFlag(sourceFlags, COMBATLOG_OBJECT_TYPE_GUARDIAN)
    if isMine and (isPet or isGuardian) then
        return "pet"
    end
end

function addon:GetSpellTexture(spellId)
    if not GetSpellInfo or not spellId then
        return nil
    end
    self.spellTextureCache = self.spellTextureCache or {}
    local cached = self.spellTextureCache[spellId]
    if cached ~= nil then
        return cached or nil
    end

    local texture = select(3, GetSpellInfo(spellId))
    self.spellTextureCache[spellId] = texture or false
    return texture
end

function addon:GetPetAttackTexture()
    if self.petAttackTexture then
        return self.petAttackTexture
    end

    if GetPetActionInfo and IsPetAttackAction then
        local slots = NUM_PET_ACTION_SLOTS or 10
        for slot = 1, slots do
            if IsPetAttackAction(slot) then
                local _, _, texture, isToken = GetPetActionInfo(slot)
                if isToken and texture then
                    texture = _G[texture]
                end
                if texture then
                    self.petAttackTexture = texture
                    return texture
                end
            end
        end
    end

    self.petAttackTexture = PET_ATTACK_TEXTURE or DEFAULT_PET_ATTACK_TEXTURE
    return self.petAttackTexture
end

function addon:GetMissText(missType)
    return _G["COMBAT_TEXT_" .. missType] or _G[missType] or MISS_FALLBACK_TEXT[missType] or missType
end

function addon:ParseCombatLogEvent(...)
    local eventType = select(2, ...)
    local sourceGUID = select(3, ...)
    local sourceFlags = select(5, ...)
    local sourceType = self:IsOwnedSource(sourceGUID, sourceFlags)
    if not sourceType then
        return nil
    end
    if sourceType == "pet" and self.db and not self.db.showPetDamage then
        return nil
    end

    if eventType == "SWING_MISSED" then
        local missType = select(9, ...)
        if not missType then
            return nil
        end
        return {
            text = self:GetMissText(missType),
            missType = missType,
            spellId = 6603,
            texture = sourceType == "pet" and self:GetPetAttackTexture() or self:GetSpellTexture(6603),
            schoolMask = 1,
            damageKind = "autoAttack",
            critical = false,
            periodic = false,
            sourceType = sourceType,
            destinationGUID = select(6, ...),
            destinationName = select(7, ...),
        }
    end

    if SPELL_MISS_EVENTS[eventType] then
        local spellId = select(9, ...)
        local missType = select(12, ...)
        if not spellId or not missType then
            return nil
        end
        return {
            text = self:GetMissText(missType),
            missType = missType,
            spellId = spellId,
            texture = self:GetSpellTexture(spellId),
            schoolMask = select(11, ...) or 1,
            damageKind = AUTO_ATTACK_SPELL_IDS[spellId] and "autoAttack" or "ability",
            critical = false,
            periodic = eventType == "SPELL_PERIODIC_MISSED",
            sourceType = sourceType,
            destinationGUID = select(6, ...),
            destinationName = select(7, ...),
        }
    end

    if eventType == "SWING_DAMAGE" then
        local amount = select(9, ...)
        if not amount then
            return nil
        end
        return {
            amount = amount,
            spellId = 6603,
            texture = sourceType == "pet" and self:GetPetAttackTexture() or self:GetSpellTexture(6603),
            schoolMask = select(11, ...) or 1,
            damageKind = "autoAttack",
            critical = select(15, ...) and true or false,
            periodic = false,
            sourceType = sourceType,
            destinationGUID = select(6, ...),
            destinationName = select(7, ...),
        }
    end

    if not SPELL_DAMAGE_EVENTS[eventType] then
        return nil
    end

    local spellId = select(9, ...)
    local amount = select(12, ...)
    if not amount then
        return nil
    end

    local spellSchool = select(11, ...)
    local damageSchool = select(14, ...)
    return {
        amount = amount,
        spellId = spellId,
        texture = self:GetSpellTexture(spellId),
        schoolMask = damageSchool or spellSchool or 1,
        damageKind = AUTO_ATTACK_SPELL_IDS[spellId] and "autoAttack" or "ability",
        critical = select(18, ...) and true or false,
        periodic = eventType == "SPELL_PERIODIC_DAMAGE",
        sourceType = sourceType,
        destinationGUID = select(6, ...),
        destinationName = select(7, ...),
    }
end

function addon:ShouldShowIcon(damage, mode, now)
    if mode == "off" then
        return false
    end
    if mode == "every" then
        return true
    end

    self.iconHistory = self.iconHistory or {}
    if not self.nextIconHistoryCleanup or now >= self.nextIconHistoryCleanup then
        for historyKey, timestamp in pairs(self.iconHistory) do
            if now - timestamp > 2 then
                self.iconHistory[historyKey] = nil
            end
        end
        self.nextIconHistoryCleanup = now + 1
    end
    local key = (damage.sourceType or "unknown")
        .. ":" .. tostring(damage.spellId or 0)
        .. ":" .. (damage.periodic and "periodic" or "direct")
    if mode == "target" then
        key = key .. ":" .. tostring(damage.destinationGUID or damage.destinationName or "unknown")
    end
    local previous = self.iconHistory[key]
    local burstWindow = damage.periodic and 0.3 or 0.18
    if not previous or now - previous >= burstWindow then
        self.iconHistory[key] = now
        return true
    end
    return false
end
