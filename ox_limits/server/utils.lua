local function DebugLog(message)
    if Config.Debug then
        print('[ox_limits:DEBUG] ' .. message)
    end
end

local function IsPlayerVIP(source)
    -- Check if player has VIP status
    -- This can be integrated with your VIP system
    -- Example implementations:
    
    -- Method 1: Check for ace permissions
    if IsPlayerAceAllowed(source, 'vip.access') then
        return true
    end
    
    -- Method 2: Check ESX group (if using ESX)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        local group = xPlayer.getGroup()
        if group == 'vip' or group == 'premium' or group == 'donator' then
            return true
        end
    end
    
    -- Method 3: Database check (example)
    -- local result = MySQL.query.await('SELECT vip FROM users WHERE identifier = ?', {
    --     GetPlayerIdentifierByType(source, 'license')
    -- })
    -- if result and result[1] and result[1].vip == 1 then
    --     return true
    -- end
    
    return false
end

local function GetPlayerJob(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        return xPlayer.job.name
    end
    return nil
end

local function IsPlayerInNonLootableJob(source)
    local job = GetPlayerJob(source)
    if job and Config.NonLootableJobs[job] then
        return true
    end
    return false
end

local function CanTransferItem(source, itemName)
    -- Check if item is in untransferable list
    if Config.UntransferableItems[itemName] ~= nil and Config.UntransferableItems[itemName] == true then
        -- Item is marked as untransferable, check if player's job has special permission
        local job = GetPlayerJob(source)
        if job and Config.TransferableItemsForJobs[job] then
            if Config.TransferableItemsForJobs[job][itemName] then
                -- Job has permission to transfer this normally untransferable item
                return true
            end
        end
        -- Item is untransferable and no job permission
        return false
    end

    -- Item is not in untransferable list, allow transfer
    return true
end

local function GetItemLimit(itemName, limitType, isVIP)
    if not Config.Limits[limitType] then
        return nil
    end
    
    local itemLimit = Config.Limits[limitType][itemName]
    if not itemLimit then
        return nil
    end
    
    return isVIP and itemLimit.vip or itemLimit.normal
end

local function CanAddItemToInventory(inventoryId, itemName, amount, limitType)
    local inventory = exports.ox_inventory:GetInventory(inventoryId)
    if not inventory then
        return false, 'Inventory not found'
    end
    
    -- Get current item count
    local currentCount = exports.ox_inventory:GetItemCount(inventoryId, itemName) or 0
    
    -- Determine if player is VIP (only for player inventories)
    local isVIP = false
    if type(inventoryId) == 'number' then
        isVIP = IsPlayerVIP(inventoryId)
    end
    
    -- Get limit for this item
    local limit = GetItemLimit(itemName, limitType, isVIP)
    
    -- If no limit is set, allow the item
    if not limit then
        return true
    end
    
    -- Check if adding this amount would exceed the limit
    if currentCount + amount > limit then
        return false, string.format('Limit exceeded. Max allowed: %d, Current: %d', limit, currentCount)
    end
    
    return true
end

local function GetPlayerCoords(source)
    local ped = GetPlayerPed(source)
    if ped and DoesEntityExist(ped) then
        return GetEntityCoords(ped)
    end
    return nil
end

local function GetDistanceBetweenPlayers(source1, source2)
    local coords1 = GetPlayerCoords(source1)
    local coords2 = GetPlayerCoords(source2)
    
    if coords1 and coords2 then
        return #(coords1 - coords2)
    end
    
    return nil
end

local function NotifyPlayer(source, message, type)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Inventory Limits',
        description = message,
        type = type or 'info',
        position = 'top'
    })
end

return {
    DebugLog = DebugLog,
    IsPlayerVIP = IsPlayerVIP,
    GetPlayerJob = GetPlayerJob,
    IsPlayerInNonLootableJob = IsPlayerInNonLootableJob,
    CanTransferItem = CanTransferItem,
    GetItemLimit = GetItemLimit,
    CanAddItemToInventory = CanAddItemToInventory,
    GetPlayerCoords = GetPlayerCoords,
    GetDistanceBetweenPlayers = GetDistanceBetweenPlayers,
    NotifyPlayer = NotifyPlayer
}

