-- Declarative banking schema, applied on boot via Kora.sql.ensureTables (additive only: creates missing
-- tables, adds missing columns/keys, never alters existing ones). No SQL files need to be run by hand.
local NULL = Kora.sql.NULL
local COLLATION = 'utf8mb4_unicode_ci'

QBBankingSchema = {
    {
        name = 'bank_accounts',
        collate = COLLATION,
        columns = {
            { name = 'id', type = 'int(11)', auto_increment = true },
            { name = 'citizenid', type = 'varchar(11)', null = true, default = NULL },
            { name = 'account_name', type = 'varchar(50)', null = true, default = NULL },
            { name = 'account_balance', type = 'int(11)', default = 0 },
            { name = 'account_type', type = 'enum', values = { 'shared', 'job', 'gang' } },
            { name = 'users', type = 'longtext', null = true, default = '[]' },
        },
        primary = { 'id' },
        indexes = {
            { name = 'account_name', columns = { 'account_name' }, unique = true },
        },
    },
    {
        name = 'bank_statements',
        collate = COLLATION,
        columns = {
            { name = 'id', type = 'int(11)', auto_increment = true },
            { name = 'citizenid', type = 'varchar(11)', null = true, default = NULL },
            { name = 'account_name', type = 'varchar(50)', null = true, default = 'checking' },
            { name = 'amount', type = 'int(11)', null = true, default = NULL },
            { name = 'reason', type = 'varchar(50)', null = true, default = NULL },
            { name = 'statement_type', type = 'enum', values = { 'deposit', 'withdraw' }, null = true, default = NULL },
            { name = 'date', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
        },
        primary = { 'id' },
        indexes = {
            { name = 'citizenid', columns = { 'citizenid' } },
        },
    },
    {
        name = 'bank_operations',
        columns = {
            { name = 'resource', type = 'varchar(64)' },
            { name = 'operation_key', type = 'varchar(128)' },
            { name = 'request', type = 'longtext' },
            { name = 'receipt', type = 'longtext' },
            { name = 'created_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
        },
        primary = { 'resource', 'operation_key' },
    },
    {
        -- Pinned to utf8mb4_unicode_ci so legs can be UNIONed with bank_statements.
        name = 'bank_operation_legs',
        collate = COLLATION,
        columns = {
            { name = 'id', type = 'bigint', unsigned = true, auto_increment = true },
            { name = 'resource', type = 'varchar(64)' },
            { name = 'operation_key', type = 'varchar(128)' },
            { name = 'leg', type = 'smallint', unsigned = true },
            { name = 'citizenid', type = 'varchar(50)', null = true },
            { name = 'account_name', type = 'varchar(50)', null = true },
            { name = 'direction', type = 'varchar(8)' },
            { name = 'amount', type = 'bigint', unsigned = true },
            { name = 'reason', type = 'varchar(50)' },
            { name = 'created_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
        },
        primary = { 'id' },
        indexes = {
            { name = 'uk_bank_operation_leg', columns = { 'resource', 'operation_key', 'leg' }, unique = true },
            { name = 'idx_bank_leg_character', columns = { 'citizenid', 'created_at' } },
            { name = 'idx_bank_leg_account', columns = { 'account_name', 'created_at' } },
        },
    },
}
