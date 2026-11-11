# Despregar DAW Dev nunha aula Windows 11

Este procedemento está pensado para **contas persoais de alumnado**, WSL2 con Debian e Docker Engine.
O profesor administra desde `172.21.34.100`; os equipos de alumnado son `172.21.34.1–35`.
Os exemplos usan o dominio `iesrodolfoucha.es` e nomes `A34EQ01`…`A34EQ35`.
Con `-Aula 31 -Numero 1` as mesmas ferramentas apuntan só ao equipo 01 da aula 31.

## Como funciona

1. O profesor activa WinRM desde a rede con PsExec, unha ferramenta asinada de Microsoft.
2. Instala WSL en cada Windows e reinicia os equipos que o precisen.
3. Constrúe **un modelo limpo Debian**, con Docker Engine, Compose, o proxecto e as tres imaxes descargadas.
4. Copia o modelo unha vez a cada equipo, en `C:\ProgramData\DAW-Aula`, protexido contra escritura do alumnado.
5. **Activación da contorna:**
   - **En aulas compartidas (configuración aplicada na Aula 34):** A activación realízase baixo demanda polo profesor durante a clase mediante `.\wsl\aula\gestionar-aula.ps1 -Action InstalarUsuario -Aula 34`. Deste xeito, os alumnos alleos ao módulo que utilicen os mesmos equipos non sofren ningún atraso no inicio de sesión, nin consumo de disco no seu perfil, nin ven ningún aviso nin acceso directo.
   - **En aulas de uso exclusivo:** Pódese manter a entrada `Run` en Windows para que cada alumno importe automaticamente a súa distribución no primeiro inicio de sesión.
6. A contorna configura o usuario predeterminado de Linux como **`ad`** (mantendo compatibilidade total con `alumno`), con acceso directo en Windows Explorer en `\\wsl.localhost\Debian-DAW\home\ad\www` e un acceso directo no Escritorio (**«DAW - Proxectos (www)»**). Desde PowerShell ou CMD, o alumno usa `daw-start`, `daw-start-all`, `daw-stop` e `daw-status`, sen elevación.

As distribucións WSL son **por conta Windows e por equipo**: instalar Debian como administrador non o instala
nas contas do alumnado. Se un alumno cambia de equipo, nese equipo terá outra copia. Os datos e o código
non se sincronizan entre equipos; usa Git ou copias de seguridade.

## Requisitos de administración remota

- Conta do dominio con permisos de administrador nos equipos. Inicia sesión con esa conta no profesor.
- Nomes DNS correctos. Os scripts usan nomes DNS e **Kerberos**, evitando contrasinais en ficheiros e
  configuracións globais de `TrustedHosts`.
- Compartición administrativa `admin$`/`c$` e administración de servizos accesibles pola LAN.
  A preparación inicial usa SMB e PsExec; ter só Veyon instalado non garante estes accesos.
- Veyon serve para visualizar o equipo e iniciar sesión remotamente coas súas funcións habituais.
  A importación inmediata usa unha tarefa co token interactivo de Windows e require un alumno conectado;
  a copia do paquete e a preparación Windows non requiren ningunha sesión de alumno.
- Virtualización na BIOS/UEFI, Windows 11 x64 e espazo para o modelo e as copias por usuario.
  Reserva inicialmente arredor de 10–15 GB por usuario e mide o crecemento real de código e BD.

WinRM restrínxese ao IP do profesor da aula. Non se activa Basic nin se permite tráfico WinRM sen cifrar.
Kerberos cifra o contido das sesións tamén usando HTTP/5985. Se xa hai regras WinRM adicionais creadas polo
centro, a administración debe comprobar que non amplían o acceso: o script axusta as regras estándar HTTP.
Se a política do centro bloquea PsExec ou a administración SMB, a alternativa é unha GPO de arranque para
executar `wsl/aula/habilitar-winrm.ps1`; Veyon StartApp executa co usuario conectado e non concede elevación.

## 1. Diagnóstico desde o profesor

Desde a raíz deste repositorio:

```powershell
# Proba pequena, aula 31
.\wsl\aula\gestionar-aula.ps1 -Action Comprobar -Aula 31 -Numero 1 | Format-Table -AutoSize

# Aula de destino completa: non modifica os equipos
.\wsl\aula\gestionar-aula.ps1 -Action Comprobar -Aula 34 | Format-Table -AutoSize
```

