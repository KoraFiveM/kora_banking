Config = {
    transactionCallers = { kora_housing = true },
    ui = { accent = nil },
    atmModels = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm', 'gabz_sm_pb_atmframe' },
    atmDistance = 1.8,
    atmAccessTime = 1500,
    dateFormat = 'locale',
    showTime = true,
    dateTimezone = 'local',
    useDailyLimit = true,
    dailyLimit = 5000,
    minAmount = { withdraw = 1, deposit = 1, transfer = 1 },
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
    locations = {
        vector3(149.05, -1041.3, 29.37),
        vector3(313.32, -280.03, 54.17),
        vector3(-351.94, -50.72, 49.04),
        vector3(-1212.68, -331.83, 37.78),
        vector3(-2961.67, 482.31, 15.7),
        vector3(1175.64, 2707.71, 38.09),
        vector3(247.65, 223.87, 106.29),
        vector3(-111.98, 6470.56, 31.63)
    }
}

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if QB and QB.config and QB.config.adopt then
    local config = QB.config
    Config.atmModels = config.list(Config.atmModels, nil, {
        label = 'ATM models', advanced = true,
        description = 'Model names treated as cash machines by targeting and nearby ATM lookup. Restart qbbanking to apply saved changes.',
    })
    Config.atmDistance = config.number(Config.atmDistance, {
        min = 0,
        label = 'ATM interaction distance (metres)', advanced = false,
        description = 'Maximum client distance for finding or targeting an ATM; the server allows an extra 1 metre of tolerance. Restart qbbanking to apply saved changes.',
    })
    Config.atmAccessTime = config.integer(Config.atmAccessTime, {
        min = 0,
        label = 'ATM access time (milliseconds)', advanced = false,
        description = 'Duration of the cancellable progress bar before opening an ATM. 1000 milliseconds equals 1 second. Restart qbbanking to apply saved changes.',
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
    Config.dateTimezone = config.enum(Config.dateTimezone, {
        options = { { value = 'local', label = 'Player local time' }, { value = 'utc', label = 'UTC' } },
        label = 'Transaction date timezone', advanced = false,
        description = 'Timezone used for Activity dates. local uses the clock offset of each player machine; utc shows the same time for everyone. Applies the next time Activity is opened.',
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
        description = 'Smallest amount a player may withdraw (bank counter and ATM). Enforced by the server and shown in the input. 1 keeps the previous behaviour. Applies immediately.',
    })
    Config.minAmount.deposit = config.integer(Config.minAmount.deposit, {
        min = 1,
        label = 'Minimum deposit ($)', advanced = false,
        description = 'Smallest amount a player may deposit (bank counter and ATM). Enforced by the server and shown in the input. 1 keeps the previous behaviour. Applies immediately.',
    })
    Config.minAmount.transfer = config.integer(Config.minAmount.transfer, {
        min = 1,
        label = 'Minimum transfer ($)', advanced = false,
        description = 'Smallest amount a player may transfer (between own accounts and to other players). Enforced by the server and shown in the input. 1 keeps the previous behaviour. Applies immediately.',
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
    Config.locations = config.list(Config.locations, nil, {
        label = 'Bank locations', advanced = true,
        description = 'World X/Y/Z coordinates in metres for bank interactions, server proximity checks, and map markers. Restart qbbanking to apply saved changes.',
    })
    Config = config.adopt(Config)
end
