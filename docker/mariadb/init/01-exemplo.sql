-- Executado só na primeira creación do volume de datos.
-- A BD `dwcs` e o usuario `dwcs` xa os crea a imaxe de MariaDB (variables do .env).
-- Sen isto o cliente de inicialización le o ficheiro como latin1 e os acentos
-- gárdanse mal (Ã­...). Inclúeo sempre nos teus scripts .sql.
SET NAMES utf8mb4;

USE dwcs;

CREATE TABLE IF NOT EXISTS alumnado (
    id      INT AUTO_INCREMENT PRIMARY KEY,
    nome    VARCHAR(100) NOT NULL,
    email   VARCHAR(150) NOT NULL UNIQUE,
    creado  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO alumnado (nome, email) VALUES
    ('Uxía Rodríguez', 'uxia@example.com'),
    ('Xoán Pérez',     'xoan@example.com'),
    ('Antía Núñez',    'antia@example.com');
