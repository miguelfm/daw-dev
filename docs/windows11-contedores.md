# Xestionar os contedores DAW Dev desde Windows 11

Esta guía permite arrancar, parar e consultar os contedores desde PowerShell ou CMD,
en calquera cartafol, cos comandos `daw-dev-*`. Os comandos e a súa axuda están en inglés.

## Requisitos

- Windows 11 con WSL2 e a distribución **Debian**.
- Docker Engine e Docker Compose instalados dentro de Debian; o usuario de Debian
  debe poder executar `docker` sen `sudo`.
- Este repositorio descargado en Windows. Neste equipo está en
  `C:\Users\miguelfm\Projects\daw-dev`.

Docker Engine, Compose e Portainer CE xa están instalados neste equipo. Para preparar
outro equipo, consulta a [guía de instalación](wsl2-alumnado.md).
Para proxectos almacenados no sistema de ficheiros de Debian, segue os comandos desa guía.
Os comandos desta páxina están pensados para a copia do repositorio en Windows; os accesos
desde WSL a ficheiros en `C:` poden ser máis lentos que a ficheiros nativos de Debian.

## Instalar os comandos no PATH do usuario

Abre PowerShell, entra na raíz do repositorio e executa:

```powershell
cd C:\Users\miguelfm\Projects\daw-dev
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wsl\install-daw-dev-commands.ps1
```

O instalador crea sete lanzadores `daw-dev-*.cmd` en `%USERPROFILE%\.local\bin` e engade
ese cartafol ao PATH do usuario se falta. Non require permisos de administrador. Para actualizar
unha instalación anterior, executa de novo o instalador: substitúe os lanzadores e retira
os antigos lanzadores `dwcs*.cmd` cando apuntan a esta copia do repositorio ou ao seu antigo
cartafol `dwcs-php`. Véxase tamén a [guía de migración](renomeado-daw-dev.md).
A opción `ExecutionPolicy Bypass` só se aplica ao
proceso que executa o script; non cambia a política permanente de PowerShell.

Abre unha nova xanela de PowerShell ou CMD e comproba:

```powershell
daw-dev-help
daw-dev-status
```

Os lanzadores chaman a `wsl/daw-dev.ps1` do repositorio, que determina a raíz do proxecto
a partir da súa propia localización. Se moves o repositorio, executa de novo o instalador.

## Comandos de uso diario

| Comando | Resultado |
|---|---|
| `daw-dev-start` | Arranca só `daw-dev-web`, sen arrancar dependencias; agarda ata que estea preparado. |
| `daw-dev-start-db` | Arranca MariaDB e o web xuntos; agarda ata que estean preparados. |
| `daw-dev-start-all` | Arranca o web, MariaDB e phpMyAdmin; agarda ata que estean preparados. |
| `daw-dev-stop` | Para os contedores DAW Dev. Conserva contedores e datos. |
| `daw-dev-status` | Mostra unha táboa compacta co nome, estado e portos, tamén dos contedores parados. |
| `daw-dev-logs` | Mostra as últimas 100 liñas por servizo e segue os novos logs. `Ctrl+C` sae da consulta. |
| `daw-dev-help` | Mostra a axuda. |

`daw-dev-start` permite traballar con PHP sen base de datos. Se os outros contedores
xa estaban en marcha, seguen en marcha. Para pasar da contorna completa a só web:

```powershell
daw-dev-stop
daw-dev-start
```

Sen MariaDB, o código que precise a BD fallará e a páxina de comprobación mostrará
un erro na conexión á BD. Para arrancar a BD e o web, executa `daw-dev-start-db`.
Para volver á contorna completa, executa `daw-dev-start-all`.

WSL arranca Debian automaticamente ao executar estes comandos. Docker debe estar
configurado para iniciar con Debian. Se non responde, executa:

```powershell
wsl -d Debian -- sudo systemctl enable --now docker
```

Os comandos usan sempre a configuración `compose.yaml` e o `.env` deste repositorio,
independentemente do cartafol actual do terminal. Respecta os portos que configures no `.env`. Non borra volumes nin a base de datos.

## Consola do contedor web

Co contedor en marcha, podes abrir unha consola desde calquera cartafol de PowerShell ou CMD.
Como Docker está dentro de Debian, chama ao comando a través de WSL2:

```powershell
wsl -d Debian -- docker exec -it -u dev daw-dev-web bash
```

Entrarás como `dev` en `/var/www/html`. Se precisas unha consola como root:

```powershell
wsl -d Debian -- docker exec -it -u root daw-dev-web bash
```

Escribe `exit` para pechar a consola; o contedor segue funcionando. Se está parado,
arráncao antes con `daw-dev-start`. Substitúe `Debian` se usas outra distribución de WSL.

Se tes Docker dispoñible directamente en Windows, podes executar
`docker exec -it -u dev daw-dev-web bash` sen o prefixo `wsl -d Debian --`.
O [README](../README.md#consola-do-contedor-web) explica tamén a alternativa con Docker Compose
e o acceso desde outro equipo por SSH ao anfitrión.

## Acceso aos servizos

Cos portos por defecto:

| Servizo | Acceso |
|---|---|
| PHP + Apache | <http://localhost> |
| phpMyAdmin | <http://localhost:8081> |
| MariaDB desde Windows | `localhost:3306` |
| Portainer CE, se está instalado | <https://localhost:9443> |

O código PHP está en `www/`; os cambios vense ao recargar o navegador.
Ao abrir <http://localhost> ou un subdirectorio, móstrase a listaxe de ficheiros,
mesmo se existe `index.php` ou `index.html`. Para executar a páxina de comprobación,
abre <http://localhost/index.php>. Para outros exercicios, abre o ficheiro PHP concreto.
Este comportamento vén configurado por defecto en Apache.
As credenciais de exemplo da BD son usuario `dwcs`, contrasinal `abc123.` e base
de datos `dwcs`. Dentro dos contedores, o servidor da BD é `db`.

Portainer permite consultar e xestionar os contedores graficamente. O seu certificado
inicial é autofirmado. `daw-dev-stop` non para Portainer, porque pertence a outro proxecto.
Non despregues unha segunda copia de DAW Dev desde Portainer: os nomes dos contedores son fixos.

## Comprobar a contorna

Desde Windows, executa o comprobador incluído no proxecto:

```powershell
wsl -d Debian --cd C:\Users\miguelfm\Projects\daw-dev -- bash scripts/comprobar.sh
```

Comproba PHP, conexión coa BD, Composer, permisos de ficheiros, actualización dos
cambios, Xdebug e phpMyAdmin. O comprobador arranca a contorna se está parada.

Se `daw-dev-start` non se recoñece, abre un terminal novo ou executa de novo o instalador.
Se un porto está ocupado, cambia o valor correspondente no `.env` e executa `daw-dev-start`.
