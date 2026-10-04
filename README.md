# dwcs-php

[![CI](https://github.com/miguelfm/dwcs-php/actions/workflows/ci.yml/badge.svg)](https://github.com/miguelfm/dwcs-php/actions/workflows/ci.yml)

Contorna Docker para **desenvolver backend con PHP**, pensada como contorna didáctica para o módulo
**Desenvolvemento Web en Contorna Servidor (DWCS)**. Un só comando arranca PHP 8.5, servidor web, base de datos,
depurador e ferramentas, igual en Linux e en Windows 11 (WSL2). Fóra de Docker non hai que instalar PHP,
servidores nin bases de datos no equipo.

| Servizo      | Que é                                                  | URL / acceso                     |
|--------------|--------------------------------------------------------|----------------------------------|
| `web`        | PHP 8.5 + Apache (ou [FrankenPHP](#servidor-alternativo-frankenphp)), Xdebug 3, Composer, cliente MariaDB, git | <http://localhost> |
| `db`         | MariaDB (última LTS)                                   | `db:3306` (dende PHP) · `localhost:3306` (dende o equipo) |
| `phpmyadmin` | Xestión web da base de datos                           | <http://localhost:8081>          |
| `mailpit`    | *(opcional)* servidor de correo falso para probas      | <http://localhost:8025>          |

## Requisitos

- **Linux:** Docker Engine + plugin `compose`.
- **Windows 11:** WSL2 con Debian e Docker Engine, sen Docker Desktop. Guías:
  [preparación dos equipos (administración)](docs/wsl2-administracion.md) e
  [instalación e uso (alumnado)](docs/wsl2-alumnado.md).
- VS Code coa extensión **PHP Debug** (`xdebug.php-debug`). Ao abrir o proxecto, VS Code propón as extensións recomendadas.

## Posta en marcha

En **Windows 11**, segue a [guía do alumnado](docs/wsl2-alumnado.md). En **Linux**:

```bash
git clone https://github.com/miguelfm/dwcs-php.git
cd dwcs-php
cp .env.example .env      # opcional, só se queres cambiar algo
docker compose up -d      # a primeira vez descarga as imaxes (uns minutos)
```

Abre <http://localhost>: a páxina de comprobación debe saír toda en verde.
O teu código vai na carpeta **`www/`**. Os cambios vense ao recargar o navegador.

Para comprobar a contorna completa (servidor, base de datos, Composer, permisos, Xdebug...):

```bash
./scripts/comprobar.sh
```

> **Linux:** a imaxe publicada usa o UID 1000, o do primeiro usuario de case todas as distribucións. Se o teu é
> outro (comproba con `id`), pon `USER_UID` e `USER_GID` no `.env` e constrúe a túa con `docker compose build`.
> Así os ficheiros que crea PHP son teus e non doutro usuario.

## Comandos do día a día

| Para…                                   | Comando                                         |
|-----------------------------------------|-------------------------------------------------|
| Arrancar / parar                        | `docker compose up -d` / `docker compose stop`  |
| Ver estado                              | `docker compose ps`                             |
| Ver erros de PHP e do servidor web      | `docker compose logs -f web`                    |
| Abrir unha shell no contedor            | `docker compose exec -u dev web bash`           |
| Consola de MariaDB                      | `docker compose exec -u dev web mysql -u dwcs -p dwcs` |
| Consola de MariaDB como root            | `docker compose exec db mariadb -u root -p`     |
| Composer                                | `docker compose exec -u dev web composer require monolog/monolog` |
| Executar un script PHP por consola      | `docker compose exec -u dev web php script.php` |
| Reconstruír tras cambiar Dockerfile/ini | `docker compose up -d --build`                  |
| Actualizar as imaxes publicadas         | `docker compose pull && docker compose up -d`   |
| Comprobar que todo funciona             | `./scripts/comprobar.sh`                        |
| Borrar todo, **incluída a BD**          | `docker compose down -v`                        |

Dentro da shell estás en `/var/www/html` (= a túa carpeta `www/`) co usuario `dev`, que ten `sudo` sen contrasinal.
Para editar ficheiros desde a shell tes `nano`, `vi` e `vis` (estilo vim, con resaltado de sintaxe).

## Base de datos

Credenciais por defecto (cámbianse no `.env`):

| Base de datos | Usuario | Contrasinal | Root       |
|---------------|---------|-------------|------------|
| `dwcs`        | `dwcs`  | `abc123.`   | `abc123.`  |

- **Dende PHP o servidor é `db`, non `localhost`.** As credenciais están tamén en variables de contorna:

  ```php
  $pdo = new PDO(
      'mysql:host=' . getenv('DB_HOST') . ';dbname=' . getenv('DB_NAME') . ';charset=utf8mb4',
      getenv('DB_USER'),
      getenv('DB_PASSWORD'),
      [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
  );
  ```

- **Dende o teu equipo** (DBeaver, HeidiSQL, extensión de VS Code…): `localhost`, porto `3306`.
  MySQL Workbench conecta, pero con MariaDB dá avisos e algunhas funcións fallan.
- **Scripts iniciais:** os `.sql` de `docker/mariadb/init/` execútanse por orde alfabética **só a primeira vez** que se crea a BD.
  Para volver executalos: `docker compose down -v && docker compose up -d`.
  Empeza sempre os teus `.sql` con `SET NAMES utf8mb4;`, porque se non os acentos gárdanse mal.
- Os datos persisten no volume `dwcs_db_data` aínda que pares ou borres os contedores (sen `-v`).

## Depurar con Xdebug

**VS Code no teu equipo:**

1. Abre a carpeta do proxecto (a raíz, non `www/`).
2. Pon un punto de interrupción nun `.php` de `www/`.
3. Pulsa **F5** (configuración «Escoitar Xdebug»).
4. Recarga a páxina no navegador: a execución detense no punto de interrupción.

Xdebug intenta conectar en **todas** as peticións (`start_with_request=yes`). Se VS Code non está escoitando non pasa nada: a páxina carga normal e sen avisos.

O modo cámbiase no `.env` sen reconstruír (despois executa `docker compose up -d`):

| `XDEBUG_MODE`    | Para que                                                      |
|------------------|---------------------------------------------------------------|
| `debug,develop`  | Depuración paso a paso + `var_dump` e erros con formato (por defecto) |
| `debug`          | Só depuración                                                 |
| `coverage`       | Cobertura de código para PHPUnit                              |
| `off`            | Desactivado (o máis rápido)                                   |

Se prefires depurar só cando o pidas, cambia `xdebug.start_with_request` a `trigger` en
`docker/php/conf.d/99-xdebug.ini`, reconstrúe a imaxe e usa a extensión do navegador «Xdebug helper».

## Dev Container (opcional)

Coa extensión **Dev Containers**: *F1 → Dev Containers: Reopen in Container*.
VS Code execútase dentro do contedor `web` co usuario `dev`, e tes PHP, Composer e `mysql` no terminal integrado sen `docker compose exec`.
A depuración funciona igual (F5). Xdebug conecta a `localhost` grazas a `.devcontainer/compose.devcontainer.yaml`.

## Servidor alternativo: FrankenPHP

Por defecto o servidor é Apache con mod_php. Opcionalmente pódese usar [FrankenPHP](https://frankenphp.dev),
un servidor PHP moderno baseado en Caddy. O resto da contorna (MariaDB, phpMyAdmin, Xdebug, `www/`) segue igual.

**Activalo:** descomenta estas dúas liñas no `.env` e executa `docker compose up -d --build`:

```bash
COMPOSE_PATH_SEPARATOR=:
COMPOSE_FILE=compose.yaml:compose.frankenphp.yaml
```

Para volver a Apache, coméntaas de novo e executa `docker compose up -d`.

**Que cambia:**

- **HTTPS:** ademais de <http://localhost>, tes <https://localhost> con HTTP/2 e HTTP/3. O porto cámbiase con `WEB_HTTPS_PORT`.
- **Rutas sen `.htaccess`:** se o ficheiro pedido non existe, a petición pasa ao `index.php` do cartafol raíz
  (controlador frontal, por exemplo `/produtos/7`). Os cartafoles sen `index.php` seguen mostrando a listaxe de ficheiros.
- **Os `.htaccess` ignóranse.** A configuración do servidor está en `docker/frankenphp/Caddyfile`.
- **O contedor xa corre co usuario `dev`:** abonda con `docker compose exec web bash`, sen `-u dev`.
- **Avisos `HTTP/2 skipped` e `no automatic HTTPS` nos logs:** son normais. Refírense ao porto 80, que serve HTTP simple.
- **Dev Container:** engade `"../compose.frankenphp.yaml"` despois de `"../compose.yaml"` en `dockerComposeFile` de `.devcontainer/devcontainer.json`.

**Evitar o aviso de certificado do navegador:** Caddy crea a súa propia autoridade de certificación (válida 10 anos,
consérvase no volume `dwcs_caddy_data`). Para que o navegador confíe nela, extráea:

```bash
docker compose cp web:/data/caddy/pki/authorities/local/root.crt ./caddy-root.crt
```

e impórtaa como autoridade de certificación:

- **Firefox:** *Axustes → Privacidade e seguranza → Ver certificados → Autoridades → Importar*. Marca «Confiar nesta CA para identificar sitios web».
- **Chrome/Edge en Linux:** *Configuración → Privacidade e seguranza → Seguranza → Xestionar certificados → Autoridades → Importar*.
- **Windows (Chrome/Edge):** dobre clic no ficheiro → *Instalar certificado* → *Entidades de certificación raíz de confianza*.
- **macOS:** ábreo con *Acceso a Chaves*, no chaveiro *Sistema*, e marca *Confiar sempre*.

## Problemas habituais

Primeiro executa `./scripts/comprobar.sh`: indica que parte falla e, en moitos casos, como arranxala.

| Síntoma | Solución |
|---------|----------|
| `port is already allocated` / `address already in use` | Outro programa usa ese porto (XAMPP, MySQL/MariaDB local, outro proxecto…). Párao ou cambia `WEB_PORT`, `DB_PORT` ou `PMA_PORT` no `.env`. |
| `SQLSTATE[HY000] [2002] No such file or directory` ou `Connection refused` | Dende PHP usa `host=db`, non `localhost` nin `127.0.0.1`. |
| Os puntos de interrupción non paran | Comproba que VS Code está escoitando (barra inferior laranxa) e que abriches a **raíz** do proxecto (o `pathMappings` apunta a `www/`). En Linux, revisa que o cortalumes permita o porto 9003 dende as redes de Docker. Para diagnosticar, pon `xdebug.log=/tmp/xdebug.log` e `xdebug.log_level=7` no `99-xdebug.ini`, reconstrúe e mira o log. |
| Os acentos saen mal (`Ã¡`) | Engade `charset=utf8mb4` no DSN de PDO e `SET NAMES utf8mb4;` nos `.sql`. Se os datos xa se gardaron mal, hai que volver cargalos. |
| Cambiei un `.sql` de `init/` e non se aplica | Só se executan coa BD baleira: `docker compose down -v && docker compose up -d`. |
| Ficheiros de `www/` propiedade de root (Linux) | Axusta `USER_UID`/`USER_GID` no `.env` e `docker compose build`. Para arranxar os xa creados: `sudo chown -R $USER: www`. |

## Estrutura

```
.
├── compose.yaml              # servizos: web, db, phpmyadmin, mailpit (opcional)
├── compose.frankenphp.yaml   # variante opcional con FrankenPHP
├── Dockerfile                # imaxe dwcs-php (Apache ou FrankenPHP)
├── .env.example              # variables configurables (portos, versións, credenciais, Xdebug)
├── docker/
│   ├── apache/dwcs.conf      # ServerName, AllowOverride All (.htaccess)
│   ├── frankenphp/Caddyfile  # configuración de Caddy (só coa variante FrankenPHP)
│   ├── php/conf.d/
│   │   ├── 90-dwcs.ini       # zona horaria, erros visibles, límites de subida, OPcache
│   │   └── 99-xdebug.ini     # configuración de Xdebug
│   └── mariadb/
│       ├── client/dwcs.cnf   # os comandos `mysql`/`mariadb` conectan a `db` por defecto
│       └── init/             # scripts .sql iniciais
├── www/                      # ← O TEU CÓDIGO (DocumentRoot)
├── scripts/comprobar.sh      # comprobación automática da contorna
├── docs/                     # guías de Windows 11 + WSL2 (administración e alumnado)
├── wsl/                      # scripts de instalación para Windows 11 + WSL2
├── .github/workflows/ci.yml  # probas e publicación das imaxes en ghcr.io
├── .vscode/                  # launch.json (Xdebug) e extensións recomendadas
└── .devcontainer/            # configuración opcional de Dev Container
```

---

## Notas para o profesorado

- **Imaxe:** `php:8.5-apache` ou `dunglas/frankenphp:php8.5`, ambas en Debian 13. Escóllese co argumento de build `SERVER`.
  O `Dockerfile` ten unha fase por servidor e unha fase final común, así que ferramentas e extensións só se definen unha vez. As extensións instálanse con
  [`install-php-extensions`](https://github.com/mlocati/docker-php-extension-installer), que limpa as dependencias de compilación.
  Hai `pdo_mysql`, `mysqli`, `intl`, `zip`, `gd` e `xdebug`, ademais de Composer 2. Para engadir máis, pon o nome na lista do `Dockerfile`.
- **Base de datos:** MariaDB en vez de MySQL. Ocupa menos (imaxe de ~340 MB fronte a ~810 MB, ~125 MB de RAM fronte a ~435 MB),
  e para o que se ve no módulo o comportamento é o mesmo: o DSN segue sendo `mysql:`, e `mysqli`, PDO e phpMyAdmin funcionan igual.
  A etiqueta `lts` colle a última versión de soporte longo. Cando saia unha LTS nova, `docker compose pull` actualiza a imaxe e MariaDB
  actualiza os datos existentes ao arrancar. Para fixar unha versión concreta: `MARIADB_VERSION=12.3` no `.env`.
- **Outra versión de PHP:** `PHP_VERSION=8.4` no `.env` e `docker compose up -d`. Como esa versión non está publicada,
  Compose constrúea co `Dockerfile`. Cada versión ten a súa etiqueta, así que se poden ter varias á vez.
- **PHP execútase co usuario `dev`**, co UID do anfitrión. En Apache vía `APACHE_RUN_USER`, e en FrankenPHP o contedor enteiro corre como `dev`
  (con `setcap` para poder usar os portos 80/443). Así se evitan os problemas de permisos con subidas de ficheiros, `vendor/`, logs…
- **FrankenPHP:** a imaxe ten a etiqueta `8.5-frankenphp` e pode convivir coa de Apache. Usa uns 120 MB de RAM en repouso, fronte aos ~20 MB de Apache.
  O modo worker non está activado: cada petición empeza de cero, como con Apache.
- **OPcache** está activo en PHP 8.5, pero con `revalidate_freq=0` e os cambios vense ao momento.
- **Imaxes publicadas e CI:** GitHub Actions ([`ci.yml`](.github/workflows/ci.yml)) executa `scripts/comprobar.sh`
  coas dúas variantes en cada cambio e en cada pull request. Se as probas pasan en `main`, publica
  `ghcr.io/miguelfm/dwcs-php:8.5` e `:8.5-frankenphp`. Tamén as reconstrúe cada luns para incorporar as actualizacións
  de seguridade de PHP, Debian e FrankenPHP.
  O alumnado descarga as imaxes en vez de compilalas: aforra minutos e evita fallos de rede no build.
  As imaxes publicadas usan o UID 1000.
- **Usar o teu propio repositorio:** fai un fork. O CI publica as imaxes en `ghcr.io/<o-teu-usuario>/dwcs-php`.
  Cambia o valor por defecto de `DWCS_IMAGE` en `compose.yaml` e `compose.frankenphp.yaml`, e a URL en
  [docs/wsl2-alumnado.md](docs/wsl2-alumnado.md).
- **Credenciais:** son de exemplo e só para desenvolvemento local. Non hai que expoñer estes portos fóra do equipo.
- **Correo:** `docker compose --profile mail up -d` arranca Mailpit. Con PHPMailer: `Host=mailpit`, `Port=1025`, sen autenticación nin TLS.
