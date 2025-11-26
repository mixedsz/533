local Utils = require 'server.utils'
local Looting = require 'server.looting'

-- Store active robberies to prevent spam
local activeRobberies = {}
local robberyTimeout = 30000 -- 30 seconds between robberies

-- Clean up old robbery records
CreateThread(function()
    while true do
        Wait(60000) -- 1 minute
        local currentTime = GetGameTimer()
        
        for key, timestamp in pairs(activeRobberies) do
            if currentTime - timestamp > robberyTimeout then
                activeRobberies[key] = nil
            end
        end
    end
end)

-- Main robbery event
RegisterNetEvent('ox_limits:server:rob_player', function(data)
    local robberId = source
    local victimId = data.playerId
    local isDead = data.dead
    
    if not robberId or not victimId then
        Utils.DebugLog('Invalid robbery attempt - missing player IDs')
        return
    end
    
    -- Validate players exist
    if not GetPlayerPed(robberId) or not GetPlayerPed(victimId) then
        Utils.NotifyPlayer(robberId, 'Invalid target', 'error')
        return
    end
    
    -- Check if robbery is on cooldown
    local robberyKey = string.format('%d_%d', robberId, victimId)
    if activeRobberies[robberyKey] then
        local timeLeft = math.ceil((robberyTimeout - (GetGameTimer() - activeRobberies[robberyKey])) / 1000)
        Utils.NotifyPlayer(robberId, string.format('You must wait %d seconds before robbing this person again', timeLeft), 'error')
        return
    end
    
    -- Check distance between players
    local distance = Utils.GetDistanceBetweenPlayers(robberId, victimId)
    if not distance or distance > 3.0 then
        Utils.NotifyPlayer(robberId, 'Target is too far away', 'error')
        return
    end
    
    Utils.DebugLog(string.format('Player %d attempting to rob %d (dead: %s, distance: %.2f)', robberId, victimId, tostring(isDead), distance))
    
    -- Validate robbery conditions
    if not isDead then
        -- Check if robber is armed
        local isArmed = lib.callback.await('ox_limits:client:validate_armed', robberId)
        if not isArmed then
            Utils.NotifyPlayer(robberId, 'You need a weapon to rob someone', 'error')
            return
        end
        
        -- Check if victim has hands up
        local hasHandsUp = lib.callback.await('ox_limits:client:validate_handsup', victimId)
        if not hasHandsUp then
            Utils.NotifyPlayer(robberId, 'Target must have their hands up', 'error')
            return
        end
    end
    
    -- Check if victim can be looted
    local canLoot, reason = Looting.CanLootVictim(robberId, victimId, isDead)
    if not canLoot then
        Utils.NotifyPlayer(robberId, reason, 'error')
        return
    end
    
    -- Get lootable items
    local lootableItems = Looting.GetLootableItems(victimId, isDead)
    
    if #lootableItems == 0 then
        Utils.NotifyPlayer(robberId, 'Target has nothing to steal', 'error')
        return
    end
    
    -- Set robbery cooldown
    activeRobberies[robberyKey] = GetGameTimer()
    
    -- Create selection menu for robber
    local options = {}
    
    for _, item in ipairs(lootableItems) do
        table.insert(options, {
            title = item.label or item.name,
            description = string.format('Amount: %d', item.count),
            icon = 'box',
            onSelect = function()
                -- Attempt to transfer item
                local success = TransferItem(victimId, robberId, item.name, item.count, item.slot)
                
                if success then
                    Utils.NotifyPlayer(robberId, string.format('You stole %dx %s', item.count, item.label or item.name), 'success')
                    Utils.NotifyPlayer(victimId, string.format('You were robbed of %dx %s', item.count, item.label or item.name), 'error')
                    
                    Utils.DebugLog(string.format('Player %d successfully robbed %dx %s from %d', robberId, item.count, item.name, victimId))
                else
                    Utils.NotifyPlayer(robberId, 'Failed to steal item', 'error')
                end
            end
        })
    end
    
    -- Show menu to robber
    lib.registerContext({
        id = 'robbery_menu',
        title = 'Rob Player',
        options = options
    })
    
    TriggerClientEvent('ox_lib:showContext', robberId, 'robbery_menu')
end)

-- Transfer item from victim to robber
function TransferItem(fromId, toId, itemName, count, slot)
    local fromInventory = exports.ox_inventory:GetInventory(fromId)
    local toInventory = exports.ox_inventory:GetInventory(toId)
    
    if not fromInventory or not toInventory then
        Utils.DebugLog('Failed to get inventories for transfer')
        return false
    end
    
    -- Check if victim still has the item
    local item = exports.ox_inventory:GetSlot(fromId, slot)
    if not item or item.name ~= itemName then
        Utils.NotifyPlayer(toId, 'Item no longer available', 'error')
        return false
    end
    
    -- Calculate actual amount to transfer
    local actualCount = math.min(count, item.count)
    
    -- Check if robber has space
    local canAdd = exports.ox_inventory:CanCarryItem(toId, itemName, actualCount)
    if not canAdd then
        Utils.NotifyPlayer(toId, 'You cannot carry this item', 'error')
        return false
    end
    
    -- Remove from victim
    local removed = exports.ox_inventory:RemoveItem(fromId, itemName, actualCount, nil, slot)
    if not removed then
        Utils.DebugLog('Failed to remove item from victim')
        return false
    end
    
    -- Add to robber
    local added = exports.ox_inventory:AddItem(toId, itemName, actualCount)
    if not added then
        -- Rollback - give item back to victim
        exports.ox_inventory:AddItem(fromId, itemName, actualCount)
        Utils.DebugLog('Failed to add item to robber, rolled back')
        return false
    end
    
    return true
end

