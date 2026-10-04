# Imaxe de desenvolvemento PHP para DWCS
# Inclúe: Xdebug, Composer, cliente MariaDB/MySQL, git e ferramentas básicas de shell.
# Servidor web: Apache + mod_php (por defecto) ou FrankenPHP (build arg SERVER=frankenphp).
ARG PHP_VERSION=8.5
ARG SERVER=apache
ARG USERNAME=dev

# --- Servidor: Apache + mod_php -----------------------------------------------
FROM php:${PHP_VERSION}-apache AS server-apache
ARG USERNAME

# Apache executa PHP co noso usuario en vez de www-data
ENV APACHE_RUN_USER=${USERNAME} \
    APACHE_RUN_GROUP=${USERNAME}

# Configuración de Apache: ServerName, AllowOverride (.htaccess) e mod_rewrite
COPY docker/apache/dwcs.conf /etc/apache2/conf-available/dwcs.conf
RUN a2enconf dwcs && a2enmod rewrite headers

# --- Servidor: FrankenPHP (Caddy) ---------------------------------------------
FROM dunglas/frankenphp:php${PHP_VERSION} AS server-frankenphp

COPY docker/frankenphp/Caddyfile /etc/frankenphp/Caddyfile
# Permite escoitar nos portos 80/443 sen ser root (o contedor corre como `dev`)
RUN setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp

# --- Imaxe final: común aos dous servidores -----------------------------------
FROM server-${SERVER}
ARG USERNAME

# UID/GID do usuario do anfitrión (Linux). Así os ficheiros que crea PHP
# (subidas, cachés, vendor/...) pertencen ao teu usuario e non a root.
ARG USER_UID=1000
ARG USER_GID=1000

# Instalador de extensións: compila, activa e limpa as dependencias de
# compilación nun só paso (imaxe máis pequena e build máis rápido que pecl).
COPY --from=mlocati/php-extension-installer:latest /usr/bin/install-php-extensions /usr/local/bin/

# Ferramentas de shell e cliente de MariaDB (tamén responde ao comando `mysql`).
# Editores: nano, vi (vim-tiny) e vis (estilo vim, ~1,5 MB; lua-lpeg é
# necesario para o resaltado de sintaxe).
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash-completion \
        git \
        less \
        mariadb-client \
        nano \
        sudo \
        unzip \
        vim-tiny \
        vis \
        lua-lpeg \
    && rm -rf /var/lib/apt/lists/*

# Extensións de PHP habituais no módulo + Xdebug + Composer
RUN install-php-extensions \
        pdo_mysql \
        mysqli \
        intl \
        zip \
        gd \
        xdebug \
        @composer

# php.ini de desenvolvemento (display_errors=On, E_ALL...) como base
RUN cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

# Usuario sen privilexios co mesmo UID/GID que o anfitrión, con sudo sen contrasinal.
# Con FrankenPHP tamén é dono dos datos de Caddy (certificados HTTPS locais).
RUN groupadd --gid "$USER_GID" "$USERNAME" \
    && useradd --uid "$USER_UID" --gid "$USER_GID" -m -s /bin/bash "$USERNAME" \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
    && chmod 0440 "/etc/sudoers.d/$USERNAME" \
    && if [ -d /data/caddy ]; then chown -R "$USERNAME:$USERNAME" /data/caddy /config/caddy; fi

# UTF-8 na shell (acentos no cliente mysql, nano...)
ENV LANG=C.UTF-8

# Configuración de PHP e Xdebug
COPY docker/php/conf.d/ "$PHP_INI_DIR/conf.d/"

# Configuración do cliente mariadb/mysql (servidor por defecto: db)
COPY docker/mariadb/client/dwcs.cnf /etc/mysql/conf.d/dwcs.cnf

WORKDIR /var/www/html