Os portos son `5985` (WinRM HTTP), `5986` (WinRM HTTPS) e `11100` (Veyon).
Un porto pechado non distingue entre servizo desactivado, cortalumes e equipo apagado.
Se HTTP responde, o script comproba tamén o protocolo WSMan. Para comprobar os permisos:

```powershell
Invoke-Command -ComputerName A31EQ01.iesrodolfoucha.es -Authentication Kerberos -ScriptBlock { whoami; hostname }
```

## 2. Activar WinRM e preparar Windows

Comeza sempre cun equipo libre e despois estende o procedemento.

```powershell
.\wsl\aula\gestionar-aula.ps1 -Action HabilitarWinRM -Aula 31 -Numero 1
.\wsl\aula\gestionar-aula.ps1 -Action PrepararWSL -Aula 31 -Numero 1
```

O primeiro comando descarga PsExec desde Microsoft se falta, comproba a súa sinatura e executa a preparación
como SYSTEM no destino, usando a autorización da túa conta administradora. Acepta a EULA de PsExec coa
opción `-accepteula`. Non necesita as credenciais do alumno. Os scripts de usuario **nunca** se lanzan como SYSTEM.

O segundo descarga unha vez o MSI oficial de WSL no profesor, comproba a sinatura Microsoft e cópiao ao
destino. Activa as características Windows e informa de `RestartRequired`. Non reinicia automaticamente.
Podes usar `-WslMsi C:\ruta\wsl.<version>.x64.msi` para un MSI xa descargado.

Se o resultado require reinicio, faino nun momento sen alumnos traballando mediante WinRM (evitando `Restart-Computer`, que emprega RPC/135 bloqueado por defecto polo cortalumes):

```powershell
$equipos = @(1..35) | ForEach-Object { "A34EQ{0:D2}.iesrodolfoucha.es" -f $_ }
Invoke-Command -ComputerName $equipos -Authentication Kerberos -ScriptBlock {
    shutdown.exe /r /t 5 /f /d p:2:4
}
```

Despois do reinicio comproba de novo WinRM. Para acelerar o despregamento na aula completa, pódese empregar `wsl/aula/gestionar-aula-paralelo.ps1`, que executa as fases de `PrepararWSL` e `CopiarModelo` en lotes concorrentes seguros de 5 equipos mediante *jobs* de PowerShell, reducendo o tempo total da aula a menos de 15 minutos:

```powershell
# Preparación concorrente en lotes de 5
.\wsl\aula\gestionar-aula-paralelo.ps1 -Action PrepararWSL -Aula 34 -Numero @(1..5)
.\wsl\aula\gestionar-aula-paralelo.ps1 -Action CopiarModelo -Aula 34 -Numero @(1..5)
```

## 3. Construír o modelo unha vez

No profesor, con WSL2 xa instalado, PowerShell normal, Git e acceso a Internet:

```powershell
.\wsl\aula\preparar-modelo.ps1 -OutputDirectory C:\DAW-Paquete-2026
```

O directorio de saída debe ser novo. O script crea unha distribución separada `DAW-Modelo` e nunca usa a
Debian persoal do profesor. Descarga a base oficial indicada no catálogo Microsoft WSL e comproba SHA256.
Instala Docker desde o repositorio oficial e precarga PHP/Apache, MariaDB e phpMyAdmin.
Non crea contedores nin volumes de BD no modelo. Conserva a distribución modelo para inspección.

O código inicial procede dos ficheiros versionados de `git archive HEAD`, cos lanzadores e o configurador
locais desta entrega. Non copia `.env` persoais, traballos non versionados de `www`, claves nin o perfil
do profesor. O usuario Linux é `alumno`, UID/GID 1000, con contrasinal bloqueado e acceso ao grupo Docker.
Para administración Linux posterior, o propietario da distribución pode usar `wsl -d Debian-DAW -u root`.
Isto non lle concede permisos de administrador de Windows.

O modelo usa o Compose do proxecto, incluída a ruta pública histórica `ghcr.io/miguelfm/dwcs-php:8.5`,
e conserva `/home/alumno/proxectos/daw-dev/www` e o volume `daw-dev_db_data` para os datos de cada conta.
Configura `WEB_PORT=127.0.0.1:80`, `PMA_PORT=127.0.0.1:8081` e `DB_PORT=127.0.0.1:3306`.
Non se abre o socket Docker pola rede. VS Code debe conectarse a WSL para usar Xdebug.

