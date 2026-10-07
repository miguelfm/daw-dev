# Xestionar os contedores DWCS desde Windows 11

Esta guía permite arrancar, parar e consultar os contedores desde PowerShell ou CMD,
en calquera cartafol, co comando `dwcs`. Os comandos e a súa axuda están en inglés.

## Requisitos

- Windows 11 con WSL2 e a distribución **Debian**.
- Docker Engine e Docker Compose instalados dentro de Debian; o usuario de Debian
  debe poder executar `docker` sen `sudo`.
- Este repositorio descargado en Windows. Neste equipo está en
  `C:\Users\miguelfm\Projects\dwcs-php`.

Docker Engine, Compose e Portainer CE xa están instalados neste equipo. Para preparar
outro equipo, consulta a [guía de instalación](wsl2-alumnado.md).
Para proxectos almacenados no sistema de ficheiros de Debian, segue os comandos desa guía.
O comando desta páxina está pensado para a copia do repositorio en Windows; os accesos
desde WSL a ficheiros en `C:` poden ser máis lentos que a ficheiros nativos de Debian.

## Instalar o comando no PATH do usuario

Abre PowerShell, entra na raíz do repositorio e executa:

```powershell
cd C:\Users\miguelfm\Projects\dwcs-php
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wsl\install-dwcs-command.ps1
```

O instalador crea `%USERPROFILE%\.local\bin\dwcs.cmd` e engade ese cartafol ao
PATH do usuario se falta. Non require permisos de administrador. Substitúe calquera
versión anterior dese comando. A opción `ExecutionPolicy Bypass` só se aplica ao
proceso que executa o script; non cambia a política permanente de PowerShell.

Abre unha nova xanela de PowerShell ou CMD e comproba:

```powershell
dwcs help
dwcs status
```

O lanzador chama a `wsl/dwcs.ps1` do repositorio, que determina a raíz do proxecto
a partir da súa propia localización. Se moves o repositorio, executa de novo o instalador.

## Comandos de uso diario

| Comando | Resultado |
|---|---|
| `dwcs start` | Arranca PHP + Apache, MariaDB e phpMyAdmin; agarda ata que estean preparados. |
| `dwcs stop` | Para os contedores DWCS, incluído Mailpit se estaba arrancado. Conserva contedores e datos. |
| `dwcs status` | Mostra o estado, tamén dos contedores parados, e os portos publicados. |
| `dwcs logs` | Mostra as últimas 100 liñas por servizo e segue os novos logs. `Ctrl+C` sae da consulta. |
| `dwcs help` | Mostra a axuda. |

WSL arranca Debian automaticamente ao executar estes comandos. Docker debe estar
configurado para iniciar con Debian. Se non responde, executa:

```powershell
wsl -d Debian -- sudo systemctl enable --now docker
```

O comando usa sempre a configuración `compose.yaml` e o `.env` deste repositorio,
independentemente do cartafol actual do terminal. Respecta os portos e a variante de
servidor que configures no `.env`. Non borra volumes nin a base de datos.

## Acceso aos servizos

Cos portos por defecto:

| Servizo | Acceso |
|---|---|
| PHP + Apache | <http://localhost> |
| phpMyAdmin | <http://localhost:8081> |
| MariaDB desde Windows | `localhost:3306` |
| Portainer CE, se está instalado | <https://localhost:9443> |

O código PHP está en `www/`; os cambios vense ao recargar o navegador.
As credenciais de exemplo da BD son usuario `dwcs`, contrasinal `abc123.` e base
de datos `dwcs`. Dentro dos contedores, o servidor da BD é `db`.

Portainer permite consultar e xestionar os contedores graficamente. O seu certificado
inicial é autofirmado. `dwcs stop` non para Portainer, porque pertence a outro proxecto.
Non despregues unha segunda copia de DWCS desde Portainer: os nomes dos contedores son fixos.

Mailpit é opcional e `dwcs start` non o activa. Para arrancalo desde Windows:

```powershell
wsl -d Debian --cd C:\Users\miguelfm\Projects\dwcs-php -- docker compose --profile mail up -d
```

A súa bandexa de correo está en <http://localhost:8025>.

## Comprobar a contorna

Desde Windows, executa o comprobador incluído no proxecto:

```powershell
wsl -d Debian --cd C:\Users\miguelfm\Projects\dwcs-php -- bash scripts/comprobar.sh
```

Comproba PHP, conexión coa BD, Composer, permisos de ficheiros, actualización dos
cambios, Xdebug e phpMyAdmin. O comprobador arranca a contorna se está parada.

Se `dwcs` non se recoñece, abre un terminal novo ou executa de novo o instalador.
Se un porto está ocupado, cambia o valor correspondente no `.env` e executa `dwcs start`.
