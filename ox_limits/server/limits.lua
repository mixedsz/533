local Utils = require 'server.utils'
local ox_inventory = exports.ox_inventory

-- Global counter to track hook calls
local hookCallCount = 0

-- Hook into ox_inventory to enforce limits
local function EnforceLimits()
    Utils.DebugLog('Registering ox_inventory hooks...')

    -- Hook into swapItems to prevent moving items that exceed limits
    local swapHook = ox_inventory:registerHook('swapItems', function(payload)
        hookCallCount = hookCallCount + 1
        print(string.format('^3[ox_limits]^7 === swapItems hook triggered === (Call #%d)', hookCallCount))
        Utils.DebugLog('=== swapItems hook triggered ===')

        -- Verbose payload logging (disabled by default - uncomment to debug payload structure)
        -- if Config.Debug then
        --     print('^3[ox_limits:DEBUG]^7 Payload structure:')
        --     for k, v in pairs(payload) do
        --         if type(v) == 'table' then
        --             print(string.format('  %s = table:', k))
        --             for k2, v2 in pairs(v) do
        --                 print(string.format('    %s = %s', k2, tostring(v2)))
        --             end
        --         else
        --             print(string.format('  %s = %s (type: %s)', k, tostring(v), type(v)))
        --         end
        --     end
        -- end

        -- Extract data based on actual payload structure
        local source = payload.source
        local action = payload.action
        local fromInventory = payload.fromInventory
        local toInventory = payload.toInventory
        local fromType = payload.fromType
        local toType = payload.toType
        local fromSlot = payload.fromSlot
        local toSlot = payload.toSlot
        local count = payload.count

        -- fromSlot can be a table or a number - extract the slot number
        local fromSlotNumber = type(fromSlot) == 'table' and fromSlot.slot or fromSlot
        local toSlotNumber = type(toSlot) == 'table' and toSlot.slot or toSlot

        Utils.DebugLog(string.format('Source: %s, Action: %s', tostring(source), tostring(action)))
        Utils.DebugLog(string.format('From: %s (type: %s) slot %s, To: %s (type: %s) slot %s',
            tostring(fromInventory),
            tostring(fromType),
            tostring(fromSlotNumber),
            tostring(toInventory),
            tostring(toType),
            tostring(toSlotNumber)
        ))

        if not fromInventory or not toInventory then
            Utils.DebugLog('Missing inventory data, allowing')
            return true
        end

        -- Get the item being moved - use the slot number
        local item = exports.ox_inventory:GetSlot(fromInventory, fromSlotNumber)
        if not item then
            Utils.DebugLog(string.format('No item in slot %s of inventory %s, allowing', tostring(fromSlotNumber), tostring(fromInventory)))
            return true -- Allow if no item found
        end

        Utils.DebugLog(string.format('Item: %s, Count: %d', item.name, count or item.count))

        -- Check if item is untransferable when moving between different inventories
        if fromInventory ~= toInventory then
            Utils.DebugLog(string.format('Moving between different inventories, checking if %s is untransferable', item.name))

            -- Check if item is in untransferable list
            local isUntransferable = Config.UntransferableItems[item.name]
            Utils.DebugLog(string.format('Config.UntransferableItems[%s] = %s', item.name, tostring(isUntransferable)))

            if isUntransferable ~= nil and isUntransferable == true then
                Utils.DebugLog(string.format('%s is marked as untransferable, checking job permissions', item.name))

                -- Check if player has job-specific permission to transfer
                local canTransfer = false
                if source and type(source) == 'number' then
                    canTransfer = Utils.CanTransferItem(source, item.name)
                    Utils.DebugLog(string.format('CanTransferItem result for player %d: %s', source, tostring(canTransfer)))
                end

                if not canTransfer then
                    if source and type(source) == 'number' then
                        Utils.NotifyPlayer(source, string.format('%s cannot be transferred', item.label or item.name), 'error')
                    end
                    Utils.DebugLog(string.format('BLOCKED transfer of untransferable item: %s', item.name))
                    print(string.format('^1[ox_limits]^7 BLOCKED: Player %s tried to transfer %s', tostring(source), item.name))
                    return false
                end
            else
                Utils.DebugLog(string.format('%s is not untransferable or is set to false', item.name))
            end
        else
            Utils.DebugLog('Moving within same inventory, allowing')
        end

        -- Determine the limit type based on inventory type
        local limitType = nil

        if toType == 'glovebox' then
            limitType = 'glovebox'
        elseif toType == 'trunk' then
            limitType = 'trunk'
        elseif toType == 'stash' then
            limitType = 'stash'
        elseif toType == 'container' and string.match(tostring(toInventory), 'duffel') then
            limitType = 'duffle'
        end

        -- If moving to a limited inventory type, check limits
        if limitType then
            local isVIP = false
            if source and type(source) == 'number' then
                isVIP = Utils.IsPlayerVIP(source)
            end

            local limit = Utils.GetItemLimit(item.name, limitType, isVIP)

            if limit then
                local currentCount = exports.ox_inventory:GetItemCount(toInventory, item.name) or 0
                local newCount = currentCount + count

                if newCount > limit then
                    if source and type(source) == 'number' then
                        Utils.NotifyPlayer(source, string.format('Cannot add %s. Limit: %d, Current: %d', item.label or item.name, limit, currentCount), 'error')
                    end
                    return false
                end
            end
        end

        -- Check duffle blacklist
        if limitType == 'duffle' and Config.DuffleBlacklist[item.name] then
            if source and type(source) == 'number' then
                Utils.NotifyPlayer(source, string.format('%s cannot be placed in a duffle bag', item.label or item.name), 'error')
            end
            return false
        end
        
        return true
    end, {
        print = true
        -- No filters - we want to check ALL items
    })

    Utils.DebugLog('swapItems hook registered: ' .. tostring(swapHook))

    -- Hook into createItem to prevent creating items that exceed limits
    local createHook = ox_inventory:registerHook('createItem', function(payload)
        local inventoryId = payload.inventoryId
        local item = payload.item
        local count = payload.count or 1
        
        if not inventoryId or not item then
            return true
        end
        
        local inventory = exports.ox_inventory:GetInventory(inventoryId)
        if not inventory then
            return true
        end
        
        -- Determine limit type
        local limitType = nil
        
        if inventory.type == 'glovebox' then
            limitType = 'glovebox'
        elseif inventory.type == 'trunk' then
            limitType = 'trunk'
        elseif inventory.type == 'stash' then
            limitType = 'stash'
        elseif inventory.type == 'container' and string.match(inventoryId, 'duffel') then
            limitType = 'duffle'
        end
        
        if limitType then
            local isVIP = false
            if type(inventoryId) == 'number' then
                isVIP = Utils.IsPlayerVIP(inventoryId)
            end
            
            local itemName = type(item) == 'table' and item.name or item
            local limit = Utils.GetItemLimit(itemName, limitType, isVIP)
            
            if limit then
                local currentCount = exports.ox_inventory:GetItemCount(inventoryId, itemName) or 0
                local newCount = currentCount + count
                
                if newCount > limit then
                    if type(inventoryId) == 'number' then
                        Utils.NotifyPlayer(inventoryId, string.format('Cannot add item. Limit exceeded: %d', limit), 'error')
                    end
                    return false
                end
            end
            
            -- Check duffle blacklist
            if limitType == 'duffle' and Config.DuffleBlacklist[itemName] then
                if type(inventoryId) == 'number' then
                    Utils.NotifyPlayer(inventoryId, 'This item cannot be placed in a duffle bag', 'error')
                end
                return false
            end
        end
        
        return true
    end, {
        print = true
    })

    Utils.DebugLog('createItem hook registered: ' .. tostring(createHook))

    -- Hook into buyItem to prevent buying untransferable items (if they somehow get in shops)
    local buyHook = ox_inventory:registerHook('buyItem', function(payload)
        local source = payload.source
        local item = payload.item
        local count = payload.count or 1

        if not source or not item then
            return true
        end

        local itemName = type(item) == 'table' and item.name or item

        -- Check if item is untransferable
        if Config.UntransferableItems[itemName] ~= nil and Config.UntransferableItems[itemName] == true then
            Utils.NotifyPlayer(source, string.format('%s cannot be purchased', itemName), 'error')
            Utils.DebugLog(string.format('Blocked purchase of untransferable item: %s', itemName))
            return false
        end

        return true
    end, {
        print = true
    })

    Utils.DebugLog('buyItem hook registered: ' .. tostring(buyHook))

    print('^2[ox_limits]^7 All hooks registered successfully')
    print('^2[ox_limits]^7 - swapItems hook: ' .. tostring(swapHook))
    print('^2[ox_limits]^7 - createItem hook: ' .. tostring(createHook))
    print('^2[ox_limits]^7 - buyItem hook: ' .. tostring(buyHook))

    Utils.DebugLog('Inventory limits system initialized')
end

-- Export function to check if item can be swapped (for external use)
local function CanSwapItem(source, item, fromInventory, toInventory)
    if not item or not fromInventory or not toInventory then
        return false, 'Invalid parameters'
    end

    -- Check if item is untransferable when moving between different inventories
    if fromInventory ~= toInventory then
        if Config.UntransferableItems[item.name] ~= nil and Config.UntransferableItems[item.name] == true then
            local canTransfer = Utils.CanTransferItem(source, item.name)
            if not canTransfer then
                return false, string.format('%s cannot be transferred', item.label or item.name)
            end
        end
    end

    return true
end

-- Function to get hook call count (for debugging)
local function GetHookCallCount()
    return hookCallCount
end

return {
    EnforceLimits = EnforceLimits,
    CanSwapItem = CanSwapItem,
    GetHookCallCount = GetHookCallCount
}