`debian-daw.tar.gz` comprime a imaxe para reducir a copia pola LAN.
`manifest.json` rexistra o SHA256 da imaxe, a base oficial, a data e o commit do proxecto.
O subdirectorio `build` é material de construción e non se copia aos alumnos.
Se a construción falla, conserva o log e inspecciona `DAW-Modelo`: non reutilices unha distribución persoal
nin borres ningunha distribución con traballo. Para outro modelo, usa `-Distribution DAW-Modelo-v2` e outro
directorio de saída. `-BaseImagePath` permite reutilizar a descarga Debian, verificándoa contra o catálogo actual.

Se falla só a descarga das imaxes, `-Resume` continúa o mesmo modelo a partir do checkpoint verificado,
sen reinstalar Debian. Tamén podes aproveitar imaxes xa descargadas nunha Debian do profesor:

```powershell
wsl -d Debian --exec docker image save --output /mnt/c/DAW-images.tar ghcr.io/miguelfm/dwcs-php:8.5 mariadb:lts phpmyadmin:latest
.\wsl\aula\preparar-modelo.ps1 -OutputDirectory C:\DAW-Paquete-2026 -Resume -DockerImagesArchive C:\DAW-images.tar
```

Só se copian imaxes; os volumes, contedores e datos do profesor non forman parte de `docker image save`.

## 4. Copiar aos equipos e activar por usuario

```powershell
.\wsl\aula\gestionar-aula.ps1 -Action CopiarModelo -Aula 31 -Numero 1 -PackageDirectory C:\DAW-Paquete-2026
```

Verifica o SHA256 antes e despois da copia. A carpeta local só permite escritura a SYSTEM e Administradores;
os usuarios teñen lectura e execución. Non depende de compartir credenciais nin dun servidor accesible
no momento de iniciar sesión.

Configura a entrada `DAWAula` en `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` para lanzar o
instalador **sen elevación na conta que inicia sesión**. A primeira importación tarda varios minutos e
consome disco. O arranque posterior sáltaa se xa rematou ben. As políticas Windows que impidan programas
de inicio ou WSL deberán permitilos. Non se modifica a política permanente de execución de PowerShell.

Se xa está conectado o alumno, non necesita pechar sesión:

```powershell
.\wsl\aula\gestionar-aula.ps1 -Action InstalarUsuario -Aula 31 -Numero 1
.\wsl\aula\gestionar-aula.ps1 -Action Estado -Aula 31 -Numero 1 | Format-List
```

A tarefa usa `LogonType Interactive` e `RunLevel Limited`: non pide contrasinais nin usa SYSTEM.
O comando só confirma que se solicitou a execución; **Estado** confirma o resultado real de cada perfil.
Os rexistros por usuario están en `%LOCALAPPDATA%\DAW-Aula\instalacion.log` e `estado.json`.
Para executalo manualmente, na conta do alumno:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\DAW-Aula\instalar-alumno.ps1
```

### Xestión en aulas compartidas con outros módulos (Activación baixo demanda)

Nas aulas que se comparten con outros ciclos ou materias onde o resto do alumnado non debe ver ningunha información nin sufrir atrasos no inicio de sesión nin consumo de disco no seu perfil:
- **Sen auto-inicio en `HKLM`:** Retírase a entrada `DAWAula` de `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`. Deste xeito, os alumnos alleos traballan sen que Windows execute ningún proceso nin xere accesos directos.
- **Activación puntual na clase de DAW:** Cando os alumnos do módulo están cos equipos iniciados, o profesor activa a contorna desde o seu equipo cun só comando:
  ```powershell
  .\wsl\aula\gestionar-aula.ps1 -Action InstalarUsuario -Aula 34
  ```
- A importación execútase de xeito limpo, interactivo e unicamente no perfil do alumno de DAW que estea presente nese posto.

Repetir o instalador non substitúe unha Debian-DAW existente nin borra datos. Se a conta xa usa outro modelo,
detense: actualizar o modelo distribuído non é un mecanismo para actualizar os proxectos existentes.

## 5. Uso diario sen administrador

Para o material de clase ou entrega ao alumnado, disponse da [guía rápida de inicio e uso en Markdown para PDF](guia-inicio-alumnado.md).

Abre unha terminal nova despois da primeira instalación:

| Comando | Resultado |
|---|---|
| `daw-start` ou `daw-star` | Só PHP + Apache; sen arrancar as dependencias |
| `daw-start-db` | Web + MariaDB |
| `daw-start-all` | Web + MariaDB + phpMyAdmin |
| `daw-stop` | Para os servizos e conserva a BD e o código |
| `daw-status` | Lista tamén contedores parados |
| `daw-code` | Abre o proxecto en VS Code listo para Dev Containers |
| `daw-help` | Axuda dos comandos Windows |

Accede a `http://localhost`, `http://localhost/index.php` e `http://localhost:8081`.
phpMyAdmin e a comprobación de BD requiren `daw-start-all`. As credenciais de desenvolvemento son as do
`.env.example`; os portos quedan limitados ao equipo local.

