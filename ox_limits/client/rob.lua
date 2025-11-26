local IsEntityPlayingAnim = IsEntityPlayingAnim
local GetPlayerServerId = GetPlayerServerId
local NetworkGetPlayerIndexFromPed = NetworkGetPlayerIndexFromPed
local IsPedDeadOrDying = IsPedDeadOrDying
local IsPedArmed = IsPedArmed

local function DebugLog(message)
    if Config.Debug then
        print('[ox_limits:DEBUG] ' .. message)
    end
end

lib.onCache('ped', function(value)
    SetPedConfigFlag(value, 438, true)
end)

local stealableAnimations = {
    { "missminuteman_1ig_2",   "handsup_base" },
    { "random@mugging3",       "handsup_standing_base" },
    { "random@arrests@busted", "idle_a" }
}

local function playerHasWeapon()
    return IsPedArmed(cache.ped, 4) or IsPedArmed(cache.ped, 1)
end


local function canRobPlayer(entity)
    if not entity or not DoesEntityExist(entity) then return false end
    if entity == cache.ped then return false end
    if not IsPedAPlayer(entity) then return false end

    if IsPedDeadOrDying(entity, 1) then
		return true
    end

    if not playerHasWeapon() then
		return false
    end

	return true
end

exports.ox_target:addGlobalPlayer({
    {
        name = 'rob_player',
        icon = 'fas fa-mask',
        label = 'Rob Player',
        distance = 2.8,
        canInteract = canRobPlayer,
        onSelect = function(data)
            local entity = data.entity
            local playerIdx = NetworkGetPlayerIndexFromPed(entity)

            if not playerIdx then return end

            local playerId = GetPlayerServerId(playerIdx)
            local isDead = IsPedDeadOrDying(entity, 1)

            DebugLog(string.format("Attempting to rob player ID=%d, dead=%s", playerId, tostring(isDead)))

            TriggerServerEvent('ox_limits:server:rob_player', {
                playerId = playerId,
                dead = isDead
            })
        end
    }
})

lib.callback.register('ox_limits:client:validate_handsup', function()
    local isHandsUp = false
    for _, anim in ipairs(stealableAnimations) do
        if IsEntityPlayingAnim(cache.ped, anim[1], anim[2], 3) then
            isHandsUp = true
            break
        end
    end

    DebugLog("Hands up validation: " .. tostring(isHandsUp))
    return isHandsUp
end)

lib.callback.register('ox_limits:client:validate_armed', function()
    local hasWeapon = playerHasWeapon()
    DebugLog("Weapon validation: " .. tostring(hasWeapon))
    return hasWeapon
end)

lib.callback.register('ox_limits:client:checkIsArmed', function()
    return IsPedArmed(cache.ped, 4) or IsPedArmed(cache.ped, 1) or
        HasPedGotWeapon(cache.ped, GetHashKey('WEAPON_UNARMED'), false)
end)

local lastAttackers = {}
local damageTimeout = 60000

AddEventHandler('gameEventTriggered', function(eventName, args)
    if eventName ~= 'CEventNetworkEntityDamage' then return end

    if not args or #args < 4 then return end

    local victim = args[1]
    local attacker = args[2]
    local isDead = args[6] == 1

    if attacker == cache.ped and victim ~= cache.ped and IsPedAPlayer(victim) then
        local victimId = NetworkGetPlayerIndexFromPed(victim)
        if victimId then
            local serverId = GetPlayerServerId(victimId)
            local attackerCoords = GetEntityCoords(cache.ped)
            local victimCoords = GetEntityCoords(victim)
            local distance = #(victimCoords - attackerCoords)

            DebugLog(string.format("Damage event: attacking player ID=%d from distance %.2f", serverId, distance))

            TriggerServerEvent('ox_limits:server:registerAttacker', serverId, distance)

            if isDead then
                DebugLog(string.format("Death event: player killed ID=%d from distance %.2f", serverId, distance))
                TriggerServerEvent('ox_limits:server:registerKillerVictim', serverId, distance)
            end
        end
    end

    if victim == cache.ped and attacker ~= 0 and attacker ~= cache.ped and IsPedAPlayer(attacker) then
        local attackerId = NetworkGetPlayerIndexFromPed(attacker)
        if attackerId then
            local serverId = GetPlayerServerId(attackerId)
            lastAttackers[serverId] = GetGameTimer()
            DebugLog(string.format("Received damage from player ID=%d", serverId))
        end
    end

    if victim == cache.ped and isDead then
        local recentAttackers = {}
        local currentTime = GetGameTimer()

        for attackerId, timestamp in pairs(lastAttackers) do
            if (currentTime - timestamp) < damageTimeout then
                table.insert(recentAttackers, attackerId)
            end
        end

        if #recentAttackers > 0 then
            TriggerServerEvent('ox_limits:server:reportRecentAttackers', recentAttackers)
        end

        lastAttackers = {}
    end
end)

-- CreateThread(function()
--     while true do
--         Wait(500)

--         if IsEntityDead(cache.ped) then
--             local entityKiller = GetPedSourceOfDeath(cache.ped)

--             if entityKiller ~= 0 and entityKiller ~= cache.ped and IsPedAPlayer(entityKiller) then
--                 local killerId = NetworkGetPlayerIndexFromPed(entityKiller)
--                 if killerId then
--                     local serverKillerId = GetPlayerServerId(killerId)
--                     TriggerServerEvent('ox_limits:server:reportKiller', serverKillerId)
--                 end
--             end
--         end
--     end
-- end)

-- CreateThread(function()
--     local function checkPlayerIsDead()
--         return IsPedDeadOrDying(cache.ped, 1)
--     end

--     local wasDead = false

--     while true do
--         Wait(1000)

--         local isDead = checkPlayerIsDead()

--         if isDead and not wasDead then
--             local playerCoords = GetEntityCoords(cache.ped)
--             local nearbyPlayers = {}

--             for i = 0, 255 do
--                 if NetworkIsPlayerActive(i) and i ~= PlayerId() then
--                     local ped = GetPlayerPed(i)
--                     if DoesEntityExist(ped) then
--                         local otherCoords = GetEntityCoords(ped)
--                         local distance = #(playerCoords - otherCoords)

--                         if distance < 200.0 then
--                             local serverId = GetPlayerServerId(i)
--                             table.insert(nearbyPlayers, { id = serverId, distance = distance })
--                         end
--                     end
--                 end
--             end

--             table.sort(nearbyPlayers, function(a, b) return a.distance < b.distance end)

--             if #nearbyPlayers > 0 then
--                 TriggerServerEvent('ox_limits:server:reportNearbyPlayers', nearbyPlayers)
--             end
--         end

--         wasDead = isDead
--     end
-- end)
