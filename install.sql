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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