### Acceso directo aos ficheiros web e contorna Linux

O instalador migra o usuario do modelo a `ad` e configura a ruta simplificada do *document root*:
- **Dende Windows Explorer:** `\\wsl.localhost\Debian-DAW\home\ad\www` (ou a través do acceso directo creado automaticamente no Escritorio: **«DAW - Proxectos (www)»**).
- **Con VS Code e Dev Containers:**
  O instalador preinstala automaticamente no perfil do alumno as extensións `ms-vscode-remote.remote-containers` e `ms-vscode-remote.remote-wsl` se VS Code está instalado no equipo. O alumno só ten que executar:
  ```powershell
  daw-code
  ```
  Ao abrirse o proxecto en VS Code, aparecerá unha mensaxe emerxente para reabrir no contedor (ou premendo `F1` e seleccionando **«Dev Containers: Reopen in Container»**). Grazas á imaxe precompilada local, a contorna ábrese de xeito instantáneo coas ferramentas (PHP 8.5, Composer, Xdebug, MariaDB client) listas para traballar.
- **Dende a terminal de Debian:** O usuario predeterminado é `ad`. O cartafol `~/www` liga directamente á raíz de Apache. Para traballar con VS Code estándar:
  ```powershell
  wsl -d Debian-DAW --cd /home/ad/www
  code .
  ```
- Mantense a compatibilidade total coa ruta interna histórica `/home/alumno/proxectos/daw-dev/www` mediante ligazóns simbólicas transparentes.

Os lanzadores Windows arrancan WSL se está parado, agardan por Docker e manteñen unha sesión oculta
mentres existan contedores do proxecto en marcha. `daw-stop` deixa rematar esa sesión en ata 20 segundos.
Dentro de Debian tamén hai comandos de terminal; conserva aberta esa terminal mentres traballas.
O uso diario non necesita UAC, `sudo`, contrasinal Linux nin administrador de Windows. O grupo Docker dá
control administrativo **dentro desta Debian**, como explica a documentación de Docker.

O alumno debe parar a contorna antes de pechar sesión. Evita deixar dous usuarios executando servizos
simultaneamente no mesmo Windows: os portos locais son compartidos e poderían entrar en conflito.
Non se configura autoinicio dos contedores ao iniciar Windows nin se usa `down -v`, `prune` ou `unregister`
nos scripts de usuario.

## Fontes e comprobacións

- [WSL por usuario: preguntas frecuentes Microsoft](https://learn.microsoft.com/en-us/windows/wsl/faq).
- [Importar distribucións WSL](https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro).
- [Systemd non mantén WSL aberto por si só](https://learn.microsoft.com/en-us/windows/wsl/systemd).
- [PsExec oficial Microsoft](https://learn.microsoft.com/en-us/sysinternals/downloads/psexec).
- [WinRM e autenticación](https://learn.microsoft.com/en-us/windows/win32/winrm/authentication-for-remote-connections).
- [Veyon StartApp executa como usuario conectado](https://github.com/veyon/veyon/blob/main/plugins/desktopservices/DesktopServicesFeaturePlugin.cpp).
- [Permisos do grupo Docker](https://docs.docker.com/engine/install/linux-postinstall/).

As probas reais e as súas limitacións desta entrega rexístranse en `docs/aula-validacion.md`.
