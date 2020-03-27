Bestiary = {}

dofile('data/modules/scripts/bestiary/assets.lua')

Bestiary.S_Packets = {
    SendBestiaryData = 0xd5,
    SendBestiaryOverview = 0xd6,
    SendBestiaryMonsterData = 0xd7,
	SendBestiaryCharmsData = 0xd8
}

Bestiary.C_Packets = {
    RequestBestiaryData = 0xe1,
    RequestBestiaryOverview = 0xe2,
    RequestBestiaryMonsterData = 0xe3,
	RequestBestiaryCharmUnlock = 0xe4
}

Bestiary.findRaceByName = function(race)
    local races = Bestiary.Races
    for i = 1, #races do
        if (races[i].name == race) then
            return races[i]
        end
    end
    return false
end

Bestiary.getRaceByMonsterId = function(monsterId)
    local races = Bestiary.Races
    for i = 1, #races do
        if table.contains(races[i].monsters, monsterId) then
            return races[i].name
        end
    end
    return false
end

Bestiary.sendCreatures = function (playerId, msg)
    local player = Player(playerId)
    if not player then
        return true
    end

    local unknown = msg:getByte()
    local raceName = msg:getString()

    local race = Bestiary.findRaceByName(raceName)
    if not race then
        print("> [Bestiary]: race was not found")
        return true
    end

    local msg = NetworkMessage()
    msg:addByte(Bestiary.S_Packets.SendBestiaryOverview)
    msg:addString(race.name) -- race name
    msg:addU16(#race.monsters) -- monster count
    for i = 1, #race.monsters do
        msg:addU16(race.monsters[i]) -- monster name
        msg:addU16(0x01) -- monster kill count (starts by 1)
    end

    msg:sendToPlayer(player)
end

Bestiary.sendRaces = function(playerId, msg)
    local player = Player(playerId)
    if not player then
        return true
    end
    local msg = NetworkMessage()
    msg:addByte(Bestiary.S_Packets.SendBestiaryData)
    msg:addU16(#Bestiary.Races)
    for k, race in ipairs(Bestiary.Races) do
        msg:addString(race.name)
        msg:addU16(#race.monsters)
        msg:addU16(math.random(#race.monsters)) -- TODO current
    end
    msg:sendToPlayer(player)
end

Bestiary.sendCharms = function(playerId, msg)
    local player = Player(playerId)
    if not player then
        return true
    end
    local msg = NetworkMessage()
    msg:addByte(Bestiary.S_Packets.SendBestiaryCharmsData)
	msg:addU32(50000) --Total charm points TODO
    msg:addByte(#Bestiary.Charms)
    for k, charm in ipairs(Bestiary.Charms) do
		msg:addByte(k) -- id
        msg:addString(charm.name) --name
        msg:addString(charm.description) --description
        msg:addByte(0) --unknown (unlocked?) 0 ok | 1-2 n�o faz nada | 3+ n�o testado
		msg:addU16(charm.points) --charm points needed charm.points
        msg:addByte(0) --selecionado o monsto, da pra resetar? 0 : custo em charms | 1 : custo em gp | 2+ n�o testado
        msg:addByte(0) --unknown (unlocked?) 0 ok | 1 crasha | 2+ n�o testado
    end
	msg:addByte(16)
	msg:addU16(0)
    msg:sendToPlayer(player)
end

Bestiary.sendBuyCharmRune = function (playerId, msg)
    local player = Player(playerId)
    if not player then
        return true
    end

    local runeID = msg:getByte()
    
    print("> [Bestiary]: Trying to buy rune: "..runeID)
    return true
end

Bestiary.sendMonsterData = function(playerId, msg)
    local player = Player(playerId)
    if not player then
        return true
    end

    local monsterId = msg:getU16()
    local race = Bestiary.getRaceByMonsterId(monsterId)
    if not race then
        print("> [Bestiary]: race was not found")
        return true
    end

    local bestiaryMonster = Bestiary.Monsters[monsterId]
    if not bestiaryMonster then
        print("> [Bestiary]: monster was not found")
        return true
    end

    local monster = MonsterType(bestiaryMonster.name)
    if not monster then
        print("> [Bestiary]: monstertype was not found")
        return true
    end

    -- TODO
    local firstMaxKill =  bestiaryMonster.FirstUnlock
    local secondMaxKill =  bestiaryMonster.SecondUnlock
    local thirdMaxKill = bestiaryMonster.toKill
    local killCounter = 350

    local msg = NetworkMessage()
    msg:addByte(Bestiary.S_Packets.SendBestiaryMonsterData)
    msg:addU16(monsterId)
    msg:addString(race)

    local currentLevel = 1
    if killCounter < firstMaxKill then
        currentLevel = 1
    elseif killCounter < secondMaxKill then
        currentLevel = 2
    elseif killCounter < thirdMaxKill then
        currentLevel = 3
    else
        currentLevel = 4
    end

    msg:addByte(currentLevel) 
    
    -- TODO: counter
    msg:addU32(killCounter) -- kill count
    msg:addU16(firstMaxKill) -- max kill first phase
    msg:addU16(secondMaxKill)  -- max kill second phase
    msg:addU16(thirdMaxKill)  -- max kill third phase

    msg:addByte(bestiaryMonster.Stars)  -- Difficult
    msg:addByte(1) -- TODO: occourrence
    local lootSize = #monster:getLoot()
    msg:addByte(lootSize)

    if lootSize > 0 then
        local loots = monster:getLoot()
        for i = 1, lootSize do
            local loot = loots[i]
            local item = ItemType(loot.itemId)
            if item then
                local type = 0
                local difficult = Bestiary.calculateDifficult(loot.chance)

                if killCounter == 0 then
                    msg:addU16(0x00)
                    msg:addByte(0x0) -- 0 = normal loot   /  1 = special event loot
                    msg:addByte(difficult)
                else 
                    msg:addItemId(loot.itemId)
                    msg:addByte(difficult)
                    msg:addByte(0x0) -- 0 = normal loot   /  1 = special event loot
                    msg:addString(item:getName())
                    msg:addByte(item:isStackable() and 0x1 or 0x0)
                end 
            end
        end
    end

    if currentLevel > 1 then
        msg:addU16(bestiaryMonster.CharmsPoints)
        local attackMode = 0
        if monster:isPassive() then
            attackMode = 2
        elseif monster:targetDistance() then
            attackMode = 1
        end

        msg:addByte(attackMode) -- 0 = meele / 1 = distance / 2 = doenst attack
        msg:addByte(0x2) -- flag for cast spells
        msg:addU32(monster:maxHealth())
        msg:addU32(monster:experience())
        msg:addU16(monster:baseSpeed())
        msg:addU16(monster:armor())
    end

    if currentLevel > 2 then
        local monsterElements = Bestiary.getMonsterElements(monster)

        -- elements size
        msg:addByte(#monsterElements)
        local i = 0
        for _, value in pairs(monsterElements) do
            -- elements id
            msg:addByte(i)

            -- element percent
            msg:addU16(value)

            i = i + 1
        end
        
        msg:addU16(1) -- enable or disable description
        msg:addString("otservbr global is the fucking awesome project")
    end

    if currentLevel > 3 then
        -- charm things
        msg:addByte(0)
        msg:addByte(0)
    end

    msg:sendToPlayer(player)
end

Bestiary.getMonsterElements = function (monster) 
    local elements = monster:getElementList()
    local monsterElements = Bestiary.getDefaultElements()

    for element, value in pairs(elements) do
        if monsterElements[element] then
            local percent = 100 + tonumber(value)
            monsterElements[element] = percent
        end
    end

    return monsterElements
end

Bestiary.calculateDifficult = function (chance)
    chance = chance / 1000

    if chance < 0.2 then
       return 4
    end 

    if chance < 1 then
       return 3
    end 

    if chance < 5 then
       return 2
    end 

    if chance < 25 then
        return 1
    end

    return 0
end

Bestiary.createEmptyLootSlot = function (msg, difficult, type)
    msg:addU16(0x0)
    msg:addByte(difficult)
    msg:addByte(type)
end

Bestiary.createLootSlot = function (msg, itemId, itemName, difficult, type, isStackable)
    msg:addItemId(itemId)
    msg:addByte(difficult)
    msg:addString(itemName)
    msg:addByte(type)
    msg:addByte(isStackable and 0x0 or 0x1)
end

function onRecvbyte(player, msg, byte)
    if (byte == Bestiary.C_Packets.RequestBestiaryData) then
        Bestiary.sendRaces(player:getId())
        Bestiary.sendCharms(player:getId())
    elseif (byte == Bestiary.C_Packets.RequestBestiaryOverview) then
        Bestiary.sendCreatures(player:getId(), msg)
    elseif (byte == Bestiary.C_Packets.RequestBestiaryMonsterData) then
        Bestiary.sendMonsterData(player:getId(), msg)
    elseif (byte == Bestiary.C_Packets.RequestBestiaryCharmUnlock) then
        Bestiary.sendBuyCharmRune(player:getId(), msg)
		--TestarBytes(player,msg)
    end
end



function TestarBytes(player, msg)
	print("Bytes Test Start")
	for i= 1, 16 do
		print(i.." "..msg:getByte())
	end
	print("Bytes Test End")
end