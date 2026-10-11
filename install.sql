CREATE TABLE IF NOT EXISTS `rsg_overlays` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,
    `owner_name` VARCHAR(100) NOT NULL DEFAULT '',
    `url` VARCHAR(512) NOT NULL,
    `media_type` VARCHAR(16) NOT NULL DEFAULT 'image',
    `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
    `heading` FLOAT NOT NULL DEFAULT 0,
    `width` FLOAT NOT NULL DEFAULT 1.5,
    `height` FLOAT NOT NULL DEFAULT 1.0,
    `opacity` FLOAT NOT NULL DEFAULT 1.0,
    `volume` FLOAT NOT NULL DEFAULT 0.5,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`)
);
