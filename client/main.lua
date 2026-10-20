local QBCore = exports['qb-core']:GetCoreObject()
local npc = nil -- declared early: referenced by /motelnpc below and the NPC spawn logic further down

-- ===========================================================================
-- Coordinate-capture admin commands (same pattern as mcLaw's /mclawpoaground):
-- stand where needed, run the command, paste the printed snippet into shared/config.lua.
-- ===========================================================================

--- /motelnokta: generic point capture (NPC, stash, wardrobe coords).
-- Uses the player's own standing Z directly (no raycast) -- a downward raycast from above can hit
-- an overhang/railing/upper floor instead of the real ground, which is what happened at the motel
-- desk spot (2026-10-17). The player is, by definition, already standing on valid ground.
RegisterCommand('motelnokta', function()
    local coords = GetEntityCoords(PlayerPedId())
    local heading = GetEntityHeading(PlayerPedId())
    print(('[county-motel] vector3(%.2f, %.2f, %.2f)  |  vector4(%.2f, %.2f, %.2f, %.2f)'):format(
        coords.x, coords.y, coords.z, coords.x, coords.y, coords.z, heading
    ))
    QBCore.Functions.Notify('Koordinat konsola yazıldı (F8).', 'primary')
end, false)

--- /motelnpc: diagnostic. Prints distance to the configured NPC spot and whether the ped has spawned.
RegisterCommand('motelnpc', function()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local c = Config.NPC.coords
    local dist = #(playerCoords - vector3(c.x, c.y, c.z))
    local exists = npc ~= nil and DoesEntityExist(npc)
    print(('[county-motel] dist to NPC spot: %.1f (viewDistance=%.1f)  |  model "%s" loaded: %s  |  npc spawned: %s'):format(
        dist, Config.NPC.viewDistance, Config.NPC.model, tostring(HasModelLoaded(GetHashKey(Config.NPC.model))),
        tostring(exists)
    ))
    if exists then
        local npcCoords = GetEntityCoords(npc)
        print(('[county-motel] npc actual coords: %.2f, %.2f, %.2f  |  player z: %.2f  |  z diff (player-npc): %.2f  |  npc visible: %s  |  npc alive: %s'):format(
            npcCoords.x, npcCoords.y, npcCoords.z, playerCoords.z, playerCoords.z - npcCoords.z,
            tostring(IsEntityVisible(npc)), tostring(not IsEntityDead(npc))
        ))
    end
    QBCore.Functions.Notify(('Mesafe: %.1f'):format(dist), 'primary')
end, false)

--- /motelkapi: look at the door entity, run the command -> prints door model hash + coords + heading.
RegisterCommand('motelkapi', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local direction = RotationToDirection(camRot)
    local destination = camCoords + direction * 5.0

    local rayHandle = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, destination.x, destination.y, destination.z, 16, ped, 0)
    local _, hit, _, _, entityHit = GetShapeTestResult(rayHandle)

    if hit == 0 or entityHit == 0 then
        QBCore.Functions.Notify('Bir kapıya bakarken komutu çalıştır.', 'error')
        return
    end

    local doorCoords = GetEntityCoords(entityHit)
    local heading = GetEntityHeading(entityHit)
    local model = GetEntityModel(entityHit)
    print(('[county-motel] doorModel = %d  |  vector4(%.2f, %.2f, %.2f, %.2f)'):format(model, doorCoords.x, doorCoords.y, doorCoords.z, heading))
    QBCore.Functions.Notify('Kapı bilgisi konsola yazıldı (F8).', 'primary')
end, false)

