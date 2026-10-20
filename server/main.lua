local QBCore = exports['qb-core']:GetCoreObject()

-- room_id -> { id = rental row id, citizenid, friends = {citizenid,...}, expiresAt = unix }
local ActiveRentals = {}

local function roomStashId(roomId)
    return 'motel_room_' .. roomId
end

local function findSourceForCid(citizenid)
    for _, pid in ipairs(GetPlayers()) do
        local P = QBCore.Functions.GetPlayer(tonumber(pid))
        if P and P.PlayerData.citizenid == citizenid then
            return tonumber(pid)
        end
    end
    return nil
end

local function loadActiveRentals()
    local rows = MySQL.query.await('SELECT * FROM motel_rentals WHERE active = 1', {})
    for _, row in ipairs(rows or {}) do
        local friends = {}
        if row.friends and row.friends ~= '' then
            friends = json.decode(row.friends) or {}
        end
        ActiveRentals[row.room_id] = {
            id = row.id,
            citizenid = row.citizenid,
            friends = friends,
            expiresAt = row.expires_at,
        }
    end
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `motel_rentals` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `room_id` INT NOT NULL,
            `citizenid` VARCHAR(64) NOT NULL,
            `rented_at` DATETIME NOT NULL,
            `expires_at` DATETIME NOT NULL,
            `friends` JSON NOT NULL DEFAULT ('[]'),
            `active` TINYINT(1) NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`),
            KEY `idx_room_active` (`room_id`, `active`),
            KEY `idx_citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    loadActiveRentals()
    local activeCount = 0
    for _ in pairs(ActiveRentals) do activeCount = activeCount + 1 end
    print(('^2[county-motel]^7 ready, %d active rental(s) loaded'):format(activeCount))
end)

--- Moves every item from the room's stash into the shared lost&found stash (job-gated, see client).
--- Slot-safe merge: lost&found items keep their slot, room items get reassigned to the first free slot.
local function dumpRoomStashToLostFound(roomId)
    local roomItems = exports['codem-inventory']:GetStashItems(roomStashId(roomId)) or {}
    if not next(roomItems) then return end

    local lfId = Config.LostFound.id
    local lfItems = exports['codem-inventory']:GetStashItems(lfId) or {}

    local usedSlots = {}
    for slot in pairs(lfItems) do
        usedSlots[tonumber(slot)] = true
    end

    local nextFree = 1
    for _, item in pairs(roomItems) do
        while usedSlots[nextFree] do
            nextFree = nextFree + 1
        end
        if nextFree > Config.LostFound.slots then
            print(('^1[county-motel]^7 lost&found full, item "%s" from room %s dropped'):format(tostring(item.name), tostring(roomId)))
            break
        end
        item.slot = nextFree
        lfItems[tostring(nextFree)] = item
        usedSlots[nextFree] = true
    end

    exports['codem-inventory']:UpdateStash(lfId, lfItems)
    exports['codem-inventory']:UpdateStash(roomStashId(roomId), {})
end

--- Forces the physical qb-doorlock door shut (rental ended / just started), whoever left it open.
local function relockDoor(roomId)
    if not Config.UseDoorlock then return end
    local ok = pcall(function() exports['qb-doorlock']:SetDoorLocked('motel-' .. roomId, true) end)
    if not ok then
        print(('^3[county-motel]^7 could not relock qb-doorlock door motel-%s (qb-doorlock not started?)'):format(tostring(roomId)))
    end
end

local function endRental(roomId, reason)
    local rental = ActiveRentals[roomId]
    if not rental then return end

    dumpRoomStashToLostFound(roomId)
    relockDoor(roomId)

    MySQL.update('UPDATE motel_rentals SET active = 0 WHERE id = ?', { rental.id })

    local src = findSourceForCid(rental.citizenid)
    if src then
        Config.Notify(src, ('Motel odanızın kirası sona erdi. Eşyalarınız resepsiyonun kayıp eşya deposuna alındı (%s).'):format(reason), 'error')
        TriggerClientEvent('motel:client:roomEnded', src, roomId)
    end

    ActiveRentals[roomId] = nil
end

CreateThread(function()
    while true do
        Wait(Config.ExpiryCheckInterval * 1000)
        for roomId, rental in pairs(ActiveRentals) do
            -- expires_at is a MySQL DATETIME string; compare via SQL to avoid timezone drift.
            local expired = MySQL.scalar.await('SELECT expires_at <= NOW() FROM motel_rentals WHERE id = ?', { rental.id })
            if expired and expired ~= 0 then
                endRental(roomId, 'süre doldu')
            end
        end
    end
end)

