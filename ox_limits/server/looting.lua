local Utils = require 'server.utils'

-- Store recent attackers and killers
local recentAttackers = {}
local killerVictims = {}

-- Clean up old attacker records every 5 minutes
CreateThread(function()
    while true do
        Wait(300000) -- 5 minutes
        local currentTime = os.time()
        
        for victimId, data in pairs(recentAttackers) do
            if currentTime - data.timestamp > 120 then -- 2 minutes
                recentAttackers[victimId] = nil
            end
        end
        
        for victimId, data in pairs(killerVictims) do
            if currentTime - data.timestamp > 120 then -- 2 minutes
                killerVictims[victimId] = nil
            end
        end
    end
end)

-- Register attacker
RegisterNetEvent('ox_limits:server:registerAttacker', function(victimId, distance)
    local attackerId = source
    
    Utils.DebugLog(string.format('Registering attacker: %d attacked %d from distance %.2f', attackerId, victimId, distance))
    
    if not recentAttackers[victimId] then
        recentAttackers[victimId] = {
            attackers = {},
            timestamp = os.time()
        }
    end
    
    recentAttackers[victimId].attackers[attackerId] = {
        distance = distance,
        timestamp = os.time()
    }
    recentAttackers[victimId].timestamp = os.time()
end)

-- Register killer-victim relationship
RegisterNetEvent('ox_limits:server:registerKillerVictim', function(victimId, distance)
    local killerId = source
    
    Utils.DebugLog(string.format('Registering killer: %d killed %d from distance %.2f', killerId, victimId, distance))
    
    killerVictims[victimId] = {
        killerId = killerId,
        distance = distance,
        timestamp = os.time()
    }
end)

-- Client reports recent attackers when they die
RegisterNetEvent('ox_limits:server:reportRecentAttackers', function(attackerIds)
    local victimId = source
    
    Utils.DebugLog(string.format('Victim %d reporting %d recent attackers', victimId, #attackerIds))
    
    if not recentAttackers[victimId] then
        recentAttackers[victimId] = {
            attackers = {},
            timestamp = os.time()
        }
    end
    
    for _, attackerId in ipairs(attackerIds) do
        if not recentAttackers[victimId].attackers[attackerId] then
            recentAttackers[victimId].attackers[attackerId] = {
                distance = 0,
                timestamp = os.time()
            }
        end
    end
end)

-- Check if player can loot victim
local function CanLootVictim(robberId, victimId, isDead)
    -- Check if victim is in a non-lootable job
    if Utils.IsPlayerInNonLootableJob(victimId) then
        Utils.DebugLog(string.format('Player %d cannot loot %d - victim is in non-lootable job', robberId, victimId))
        return false, 'This person cannot be looted'
    end
    
    -- If victim is dead, check if robber was involved in the kill
    if isDead then
        -- Check if robber was the killer
        local killerData = killerVictims[victimId]
        if killerData and killerData.killerId == robberId then
            Utils.DebugLog(string.format('Player %d can loot %d - was the killer', robberId, victimId))
            return true
        end
        
        -- Check if robber was a recent attacker
        local attackerData = recentAttackers[victimId]
        if attackerData and attackerData.attackers[robberId] then
            Utils.DebugLog(string.format('Player %d can loot %d - was a recent attacker', robberId, victimId))
            return true
        end
        
        Utils.DebugLog(string.format('Player %d cannot loot %d - not involved in kill', robberId, victimId))
        return false, 'You were not involved in this kill'
    end
    
    return true
end

-- Get lootable items from victim based on state
local function GetLootableItems(victimId, isDead)
    local victimInventory = exports.ox_inventory:GetInventory(victimId)
    if not victimInventory then
        return {}
    end
    
    local lootableItems = {}
    local limitType = isDead and 'dead' or 'handsup'
    local isVIP = Utils.IsPlayerVIP(victimId)
    
    for slot, item in pairs(victimInventory.items) do
        if item and item.name then
            -- Check if item is untransferable (cannot be stolen)
            if Config.UntransferableItems[item.name] ~= nil and Config.UntransferableItems[item.name] == true then
                -- Item is untransferable, skip it
                Utils.DebugLog(string.format('Skipping untransferable item: %s', item.name))
            else
                -- Item can be transferred, check limits
                local limit = Utils.GetItemLimit(item.name, limitType, isVIP)

                if limit and limit > 0 then
                    local amountToTake = math.min(item.count, limit)
                    table.insert(lootableItems, {
                        name = item.name,
                        label = item.label,
                        count = amountToTake,
                        slot = slot
                    })
                end
            end
        end
    end
    
    return lootableItems
end

return {
    CanLootVictim = CanLootVictim,
    GetLootableItems = GetLootableItems
}

