Config = {}

-- qb-core job that owns the cash register (management_funds via qb-banking proxy).
-- Create this job's boss account the same way DOJ was created: /adminmenu, grade = boss grade below.
Config.Job = 'motel'

-- No refund on manual cancellation (County RP economy convention: no take-backs on a paid service).
Config.CancelRefund = false

-- Rent is paid in cash at the desk (receptionist transaction, not a bank transfer).
Config.PaymentAccount = 'cash' -- 'cash' or 'bank'

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
    coords = vector4(0.0, 0.0, 0.0, 0.0), -- PLACEHOLDER: capture with /motelnokta and paste here
    label = 'Motel Resepsiyonu',
    interactDist = 2.5,
    viewDistance = 15.0,
}

-- Room list. Fill doorCoords with /motelkapi (look at the door, run the command) and
-- stashCoords/wardrobeCoords with /motelnokta (stand on the spot, run the command).
-- Each room needs: label, doorCoords (vector4 + model hash), stashCoords, wardrobeCoords.
Config.Rooms = {
    -- [1] = {
    --     label = 'Oda 1',
    --     doorModel = 0,                         -- GetEntityModel hash from /motelkapi output
    --     doorCoords = vector4(0.0, 0.0, 0.0, 0.0),
    --     stashCoords = vector3(0.0, 0.0, 0.0),
    --     wardrobeCoords = vector3(0.0, 0.0, 0.0),
    --     stashSlots = 40,
    --     stashWeight = 40000,
    -- },
}