lib.callback.register('motel:cb:getRoomList', function(source)
    local list = {}
    for roomId, room in pairs(Config.Rooms) do
        table.insert(list, {
            id = roomId,
            label = room.label,
            occupied = ActiveRentals[roomId] ~= nil,
        })
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end)

lib.callback.register('motel:cb:getMyRoom', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil end
    for roomId, rental in pairs(ActiveRentals) do
        if rental.citizenid == Player.PlayerData.citizenid then
            return { roomId = roomId, friends = rental.friends, expiresAt = rental.expiresAt }
        end
    end
    return nil
end)

--- Called once on client resource start (and on spawn) to sync which rooms should show as
--- physically unlocked for this player -- otherwise a resource restart resets everyone's door
--- blocker to "locked" with no way to know their own active rental/friend access.
lib.callback.register('motel:cb:getMyUnlockedRooms', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end
    local cid = Player.PlayerData.citizenid
    local roomIds = {}
    for roomId, rental in pairs(ActiveRentals) do
        if rental.citizenid == cid then
            table.insert(roomIds, roomId)
        else
            for _, friendCid in ipairs(rental.friends) do
                if friendCid == cid then
                    table.insert(roomIds, roomId)
                    break
                end
            end
        end
    end
    return roomIds
end)

--- Server is the sole authority on room access; client only asks before animating the door/opening stash/wardrobe.
local function canUseRoom(source, roomId)
    roomId = tonumber(roomId)
    local Player = QBCore.Functions.GetPlayer(source)
    local rental = ActiveRentals[roomId]
    if not Player or not rental then return false end
    local cid = Player.PlayerData.citizenid
    if rental.citizenid == cid then return true end
    for _, friendCid in ipairs(rental.friends) do
        if friendCid == cid then return true end
    end
    return false
end

lib.callback.register('motel:cb:canUseRoom', canUseRoom)

-- qb-doorlock (configs/motel.lua, `motelRoom`) asks this on every E press on a room door.
exports('CanUseRoom', canUseRoom)

RegisterNetEvent('motel:server:rentRoom', function(roomId, durationIdx)
    local src = source
    roomId = tonumber(roomId)
    durationIdx = tonumber(durationIdx)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local room = Config.Rooms[roomId]
    local duration = Config.Durations[durationIdx]
    if not room or not duration then return end
    if ActiveRentals[roomId] then
        Config.Notify(src, 'Bu oda şu anda dolu.', 'error')
        return
    end

    local cid = Player.PlayerData.citizenid
    for existingRoomId, rental in pairs(ActiveRentals) do
        if rental.citizenid == cid then
            Config.Notify(src, 'Zaten kiralık bir odanız var.', 'error')
            return
        end
    end

    local price = duration.price
    -- Try cash first, fall back to bank -- player doesn't pick, whichever account covers it is used.
    local cash = Player.PlayerData.money.cash or 0
    local bank = Player.PlayerData.money.bank or 0
    local payAccount = nil
    if cash >= price then
        payAccount = 'cash'
    elseif bank >= price then
        payAccount = 'bank'
    else
        Config.Notify(src, 'Ne nakit ne de banka hesabınızda yeterli para var.', 'error')
        return
    end

    Player.Functions.RemoveMoney(payAccount, price, 'Motel oda kirası')
    exports['qb-banking']:AddMoney(Config.Job, price)

    local id = MySQL.insert.await(
        'INSERT INTO motel_rentals (room_id, citizenid, rented_at, expires_at, friends, active) VALUES (?, ?, NOW(), DATE_ADD(NOW(), INTERVAL ? HOUR), ?, 1)',
        { roomId, cid, duration.hours, json.encode({}) }
    )
    if not id then
        -- INSERT failed: refund immediately instead of letting the player believe they rented a
        -- room that only exists in memory until the next restart (this exact bug happened once).
        print(('^1[county-motel]^7 rentRoom INSERT failed for room %s, citizenid %s -- refunding'):format(tostring(roomId), cid))
        Player.Functions.AddMoney(payAccount, price, 'Motel oda kirası (başarısız kayıt - iade)')
        Config.Notify(src, 'Kiralama kaydedilemedi, paranız iade edildi. Tekrar deneyin.', 'error')
        return
    end

    local expiresAt = MySQL.scalar.await('SELECT expires_at FROM motel_rentals WHERE id = ?', { id })
    ActiveRentals[roomId] = { id = id, citizenid = cid, friends = {}, expiresAt = expiresAt }
    relockDoor(roomId)

    Config.Notify(src, ('%s kiralandı: %s. $%s ödendi.'):format(room.label, duration.label, price), 'success')
    TriggerClientEvent('motel:client:roomRented', src, roomId)
end)

