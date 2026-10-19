# Imaxe de desenvolvemento PHP para DAW Dev
# Inclúe: Apache + mod_php, Xdebug, Composer, cliente MariaDB/MySQL, git e ferramentas básicas de shell.
ARG PHP_VERSION=8.5
FROM php:${PHP_VERSION}-apache

ARG USERNAME=dev
# UID/GID do usuario do anfitrión (Linux). Así os ficheiros que crea PHP
# (subidas, cachés, vendor/...) pertencen ao teu usuario e non a root.
ARG USER_UID=1000
ARG USER_GID=1000

# Apache executa PHP co usuario dev e o grupo www-data de Apache
ENV APACHE_RUN_USER=${USERNAME} \
    APACHE_RUN_GROUP=www-data

# Configuración de Apache: ServerName, AllowOverride (.htaccess) e mod_rewrite
COPY docker/apache/daw-dev.conf /etc/apache2/conf-available/daw-dev.conf
RUN a2enconf daw-dev && a2enmod rewrite headers \
    && echo "umask 002" >> /etc/apache2/envvars

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
        bcmath \
        pdo_mysql \
        mysqli \
        intl \
        zip \
        gd \
        xdebug \
        @composer

# php.ini de desenvolvemento (display_errors=On, E_ALL...) como base
RUN cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

# Usuario sen privilexios co mesmo UID/GID que o anfitrión, no grupo www-data e con sudo sen contrasinal.
# Crea a ligazón simbólica /home/dev/html -> /var/www/html e configura permisos e umask 002.
RUN (getent group "$USER_GID" || groupadd --gid "$USER_GID" "$USERNAME") \
    && useradd --uid "$USER_UID" --gid "$USER_GID" -m -s /bin/bash -G www-data "$USERNAME" \
    && usermod -aG "$USERNAME" www-data 2>/dev/null || true \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
    && chmod 0440 "/etc/sudoers.d/$USERNAME" \
    && chmod 0755 "/home/$USERNAME" \
    && ln -s /var/www/html "/home/$USERNAME/html" \
    && chown -h "$USERNAME:$USERNAME" "/home/$USERNAME/html" \
    && echo "umask 002" >> "/home/$USERNAME/.bashrc" \
    && chown -R "$USERNAME:www-data" /var/www/html \
    && chmod -R 2775 /var/www/html

# UTF-8 na shell (acentos no cliente mysql, nano...)
ENV LANG=C.UTF-8

# Configuración de PHP e Xdebug
COPY docker/php/conf.d/ "$PHP_INI_DIR/conf.d/"

# Configuración do cliente mariadb/mysql (servidor por defecto: db)
COPY docker/mariadb/client/daw-dev.cnf /etc/mysql/conf.d/daw-dev.cnf
RUN chmod 0644 /etc/mysql/conf.d/daw-dev.cnf

WORKDIR /var/www/html
