Config = {
    transactionCallers = { kora_housing = true },
    ui = { accent = nil },
    -- Props treated as ATMs by the targeting eye. Default covers every standard GTA ATM (prop_atm_01/02/03, prop_fleeca_atm)
    -- plus bank lobby wall ATMs and the Gabz frame; add a model name here for a custom map's ATM prop.
    atmModels = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm', 'gabz_sm_pb_atmframe',
        -- Wall ATMs inside bank lobbies (Pacific Standard / big bank).
        'v_5_b_atm1', 'v_5_b_atm2' },
    -- Fallback for ATMs baked into the map (not entities, so model targeting never hits them): each entry is a vector3 at the
    -- machine and gets a "Use ATM" sphere zone of atmZoneRadius. Leave empty when every ATM resolves through atmModels.
    atmCoords = {},
    atmZoneRadius = 1.2,
    atmDistance = 1.8,
    -- Extra metres on top of atmDistance between the player and the ATM (client lookup and server check).
    -- Wall ATMs in bank lobbies are wide, so the prop centre can sit further away than the interaction distance.
    atmTolerance = 1.0,
    atmAccessTime = 1500,
    -- true: an ATM needs a bank card in the inventory and the card PIN. The server checks the card before the animation and progress bar start.
    -- false: no card is needed and the ATM opens without a PIN.
    requireBankCard = true,
    dateFormat = 'locale',
    showTime = true,
    dateTimezone = 'player', -- 'player' = each player time zone, 'server' = server time (UTC) for everyone
    useDailyLimit = true,
    dailyLimit = 5000,
    minAmount = { withdraw = 1, deposit = 1, transfer = 1 },
    -- Player-to-player transfers (bank counter, "Another player" tab). The recipient field accepts a character account
    -- number (citizen ID), a shared / society / gang account name, or a bank card number.
    Transfers = {
        allowOffline = true,        -- credit characters who are offline (written straight to the database); false = recipient must be online
        allowSharedAccounts = true, -- allow sending to shared, society (job) and gang accounts by account name
        allowCardNumbers = true,    -- allow a bank card number in place of the account number
    },
    migrationRetrySeconds = 0,
    maxAccounts = 2,
    maxSharedMembers = 10,
    maxSharedMemberBytes = 512,
    memberRateLimit = { max = 5, window = 10000 },
    blipInfo = {
        category = 'Bank',
        sprite = 108,
        color = 2,
        scale = 0.55,
        shortRange = true,
    },
    -- Each location is either plain coordinates (legacy; uses Config.tiers.default when tiers are enabled) or
    -- { coords = vector3/vector4, tier = 'fleeca' | 'bigbank' | <your tier>, label = 'Shown in the app header and on the map' }.
    locations = {
        { coords = vector3(149.05, -1041.3, 29.37), tier = 'fleeca', label = 'Fleeca Bank - Legion Square' },
        { coords = vector3(313.32, -280.03, 54.17), tier = 'fleeca', label = 'Fleeca Bank - Alta' },
        { coords = vector3(-351.94, -50.72, 49.04), tier = 'fleeca', label = 'Fleeca Bank - Burton' },
        { coords = vector3(-1212.68, -331.83, 37.78), tier = 'fleeca', label = 'Fleeca Bank - Rockford Plaza' },
        { coords = vector3(-2961.67, 482.31, 15.7), tier = 'fleeca', label = 'Fleeca Bank - Great Ocean Highway' },
        { coords = vector3(1175.64, 2707.71, 38.09), tier = 'fleeca', label = 'Fleeca Bank - Harmony' },
        { coords = vector3(247.65, 223.87, 106.29), tier = 'bigbank', label = 'Pacific Standard' },
        -- Blaine County Savings is a small regional branch, so it ships as a Fleeca-tier location with its own name.
        { coords = vector3(-111.98, 6470.56, 31.63), tier = 'fleeca', label = 'Blaine County Savings' },
    },
    -- Bank tiers (off by default: with enabled = false every branch behaves exactly as before).
    -- When enabled, the server resolves the tier from the branch the player is standing at (never from the client).
    -- features: set a feature to false to block it at that tier (unset = allowed). Gated features: deposit, withdraw,
    -- transfer, sharedAccounts (open/rename/close shared accounts), manageMembers (grant/revoke access), orderCard.
    -- limits (0 = no limit): dailyWithdraw = per-day counter withdrawal cap, maxTransfer = largest single transfer.
    -- blip: optional per-tier map marker overrides (sprite, color, scale); the location label names the marker.
    tiers = {
        enabled = false,
        default = 'fleeca',
        list = {
            fleeca = {
                label = 'Fleeca Bank',
                features = { deposit = true, withdraw = true, transfer = true, sharedAccounts = false, manageMembers = false, orderCard = true },
                limits = { dailyWithdraw = 5000, maxTransfer = 10000 },
                blip = { sprite = 108, color = 2 },
            },
            bigbank = {
                label = 'Pacific Standard',
                features = { deposit = true, withdraw = true, transfer = true, sharedAccounts = true, manageMembers = true, orderCard = true },
                limits = { dailyWithdraw = 50000, maxTransfer = 250000 },
                blip = { sprite = 106, color = 5 },
            },
        },
    },
}

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if Kora and Kora.config and Kora.config.adopt then
    local config = Kora.config
    Config.atmModels = config.list(Config.atmModels, nil, {
        label = 'ATM models', advanced = true,
        description = 'Model names treated as cash machines by targeting and nearby ATM lookup. Restart qbbanking to apply saved changes.',
    })
    Config.atmCoords = config.list(Config.atmCoords, nil, {
        label = 'ATM fallback coordinates', advanced = true,
        description = 'World coordinates (X/Y/Z) of ATMs baked into the map that model targeting cannot hit. Each entry gets a Use ATM target zone. Restart kora_banking to apply saved changes.',
    })
    Config.atmZoneRadius = config.number(Config.atmZoneRadius, {
        min = 0.3, max = 5.0, step = 0.1,
        label = 'ATM fallback zone radius (metres)', advanced = true,
        description = 'Size of the target zone created at each ATM fallback coordinate. Restart kora_banking to apply saved changes.',
    })
    Config.atmDistance = config.number(Config.atmDistance, {
        min = 0,
        label = 'ATM interaction distance (metres)', advanced = false,
        description = 'Maximum client distance for finding or targeting an ATM; the server allows an extra 1 metre of tolerance. Restart qbbanking to apply saved changes.',
    })
    Config.atmTolerance = config.number(Config.atmTolerance, {
        min = 0,
        label = 'ATM distance tolerance (metres)', advanced = true,
        description = 'Extra distance added to the ATM interaction distance when the client looks up the ATM and when the server verifies the player is beside it. Raise it if wall ATMs report Move closer while you stand in front of them. Restart kora_banking to apply saved changes.',
    })
    Config.atmAccessTime = config.integer(Config.atmAccessTime, {
        min = 0,
        label = 'ATM access time (milliseconds)', advanced = false,
        description = 'Duration of the cancellable progress bar before opening an ATM. 1000 milliseconds equals 1 second. Restart qbbanking to apply saved changes.',
    })
    Config.requireBankCard = config.boolean(Config.requireBankCard, {
        label = 'Require a bank card at ATMs', advanced = false,
        description = 'When on, players need a bank card in their inventory and its PIN to use an ATM; without a card only the error notification shows (no animation or progress bar). When off, ATMs open without a card or PIN. Applies immediately.',
    })
    Config.dateFormat = config.enum(Config.dateFormat, {
        options = {
            { value = 'locale', label = 'Player locale' }, { value = 'DD/MM/YYYY', label = 'DD/MM/YYYY' },
            { value = 'MM/DD/YYYY', label = 'MM/DD/YYYY' }, { value = 'YYYY-MM-DD', label = 'YYYY-MM-DD' },
        },
        label = 'Transaction date format', advanced = false,
        description = 'How dates appear in the Activity table. locale follows the player locale (en-US shows MM/DD/YYYY, most others DD/MM/YYYY); the other values force that order for everyone. Applies the next time Activity is opened.',
    })
    Config.showTime = config.boolean(Config.showTime, {
        label = 'Show time with transaction dates', advanced = false,
        description = 'Appends the hour and minute to each transaction date in Activity. Turn off to show the date only. Applies the next time Activity is opened.',
    })
    if Config.dateTimezone == 'local' then Config.dateTimezone = 'player' elseif Config.dateTimezone == 'utc' then Config.dateTimezone = 'server' end
    Config.dateTimezone = config.enum(Config.dateTimezone, {
        options = { { value = 'player', label = 'Player local time' }, { value = 'server', label = 'Server time (UTC)' } },
        label = 'Transaction date timezone', advanced = false,
        description = 'Timezone used for Activity dates. player shows each transaction in the time zone of the player machine (a player in New York sees Eastern time); server shows server time (UTC) to everyone. The older values local and utc still work. Applies the next time Activity is opened.',
    })
    Config.useDailyLimit = config.boolean(Config.useDailyLimit, {
        label = 'Limit daily ATM withdrawals', advanced = false,
        description = 'Enforces the daily personal-account withdrawal allowance at ATMs; bank-counter withdrawals are not blocked by this limit but count toward it. Restart qbbanking to apply saved changes.',
    })
    Config.dailyLimit = config.integer(Config.dailyLimit, {
        min = 0,
        label = 'Daily ATM allowance ($)', advanced = false,
        description = 'Maximum personal-account withdrawals per character since midnight on the database clock when daily limits are enabled. Bank-counter withdrawals also count toward this allowance. Restart qbbanking to apply saved changes.',
    })
    Config.minAmount.withdraw = config.integer(Config.minAmount.withdraw, {
        min = 1,
        label = 'Minimum withdrawal ($)', advanced = false,
        description = 'Smallest amount a player may withdraw (bank counter and ATM). Enforced by the server and shown in the input. 1 keeps the previous behaviour; set it to 5 for a $5 minimum. Applies immediately.',
    })
    Config.minAmount.deposit = config.integer(Config.minAmount.deposit, {
        min = 1,
        label = 'Minimum deposit ($)', advanced = false,
        description = 'Smallest amount a player may deposit (bank counter and ATM). Enforced by the server and shown in the input. 1 keeps the previous behaviour; set it to 5 for a $5 minimum. Applies immediately.',
    })
    Config.minAmount.transfer = config.integer(Config.minAmount.transfer, {
        min = 1,
        label = 'Minimum transfer ($)', advanced = false,
        description = 'Smallest amount a player may transfer (between own accounts and to other players). Enforced by the server and shown in the input. 1 keeps the previous behaviour; set it to 5 for a $5 minimum. Applies immediately.',
    })
    Config.Transfers.allowOffline = config.boolean(Config.Transfers.allowOffline, {
        label = 'Allow transfers to offline players', advanced = false,
        description = 'When on, a transfer to a character who is offline is credited directly in the database and logged for both sides. Turn off to require the recipient to be online (the previous behaviour). Applies immediately; the transfer form text updates after the next config sync.',
    })
    Config.Transfers.allowSharedAccounts = config.boolean(Config.Transfers.allowSharedAccounts, {
        label = 'Allow transfers to shared and business accounts', advanced = false,
        description = 'Lets players enter a shared, society (job) or gang account name as the recipient. Applies immediately.',
    })
    Config.Transfers.allowCardNumbers = config.boolean(Config.Transfers.allowCardNumbers, {
        label = 'Allow transfers by bank card number', advanced = false,
        description = 'Lets players enter the 16-digit number of an issued bank card instead of the account number; the money goes to the personal account of the character the card was issued to. Applies immediately.',
    })
    Config.migrationRetrySeconds = config.integer(Config.migrationRetrySeconds, {
        min = 0, max = 3600,
        label = 'Retry failed database migration (seconds)', advanced = true,
        description = 'When the durable banking database migration fails at startup, retry it after this many seconds. 0 keeps the previous behaviour: log the failure once and leave durable banking disabled until the resource restarts. Applies the next time a migration fails.',
    })
    Config.maxAccounts = config.integer(Config.maxAccounts, {
        min = 0,
        label = 'Shared accounts per character', advanced = false,
        description = 'Maximum shared accounts a character may own; personal and job accounts are not counted. Restart qbbanking to apply saved changes.',
    })
    Config.maxSharedMembers = config.integer(Config.maxSharedMembers, {
        min = 0,
        label = 'Members per shared account', advanced = false,
        description = 'Maximum additional members on a shared account. Lowering this also truncates loaded access lists, so existing members may lose access. Restart qbbanking to apply saved changes.',
    })
    Config.maxSharedMemberBytes = config.integer(Config.maxSharedMemberBytes, {
        min = 0,
        label = 'Member list storage limit (bytes)', advanced = true,
        description = 'Maximum JSON size of a shared-account member list. Oversized stored lists are read as empty and oversized membership updates are rejected. Restart qbbanking to apply saved changes.',
    })
    Config.memberRateLimit.max = config.integer(Config.memberRateLimit.max, {
        min = 0,
        label = 'Membership requests per window', advanced = true,
        description = 'Maximum member-management requests accepted per player during the rolling time window. Further requests are rejected until older requests expire. Restart qbbanking to apply saved changes.',
    })
    Config.memberRateLimit.window = config.integer(Config.memberRateLimit.window, {
        min = 1,
        label = 'Membership request window (milliseconds)', advanced = true,
        description = 'Rolling period used to limit member-management requests per player. 10000 milliseconds equals 10 seconds. Restart qbbanking to apply saved changes.',
    })
    Config.blipInfo.category = config.string(Config.blipInfo.category, {
        minLength = 1,
        label = 'Bank map category', advanced = true,
        description = 'Named kora_lib map-legend category for bank markers; use a supported category name such as Bank. Restart qbbanking to apply saved changes.',
    })
    Config.blipInfo.sprite = config.integer(Config.blipInfo.sprite, {
        label = 'Bank map icon ID', advanced = true,
        description = 'GTA blip sprite ID used for every bank marker. Restart qbbanking to apply saved changes.',
    })
    Config.blipInfo.color = config.integer(Config.blipInfo.color, {
        label = 'Bank map colour ID', advanced = true,
        description = 'GTA blip colour index used for every bank marker. Restart qbbanking to apply saved changes.',
    })
    Config.blipInfo.scale = config.number(Config.blipInfo.scale, {
        min = 0,
        label = 'Bank map icon size', advanced = false,
        description = 'Size multiplier for bank markers; 1 is standard size and 0.55 is 55 percent. Restart qbbanking to apply saved changes.',
    })
    Config.blipInfo.shortRange = config.boolean(Config.blipInfo.shortRange, {
        label = 'Show bank markers only nearby', advanced = false,
        description = 'Makes bank markers short-range on the minimap; their pause-map category remains available. Restart qbbanking to apply saved changes.',
    })
    Config.tiers.enabled = config.boolean(Config.tiers.enabled, {
        label = 'Enable bank tiers (Fleeca / Pacific Standard)', advanced = false,
        description = 'When on, each bank location uses the features, limits and map marker of its tier (Fleeca Bank or Pacific Standard by default). Shared accounts and member management are Pacific Standard only in the default preset. Off keeps every branch identical. Applies immediately for server checks; restart kora_banking to refresh map markers.',
    })
    local tierNames = {}
    for name in pairs(Config.tiers.list) do tierNames[#tierNames + 1] = name end
    table.sort(tierNames)
    local tierOptions = {}
    for _, name in ipairs(tierNames) do tierOptions[#tierOptions + 1] = { value = name, label = Config.tiers.list[name].label or name } end
    Config.tiers.default = config.enum(Config.tiers.default, {
        options = tierOptions,
        label = 'Default bank tier', advanced = false,
        description = 'Tier used by locations that are plain coordinates or name an unknown tier. Applies immediately.',
    })
    for _, name in ipairs(tierNames) do
        local tier = Config.tiers.list[name]
        tier.label = config.string(tier.label, {
            minLength = 1,
            label = name .. ' tier name', advanced = false,
            description = 'Name shown in the app header, in "Available at ..." messages and on the map for this tier. Applies the next time the bank opens.',
        })
        for feature, allowed in pairs(tier.features) do
            tier.features[feature] = config.boolean(allowed, {
                label = name .. ' tier: ' .. feature, advanced = false,
                description = 'Allows ' .. feature .. ' at locations of this tier. Off blocks it on the server and disables it in the app. Applies immediately.',
            })
        end
        tier.limits.dailyWithdraw = config.integer(tier.limits.dailyWithdraw, {
            min = 0,
            label = name .. ' tier daily withdrawal limit ($)', advanced = false,
            description = 'Most a character may withdraw per day (since midnight, database clock) at bank counters of this tier. 0 means no limit. ATMs keep using the daily ATM allowance. Applies immediately.',
        })
        tier.limits.maxTransfer = config.integer(tier.limits.maxTransfer, {
            min = 0,
            label = name .. ' tier largest single transfer ($)', advanced = false,
            description = 'Largest amount one transfer may move at locations of this tier; larger transfers must be made at a tier with a higher limit. 0 means no limit. Applies immediately.',
        })
    end
    Config.locations = config.list(Config.locations, nil, {
        label = 'Bank locations', advanced = true,
        description = 'Bank locations used for interactions, server proximity checks, and map markers. Each entry is plain X/Y/Z coordinates or a table with coords, tier and label. Restart qbbanking to apply saved changes.',
    })
    Config = config.adopt(Config)
end
