Config = {}

-- qb-core job that owns the cash register (management_funds via qb-banking proxy).
-- Create this job's boss account the same way DOJ was created: /adminmenu, grade = boss grade below.
Config.Job = 'motel'

-- No refund on manual cancellation (County RP economy convention: no take-backs on a paid service).
Config.CancelRefund = false

-- Rent is paid automatically from whichever account covers it: cash first, then bank
-- (see server/main.lua rentRoom) -- no account choice needed from the player.

-- 2026-10-20: room doors are physical qb-doorlock doors (E to lock/unlock, same as police doors;
-- defined in qb-doorlock/configs/motel.lua, authorization via the CanUseRoom export below).
-- false = old fallback: client-side collision barrier + qb-target "Aç/Kilitle" options.
Config.UseDoorlock = true

-- How many other citizens a renter can grant room access to.
Config.MaxFriendsPerRoom = 3

-- Server-side loop: how often (seconds) expired rentals are swept.
Config.ExpiryCheckInterval = 120

Config.Notify = function(src, msg, type)
    TriggerClientEvent('QBCore:Notify', src, msg, type or 'primary')
end

-- Rental duration presets. 'hours' may be fractional (e.g. 0.5 = 30 min) for testing.
Config.Durations = {
    { label = '1 Saat',   hours = 1,  price = 75 },
    { label = '4 Saat',   hours = 4,  price = 250 },
    { label = '8 Saat',   hours = 8,  price = 450 },
    { label = '24 Saat',  hours = 24, price = 800 },
}

-- Shared "lost & found" stash: expired rentals dump their room's items here.
-- Only Config.Job members can open it (reception desk target option).
Config.LostFound = {
    id = 'motel_lostfound',
    label = 'Motel Kayıp Eşya Deposu',
    slots = 200,
    maxWeight = 200000,
}

-- Reception NPC — walk-up menu, no tablet/NUI. Fill coords with /motelnokta (see client/main.lua).
Config.NPC = {
    model = 'a_m_m_business_01',
    coords = vector4(324.48, -230.63, 53.22, 110.86), -- heading flipped 180° from /motelnokta capture so the NPC faces the approach, not the door
    label = 'Motel Resepsiyonu',
    interactDist = 2.5,
    viewDistance = 15.0,
}

-- Room list. Fill doorCoords with /motelkapi (look at the door, run the command) and
-- stashCoords/wardrobeCoords with /motelnokta (stand on the spot, run the command).
-- Each room needs: label, doorCoords (vector4 + model hash), stashCoords, wardrobeCoords.
-- 2026-10-17: doorCoords (via /motelkapi) and stashCoords/wardrobeCoords (via /motelnokta, inside
-- each room) captured for all 14 rooms. The stash/wardrobe pairs weren't labeled per room when sent,
-- so they were matched to each door by nearest distance -- every match landed at a consistent ~6.1m
-- depth from its door, which is a strong signal the matching is correct, but it was inferred, not
-- explicitly confirmed. Walk each room once and check the target labels say the right room number.
Config.Rooms = {
    [1]  = { label = 'Oda 1',  doorModel = -1156992775, doorCoords = vector4(339.81, -219.10, 54.37, 251.44), stashCoords = vector3(339.85, -224.13, 54.23), wardrobeCoords = vector3(344.11, -225.47, 54.23), stashSlots = 40, stashWeight = 40000 },
    [2]  = { label = 'Oda 2',  doorModel = -1156992775, doorCoords = vector4(343.60, -209.21, 54.37, 248.91), stashCoords = vector3(343.83, -214.11, 54.23), wardrobeCoords = vector3(348.01, -215.64, 54.23), stashSlots = 40, stashWeight = 40000 },
    [3]  = { label = 'Oda 3',  doorModel = -1156992775, doorCoords = vector4(347.39, -199.33, 54.37, 258.40), stashCoords = vector3(347.41, -204.38, 54.23), wardrobeCoords = vector3(351.73, -205.68, 54.23), stashSlots = 40, stashWeight = 40000 },
    [4]  = { label = 'Oda 4',  doorModel = -1156992775, doorCoords = vector4(347.39, -199.33, 58.17, 248.91), stashCoords = vector3(347.52, -204.44, 58.02), wardrobeCoords = vector3(351.72, -205.62, 58.02), stashSlots = 40, stashWeight = 40000 },
    [5]  = { label = 'Oda 5',  doorModel = -1156992775, doorCoords = vector4(343.60, -209.21, 58.17, 248.91), stashCoords = vector3(343.72, -214.30, 58.02), wardrobeCoords = vector3(348.00, -215.75, 58.02), stashSlots = 40, stashWeight = 40000 },
    [6]  = { label = 'Oda 6',  doorModel = -1156992775, doorCoords = vector4(339.81, -219.10, 58.17, 250.74), stashCoords = vector3(340.00, -224.21, 58.02), wardrobeCoords = vector3(344.16, -225.42, 58.02), stashSlots = 40, stashWeight = 40000 },
    [7]  = { label = 'Oda 7',  doorModel = -1156992775, doorCoords = vector4(335.34, -227.98, 58.17, 175.66), stashCoords = vector3(330.23, -228.11, 58.02), wardrobeCoords = vector3(328.94, -232.35, 58.02), stashSlots = 40, stashWeight = 40000 },
    [8]  = { label = 'Oda 8',  doorModel = -1156992775, doorCoords = vector4(315.25, -220.27, 58.17, 171.83), stashCoords = vector3(310.13, -220.43, 58.02), wardrobeCoords = vector3(308.96, -224.61, 58.02), stashSlots = 40, stashWeight = 40000 },
    [9]  = { label = 'Oda 9',  doorModel = -1156992775, doorCoords = vector4(306.85, -213.67, 58.17, 66.35),  stashCoords = vector3(306.79, -208.61, 58.02), wardrobeCoords = vector3(302.34, -207.30, 58.02), stashSlots = 40, stashWeight = 40000 },
    [10] = { label = 'Oda 10', doorModel = -1156992775, doorCoords = vector4(310.64, -203.79, 58.17, 95.33),  stashCoords = vector3(310.50, -198.69, 58.02), wardrobeCoords = vector3(306.31, -197.47, 58.02), stashSlots = 40, stashWeight = 40000 },
    [11] = { label = 'Oda 11', doorModel = -1156992775, doorCoords = vector4(315.39, -194.17, 58.17, 338.95), stashCoords = vector3(320.52, -194.12, 58.02), wardrobeCoords = vector3(321.82, -189.84, 58.02), stashSlots = 40, stashWeight = 40000 },
    [12] = { label = 'Oda 12', doorModel = -1156992775, doorCoords = vector4(315.39, -194.17, 54.37, 338.95), stashCoords = vector3(320.46, -194.15, 54.23), wardrobeCoords = vector3(321.69, -189.82, 54.23), stashSlots = 40, stashWeight = 40000 },
    [13] = { label = 'Oda 13', doorModel = -1156992775, doorCoords = vector4(310.64, -203.79, 54.37, 68.91),  stashCoords = vector3(310.41, -198.65, 54.23), wardrobeCoords = vector3(306.43, -197.44, 54.23), stashSlots = 40, stashWeight = 40000 },
    [14] = { label = 'Oda 14', doorModel = -1156992775, doorCoords = vector4(306.85, -213.67, 54.37, 84.42),  stashCoords = vector3(306.76, -208.53, 54.23), wardrobeCoords = vector3(302.48, -207.26, 54.23), stashSlots = 40, stashWeight = 40000 },
}