function RotationToDirection(rotation)
    local z = math.rad(rotation.z)
    local x = math.rad(rotation.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

-- ===========================================================================
-- Reception NPC
-- ===========================================================================

local function spawnNpc()
    if npc and DoesEntityExist(npc) then return end
    local model = GetHashKey(Config.NPC.model)
    RequestModel(model)
    local attempts = 0
    while not HasModelLoaded(model) and attempts < 100 do
        Wait(10)
        attempts = attempts + 1
    end
    if not HasModelLoaded(model) then
        print(('^1[county-motel]^7 NPC model "%s" failed to load'):format(Config.NPC.model))
        return
    end

    local c = Config.NPC.coords
    -- c.z is already real ground height (/motelnokta raycasts it) -> no extra offset needed here.
    npc = CreatePed(4, model, c.x, c.y, c.z, c.w, false, false)
    SetEntityInvincible(npc, true)
    FreezeEntityPosition(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetModelAsNoLongerNeeded(model)

    exports['qb-target']:AddTargetEntity(npc, {
        options = {
            { type = 'client', event = 'motel:client:openMainMenu', icon = 'fas fa-bed', label = Config.NPC.label },
            {
                type = 'client',
                event = 'motel:client:openLostFound',
                icon = 'fas fa-box-archive',
                label = 'Kayıp Eşya Deposu',
                canInteract = function()
                    local pd = QBCore.Functions.GetPlayerData()
                    return pd and pd.job and pd.job.name == Config.Job
                end,
            },
        },
        distance = Config.NPC.interactDist,
    })
end

local function removeNpc()
    if npc and DoesEntityExist(npc) then
        exports['qb-target']:RemoveTargetEntity(npc)
        DeleteEntity(npc)
    end
    npc = nil
end

CreateThread(function()
    while true do
        local playerCoords = GetEntityCoords(PlayerPedId())
        local dist = #(playerCoords - vector3(Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z))
        if dist < Config.NPC.viewDistance then
            spawnNpc()
        else
            removeNpc()
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then removeNpc() end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'tgiann-target' then removeNpc() end
end)

-- ===========================================================================
-- Menus
-- ===========================================================================

local function openDurationMenu(roomId)
    local options = {}
    for i, d in ipairs(Config.Durations) do
        table.insert(options, {
            header = d.label,
            txt = ('Ücret: $%s'):format(d.price),
            params = {
                event = 'motel:client:confirmRent',
                args = { roomId = roomId, durationIdx = i },
            },
        })
    end
    table.insert(options, { header = 'Geri', params = { event = 'motel:client:openMainMenu' } })
    exports['qb-menu']:openMenu(options)
end

RegisterNetEvent('motel:client:confirmRent', function(data)
    local duration = Config.Durations[data.durationIdx]
    exports['qb-menu']:openMenu({
        {
            header = 'Kiralamayı Onayla',
            txt = ('%s - $%s'):format(duration.label, duration.price),
            isMenuHeader = true,
        },
        {
            header = 'Onayla',
            params = {
                event = 'motel:client:doRent',
                isServer = false,
                args = data,
            },
        },
        { header = 'Vazgeç', params = { event = 'motel:client:openMainMenu' } },
    })
end)

RegisterNetEvent('motel:client:doRent', function(data)
    TriggerServerEvent('motel:server:rentRoom', data.roomId, data.durationIdx)
end)

local function openRoomPickMenu()
    local rooms = lib.callback.await('motel:cb:getRoomList', false)
    local options = {}
    for _, room in ipairs(rooms) do
        table.insert(options, {
            header = room.label,
            txt = room.occupied and 'Dolu' or 'Boş',
            disabled = room.occupied,
            params = {
                event = 'motel:client:pickDuration',
                args = { roomId = room.id },
            },
        })
    end
    table.insert(options, { header = 'Geri', params = { event = 'motel:client:openMainMenu' } })
    exports['qb-menu']:openMenu(options)
end

RegisterNetEvent('motel:client:pickDuration', function(data)
    openDurationMenu(data.roomId)
end)

local function openMyRoomMenu()
    local myRoom = lib.callback.await('motel:cb:getMyRoom', false)
    if not myRoom then
        QBCore.Functions.Notify('Kiralık bir odanız yok.', 'error')
        return
    end

    exports['qb-menu']:openMenu({
        { header = Config.Rooms[myRoom.roomId].label, txt = ('Bitiş: %s'):format(myRoom.expiresAt), isMenuHeader = true },
        {
            header = 'Erişim Ver',
            txt = ('%d/%d kişi'):format(#myRoom.friends, Config.MaxFriendsPerRoom),
            params = { event = 'motel:client:promptAddFriend', args = { roomId = myRoom.roomId } },
        },
        {
            header = 'Erişimi Kaldır',
            params = { event = 'motel:client:promptRemoveFriend', args = { roomId = myRoom.roomId, friends = myRoom.friends } },
        },
        {
            header = 'Kirayı İptal Et',
            params = { event = 'motel:client:promptCancel', args = { roomId = myRoom.roomId } },
        },
        { header = 'Geri', params = { event = 'motel:client:openMainMenu' } },
    })
end

RegisterNetEvent('motel:client:promptAddFriend', function(data)
    local input = exports['qb-input']:ShowInput({
        header = 'Erişim Ver',
        submitText = 'Onayla',
        inputs = { { text = 'Vatandaş No', name = 'cid', type = 'text', isRequired = true } },
    })
    if not input or not input.cid then return end
    TriggerServerEvent('motel:server:addFriend', data.roomId, input.cid)
end)

RegisterNetEvent('motel:client:promptRemoveFriend', function(data)
    if not data.friends or #data.friends == 0 then
        QBCore.Functions.Notify('Erişim listesi boş.', 'error')
        return
    end
    local options = {}
    for _, cid in ipairs(data.friends) do
        table.insert(options, {
            header = cid,
            params = { event = 'motel:client:doRemoveFriend', isServer = false, args = { roomId = data.roomId, cid = cid } },
        })
    end
    table.insert(options, { header = 'Geri', params = { event = 'motel:client:openMyRoomMenu' } })
    exports['qb-menu']:openMenu(options)
end)

RegisterNetEvent('motel:client:doRemoveFriend', function(data)
    TriggerServerEvent('motel:server:removeFriend', data.roomId, data.cid)
end)

RegisterNetEvent('motel:client:promptCancel', function(data)
    exports['qb-menu']:openMenu({
        { header = 'Kirayı iptal etmek istediğinize eminsiniz?', txt = 'Ücret iadesi yapılmaz.', isMenuHeader = true },
        { header = 'Evet, iptal et', params = { event = 'motel:client:doCancel', isServer = false, args = data } },
        { header = 'Vazgeç', params = { event = 'motel:client:openMyRoomMenu' } },
    })
end)

RegisterNetEvent('motel:client:doCancel', function(data)
    TriggerServerEvent('motel:server:cancelRoom', data.roomId)
end)

RegisterNetEvent('motel:client:openMyRoomMenu', openMyRoomMenu)

RegisterNetEvent('motel:client:openMainMenu', function()
    exports['qb-menu']:openMenu({
        { header = Config.NPC.label, isMenuHeader = true },
        { header = 'Oda Kirala', params = { event = 'motel:client:openRoomPick' } },
        { header = 'Odam', params = { event = 'motel:client:openMyRoomMenu' } },
        { header = 'Kapat', params = { event = 'qb-menu:client:closeMenu' } },
    })
end)

RegisterNetEvent('motel:client:openRoomPick', openRoomPickMenu)

-- ===========================================================================
-- Rooms: door lock, stash, wardrobe
-- ===========================================================================

-- 2026-10-17: confirmed in-game that SetEntityCoords-based correction is what caused the vertical
-- hop (with enforcement fully disabled, walking through was completely clean -- so it's our
-- position-override fighting the ped's own animation/ground state, not the map). Back to a real
-- collision object instead of faking it with coordinates. Made visible (DEBUG_VISIBLE) for now so
-- we can actually see whether it blocks on contact, not guess from "could I walk through or not".
local DEBUG_VISIBLE_BARRIERS = true -- 2026-10-17 TEMP: set false once confirmed working

local roomLocked = {} -- roomId -> bool, defaults to true (locked)
local lockBarriers = {} -- roomId -> object handle, only present while locked
for roomId in pairs(Config.Rooms) do
    roomLocked[roomId] = true
end

local function destroyBarrier(roomId)
    if lockBarriers[roomId] and DoesEntityExist(lockBarriers[roomId]) then
        DeleteEntity(lockBarriers[roomId])
    end
    lockBarriers[roomId] = nil
end

local function spawnBarrier(roomId)
    if lockBarriers[roomId] and DoesEntityExist(lockBarriers[roomId]) then return end
    local room = Config.Rooms[roomId]
    if not room then return end
    local c = room.doorCoords
    local model = room.doorModel
    RequestModel(model)
    local attempts = 0
    while not HasModelLoaded(model) and attempts < 100 do
        Wait(10)
        attempts = attempts + 1
    end
    if not HasModelLoaded(model) then
        print(('^1[county-motel]^7 barrier model failed to load for room %s'):format(tostring(roomId)))
        return
    end

    local barrier = CreateObject(model, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(barrier, c.w)
    SetEntityVisible(barrier, DEBUG_VISIBLE_BARRIERS, false)
    FreezeEntityPosition(barrier, true)
    SetEntityCollision(barrier, true, true)
    Wait(50) -- give the physics/collision a moment to register before we trust it
    ActivatePhysics(barrier)
    SetModelAsNoLongerNeeded(model)
    lockBarriers[roomId] = barrier
    print(('[county-motel] barrier spawned for room %s: exists=%s collidable=%s'):format(
        tostring(roomId), tostring(DoesEntityExist(barrier)), tostring(GetEntityCollisionDisabled and not GetEntityCollisionDisabled(barrier) or 'n/a')
    ))
end

local function setRoomLocked(roomId, locked)
    roomLocked[roomId] = locked
    if Config.UseDoorlock then return end -- qb-doorlock owns the physical door
    if locked then
        spawnBarrier(roomId)
    else
        destroyBarrier(roomId)
    end
end

-- Sync with the server once on start: a resource restart resets every client's roomLocked table
-- to "all locked", with no memory of who actually has an active rental/friend access.
CreateThread(function()
    Wait(2000) -- let qb-core/ox_lib finish initializing
    local unlockedRoomIds = lib.callback.await('motel:cb:getMyUnlockedRooms', false)
    for _, roomId in ipairs(unlockedRoomIds or {}) do
        setRoomLocked(roomId, false)
    end
end)

local function registerRoomDoors()
    for roomId, room in pairs(Config.Rooms) do
        local c = room.doorCoords
        setRoomLocked(roomId, true)

        if not Config.UseDoorlock then
            exports['qb-target']:AddBoxZone('motel_door_' .. roomId, vector3(c.x, c.y, c.z), 1.0, 1.0, {
                name = 'motel_door_' .. roomId,
                heading = c.w,
                minZ = c.z - 1.0,
                maxZ = c.z + 1.0,
            }, {
                options = {
                    { type = 'client', event = 'motel:client:tryEnterRoom', icon = 'fas fa-door-open', label = room.label .. ' - Aç', roomId = roomId },
                    { type = 'client', event = 'motel:client:tryLockRoom', icon = 'fas fa-lock', label = room.label .. ' - Kilitle', roomId = roomId },
                },
                distance = 2.0,
            })
        end

        -- Skip stash/wardrobe zones while their coords are still the door-coords placeholder
        -- (shared/config.lua) -- otherwise they stack on top of the door target, which is confusing.
        local hasStash = room.stashCoords.x ~= c.x or room.stashCoords.y ~= c.y or room.stashCoords.z ~= c.z
        local hasWardrobe = room.wardrobeCoords.x ~= c.x or room.wardrobeCoords.y ~= c.y or room.wardrobeCoords.z ~= c.z

        if hasStash then
            exports['qb-target']:AddBoxZone('motel_stash_' .. roomId, room.stashCoords, 1.0, 1.0, {
                name = 'motel_stash_' .. roomId,
                minZ = room.stashCoords.z - 1.0,
                maxZ = room.stashCoords.z + 1.0,
            }, {
                options = {
                    { type = 'client', event = 'motel:client:tryOpenStash', icon = 'fas fa-box', label = room.label .. ' - Depo', roomId = roomId },
                },
                distance = 2.0,
            })
        end

        if hasWardrobe then
            exports['qb-target']:AddBoxZone('motel_wardrobe_' .. roomId, room.wardrobeCoords, 1.0, 1.0, {
                name = 'motel_wardrobe_' .. roomId,
                minZ = room.wardrobeCoords.z - 1.0,
                maxZ = room.wardrobeCoords.z + 1.0,
            }, {
                options = {
                    { type = 'client', event = 'motel:client:tryOpenWardrobe', icon = 'fas fa-shirt', label = room.label .. ' - Kıyafet Değiştir', roomId = roomId },
                },
                distance = 2.0,
            })
        end
    end
end

CreateThread(function()
    Wait(1000) -- let tgiann-target finish starting
    registerRoomDoors()
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'tgiann-target' then
        Wait(500)
        registerRoomDoors()
    end
end)

-- 2026-10-17: removed the always-on 3D text loop (caused stutter). Room names are shown through
-- the qb-target option labels only (room.label .. ' - ...' set on each AddBoxZone above).

RegisterNetEvent('motel:client:tryEnterRoom', function(data)
    local roomId = tonumber(data.roomId)
    local allowed = lib.callback.await('motel:cb:canUseRoom', false, roomId)
    if not allowed then
        QBCore.Functions.Notify('Bu oda kilitli. Önce kiralamanız gerekiyor.', 'error')
        return
    end
    setRoomLocked(roomId, false)
    QBCore.Functions.Notify('Oda açıldı.', 'primary')
end)

RegisterNetEvent('motel:client:tryLockRoom', function(data)
    local roomId = tonumber(data.roomId)
    local allowed = lib.callback.await('motel:cb:canUseRoom', false, roomId)
    if not allowed then return end
    setRoomLocked(roomId, true)
    QBCore.Functions.Notify('Oda kilitlendi.', 'primary')
end)

RegisterNetEvent('motel:client:tryOpenStash', function(data)
    TriggerServerEvent('motel:server:openStash', data.roomId)
end)

RegisterNetEvent('motel:client:doOpenStash', function(stashId, slots, maxWeight, label)
    TriggerServerEvent('codem-inventory:server:openstash', stashId, slots, maxWeight, label)
end)

RegisterNetEvent('motel:client:tryOpenWardrobe', function(data)
    local allowed = lib.callback.await('motel:cb:canUseRoom', false, data.roomId)
    if not allowed then
        QBCore.Functions.Notify('Bu oda kilitli. Önce kiralamanız gerekiyor.', 'error')
        return
    end
    TriggerEvent('illenium-appearance:client:openClothingOnly')
end)

RegisterNetEvent('motel:client:roomRented', function(roomId)
    setRoomLocked(roomId, false)
end)

RegisterNetEvent('motel:client:roomEnded', function(roomId)
    setRoomLocked(roomId, true)
end)

-- Reception desk: motel employees/boss open the shared lost&found stash (separate target option on the NPC).
RegisterNetEvent('motel:client:openLostFound', function()
    TriggerServerEvent('motel:server:openLostFound')
end)
