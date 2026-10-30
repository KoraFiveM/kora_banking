-- Match banking.sql so bank_operation_legs can be UNIONed with bank_statements on servers whose default collation differs.
ALTER TABLE `bank_operation_legs` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
