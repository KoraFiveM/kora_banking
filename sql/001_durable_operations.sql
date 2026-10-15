CREATE TABLE IF NOT EXISTS `bank_operations` (
  `resource` VARCHAR(64) NOT NULL,
  `operation_key` VARCHAR(128) NOT NULL,
  `request` LONGTEXT NOT NULL,
  `receipt` LONGTEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`resource`, `operation_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `bank_operation_legs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `resource` VARCHAR(64) NOT NULL,
  `operation_key` VARCHAR(128) NOT NULL,
  `leg` SMALLINT UNSIGNED NOT NULL,
  `citizenid` VARCHAR(50) NULL,
  `account_name` VARCHAR(50) NULL,
  `direction` VARCHAR(8) NOT NULL,
  `amount` BIGINT UNSIGNED NOT NULL,
  `reason` VARCHAR(50) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_bank_operation_leg` (`resource`, `operation_key`, `leg`),
  KEY `idx_bank_leg_character` (`citizenid`, `created_at`),
  KEY `idx_bank_leg_account` (`account_name`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
