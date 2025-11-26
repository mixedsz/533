local Utils = require 'server.utils'
local Limits = require 'server.limits'

-- Initialize the limits system
CreateThread(function()
    print('^3[ox_limits]^7 Waiting for ox_inventory to start...')

    -- Wait for ox_inventory to be ready
    local attempts = 0
    while GetResourceState('ox_inventory') ~= 'started' do
        Wait(100)
        attempts = attempts + 1
        if attempts > 100 then
            print('^1[ox_limits]^7 ERROR: ox_inventory failed to start after 10 seconds!')
            return
        end
    end

    print('^2[ox_limits]^7 ox_inventory detected, waiting for full initialization...')
    Wait(2000) -- Additional wait to ensure ox_inventory is fully loaded

    -- Initialize limit enforcement
    print('^3[ox_limits]^7 Initializing limit enforcement...')
    Limits.EnforceLimits()

    print('^2[ox_limits]^7 Successfully initialized inventory limits system')
    print('^2[ox_limits]^7 Debug mode: ' .. tostring(Config.Debug))
end)

-- Export utility functions for other resources
exports('IsPlayerVIP', Utils.IsPlayerVIP)
exports('GetPlayerJob', Utils.GetPlayerJob)
exports('CanTransferItem', Utils.CanTransferItem)
exports('GetItemLimit', Utils.GetItemLimit)
exports('CanSwapItem', Limits.CanSwapItem)

-- Admin command to check player limits (optional)
RegisterCommand('checklimits', function(source, args)
    if source == 0 then
        print('This command can only be used in-game')
        return
    end
    
    -- Check if player has admin permission
    if not IsPlayerAceAllowed(source, 'command.checklimits') then
        Utils.NotifyPlayer(source, 'You do not have permission to use this command', 'error')
        return
    end
    
    local targetId = tonumber(args[1]) or source
    
    if not GetPlayerPed(targetId) then
        Utils.NotifyPlayer(source, 'Invalid player ID', 'error')
        return
    end
    
    local isVIP = Utils.IsPlayerVIP(targetId)
    local job = Utils.GetPlayerJob(targetId)
    
    Utils.NotifyPlayer(source, string.format('Player %d - VIP: %s, Job: %s', targetId, tostring(isVIP), job or 'none'), 'info')
end, false)

-- Admin command to reload config (optional)
RegisterCommand('reloadlimits', function(source)
    if source ~= 0 and not IsPlayerAceAllowed(source, 'command.reloadlimits') then
        Utils.NotifyPlayer(source, 'You do not have permission to use this command', 'error')
        return
    end
    
    -- Reload the config
    local success, err = pcall(function()
        -- Force reload of config.lua
        package.loaded['config'] = nil
        Config = require('config')
    end)
    
    if success then
        if source == 0 then
            print('^2[ox_limits]^7 Configuration reloaded successfully')
        else
            Utils.NotifyPlayer(source, 'Configuration reloaded successfully', 'success')
        end
    else
        if source == 0 then
            print('^1[ox_limits]^7 Failed to reload configuration: ' .. tostring(err))
        else
            Utils.NotifyPlayer(source, 'Failed to reload configuration', 'error')
        end
    end
end, false)

-- Debug command to test limits
RegisterCommand('testlimit', function(source, args)
    if not Config.Debug then
        return
    end
    
    if source == 0 then
        print('This command can only be used in-game')
        return
    end
    
    local itemName = args[1]
    local limitType = args[2] or 'dead'
    
    if not itemName then
        Utils.NotifyPlayer(source, 'Usage: /testlimit <item_name> [limit_type]', 'error')
        return
    end
    
    local isVIP = Utils.IsPlayerVIP(source)
    local limit = Utils.GetItemLimit(itemName, limitType, isVIP)
    
    if limit then
        Utils.NotifyPlayer(source, string.format('%s limit for %s: %d (VIP: %s)', limitType, itemName, limit, tostring(isVIP)), 'info')
    else
        Utils.NotifyPlayer(source, string.format('No limit found for %s in %s', itemName, limitType), 'info')
    end
end, false)

-- Test command to force trigger a hook test
RegisterCommand('testhook', function(source)
    if source == 0 then
        print('This command can only be used in-game')
        return
    end

    print('^3[ox_limits:TEST]^7 Testing if hooks can be triggered manually...')

    -- Try to get player inventory
    local inventory = exports.ox_inventory:GetInventory(source)
    if inventory then
        print('^2[ox_limits:TEST]^7 Player inventory found')
        print('^2[ox_limits:TEST]^7 Inventory ID: ' .. tostring(inventory.id))
        print('^2[ox_limits:TEST]^7 Inventory type: ' .. tostring(inventory.type))

        -- Check if player has any items
        if inventory.items then
            local itemCount = 0
            for slot, item in pairs(inventory.items) do
                if item then
                    itemCount = itemCount + 1
                    print(string.format('^2[ox_limits:TEST]^7 Slot %d: %s x%d', slot, item.name, item.count))
                end
            end
            print(string.format('^2[ox_limits:TEST]^7 Total items: %d', itemCount))
        end
    else
        print('^1[ox_limits:TEST]^7 ERROR: Could not get player inventory')
    end

    Utils.NotifyPlayer(source, 'Hook test completed - check console', 'info')
end, false)

-- Test command to verify hooks are working
RegisterCommand('testoxlimits', function(source)
    if source == 0 then
        print('This command can only be used in-game')
        return
    end

    if not IsPlayerAceAllowed(source, 'command.testoxlimits') and not Config.Debug then
        Utils.NotifyPlayer(source, 'You do not have permission to use this command', 'error')
        return
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        Utils.NotifyPlayer(source, 'Player not found', 'error')
        return
    end

    -- Test 1: Check if ox_inventory is accessible
    local oxInvState = GetResourceState('ox_inventory')
    print(string.format('[ox_limits:TEST] ox_inventory state: %s', oxInvState))

    -- Test 2: Check player inventory
    local inventory = exports.ox_inventory:GetInventory(source)
    print(string.format('[ox_limits:TEST] Player inventory: %s', inventory and 'Found' or 'Not Found'))

    -- Test 3: Check VIP status
    local isVIP = Utils.IsPlayerVIP(source)
    print(string.format('[ox_limits:TEST] Player VIP status: %s', tostring(isVIP)))

    -- Test 4: Check job
    local job = Utils.GetPlayerJob(source)
    print(string.format('[ox_limits:TEST] Player job: %s', job or 'none'))

    -- Test 5: Check untransferable items config
    print('[ox_limits:TEST] Untransferable items:')
    for item, value in pairs(Config.UntransferableItems) do
        if value == true then
            print(string.format('  - %s: %s', item, tostring(value)))
        end
    end

    -- Test 6: Test CanTransferItem function
    local canTransferToken = Utils.CanTransferItem(source, 'donortoken1')
    print(string.format('[ox_limits:TEST] Can transfer donortoken1: %s', tostring(canTransferToken)))

    local canTransferWater = Utils.CanTransferItem(source, 'water')
    print(string.format('[ox_limits:TEST] Can transfer water: %s', tostring(canTransferWater)))

    -- Test 7: Check hook call count
    local hookCalls = Limits.GetHookCallCount()
    print(string.format('[ox_limits:TEST] Total hook calls since startup: %d', hookCalls))

    Utils.NotifyPlayer(source, 'Test results printed to server console', 'success')
end, false)

-- Version check
CreateThread(function()
    local currentVersion = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)
    print(string.format('^2[ox_limits]^7 Version %s loaded', currentVersion))
end)