RegisterNetEvent('motel:server:cancelRoom', function(roomId)
    local src = source
    roomId = tonumber(roomId)
    local Player = QBCore.Functions.GetPlayer(src)
    local rental = ActiveRentals[roomId]
    if not Player or not rental or rental.citizenid ~= Player.PlayerData.citizenid then return end

    -- Config.CancelRefund is always false right now (County RP economy decision, 2026-10-17) but kept
    -- as a config flag in case that decision changes later.
    if Config.CancelRefund then
        -- refund logic would go here
    end

    endRental(roomId, 'iptal edildi')
    Config.Notify(src, 'Oda kiranız iptal edildi.', 'primary')
end)

RegisterNetEvent('motel:server:addFriend', function(roomId, targetCid)
    local src = source
    roomId = tonumber(roomId)
    local Player = QBCore.Functions.GetPlayer(src)
    local rental = ActiveRentals[roomId]
    if not Player or not rental or rental.citizenid ~= Player.PlayerData.citizenid then return end
    if targetCid == rental.citizenid then return end

    if #rental.friends >= Config.MaxFriendsPerRoom then
        Config.Notify(src, ('En fazla %s kişiye erişim verebilirsiniz.'):format(Config.MaxFriendsPerRoom), 'error')
        return
    end
    for _, cid in ipairs(rental.friends) do
        if cid == targetCid then
            Config.Notify(src, 'Bu kişi zaten listede.', 'error')
            return
        end
    end

    local targetExists = MySQL.scalar.await('SELECT 1 FROM players WHERE citizenid = ?', { targetCid })
    if not targetExists then
        Config.Notify(src, 'Bu vatandaş no bulunamadı.', 'error')
        return
    end

    table.insert(rental.friends, targetCid)
    MySQL.update('UPDATE motel_rentals SET friends = ? WHERE id = ?', { json.encode(rental.friends), rental.id })
    Config.Notify(src, 'Erişim verildi.', 'success')

    local targetSrc = findSourceForCid(targetCid)
    if targetSrc then
        Config.Notify(targetSrc, 'Bir motel odasına erişim verildi.', 'primary')
    end
end)

RegisterNetEvent('motel:server:removeFriend', function(roomId, targetCid)
    local src = source
    roomId = tonumber(roomId)
    local Player = QBCore.Functions.GetPlayer(src)
    local rental = ActiveRentals[roomId]
    if not Player or not rental or rental.citizenid ~= Player.PlayerData.citizenid then return end

    for i, cid in ipairs(rental.friends) do
        if cid == targetCid then
            table.remove(rental.friends, i)
            MySQL.update('UPDATE motel_rentals SET friends = ? WHERE id = ?', { json.encode(rental.friends), rental.id })
            Config.Notify(src, 'Erişim kaldırıldı.', 'primary')
            return
        end
    end
end)

RegisterNetEvent('motel:server:openStash', function(roomId)
    local src = source
    roomId = tonumber(roomId)
    local Player = QBCore.Functions.GetPlayer(src)
    local room = Config.Rooms[roomId]
    if not Player or not room then return end

    local rental = ActiveRentals[roomId]
    if not rental then return end
    local cid = Player.PlayerData.citizenid
    local allowed = rental.citizenid == cid
    if not allowed then
        for _, friendCid in ipairs(rental.friends) do
            if friendCid == cid then allowed = true break end
        end
    end
    if not allowed then return end

    TriggerClientEvent('motel:client:doOpenStash', src, roomStashId(roomId), room.stashSlots, room.stashWeight, room.label .. ' Deposu')
end)

-- TEMP DEBUG (2026-10-17, remove once the room-lock bug is confirmed fixed): dumps ActiveRentals
-- as-is so we can see the real key types/values instead of guessing.
RegisterCommand('motelrentalsdebug', function(src)
    if src == 0 then return end -- console only guard not needed; command is player-run
    local lines = { '[county-motel] ActiveRentals dump:' }
    for roomId, rental in pairs(ActiveRentals) do
        table.insert(lines, ('  room %s (type %s) -> citizenid=%s id=%s expiresAt=%s'):format(
            tostring(roomId), type(roomId), tostring(rental.citizenid), tostring(rental.id), tostring(rental.expiresAt)
        ))
    end
    if #lines == 1 then table.insert(lines, '  (empty)') end
    print(table.concat(lines, '\n'))
    Config.Notify(src, 'Konsola yazıldı (F8).', 'primary')
end, false)

--- Reception desk, job-gated: motel employees/boss open the shared lost&found stash.
RegisterNetEvent('motel:server:openLostFound', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.Job then return end
    TriggerClientEvent('motel:client:doOpenStash', src, Config.LostFound.id, Config.LostFound.slots, Config.LostFound.maxWeight, Config.LostFound.label)
end)
