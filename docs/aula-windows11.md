# Despregar DAW Dev nunha aula Windows 11

Este procedemento está pensado para **contas persoais de alumnado**, WSL2 con Debian e Docker Engine.
O profesor administra desde `172.21.34.100`. Na aula 134, o inventario
verificado vai de `A34EQ01` a `A34EQ33` (`172.21.34.1–33`).
Os exemplos usan o dominio `iesrodolfoucha.es` e o identificador de aula `34`.
Con `-Aula 31 -Numero 1` as mesmas ferramentas apuntan só ao equipo 01 da aula 31.

A revisión do 13/11/2026 cambia os scripts e o contrato dos paquetes. Antes de reutilizar un paquete antigo, consultar [actualización segura e cambios](aula-correccions-20261113.md).

Consulta o [estado e versións da aula 134 ao 20/11/2026](aula-despregamento-20261118.md#estado-do-20112026)
e o [despregamento na aula 31 do 19/11/2026](aula-despregamento-20261119-aula31.md).
Se un posto responde por Veyon pero non por WinRM, comproba que o seu nome
DNS resolve á IP da aula. Os scripts de administración usan o nome e Kerberos.

## Como funciona

1. O profesor activa WinRM desde a rede con PsExec, unha ferramenta asinada de Microsoft.
2. Instala WSL en cada Windows e reinicia os equipos que o precisen.
3. Constrúe **un modelo limpo Debian**, con Docker Engine, Compose, o proxecto e as tres imaxes descargadas.
4. Copia o modelo unha vez a cada equipo, en `C:\ProgramData\DAW-Aula`, protexido contra escritura do alumnado.
5. **Activación da contorna:**
   - **En aulas compartidas (aulas 31 e 134):** Cada usuario activa o seu contorno cando o necesita desde **Inicio → DAW Dev → Activar DAW Dev**. O profesor tamén pode instalar o modelo na conta activa mediante `.\wsl\aula\gestionar-aula.ps1 -Action InstalarUsuario -Aula 31` (ou `-Aula 34`). Cada conta decide cando iniciar a contorna con `daw-start` ou `daw-start-all`.
   - **En aulas de uso exclusivo:** Só engadindo `-AutoInicio` a `CopiarModelo` se activa a entrada `Run` en Windows para que cada alumno importe automaticamente a súa distribución no primeiro inicio de sesión.
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

Despois do reinicio comproba de novo WinRM. Para acelerar o despregamento na aula completa, pódese empregar `wsl/aula/gestionar-aula-paralelo.ps1`, que executa as fases de `PrepararWSL` e `CopiarModelo` cun límite interno de 5 equipos mediante *jobs* de PowerShell. Pódese axustar con `-ThrottleLimit`; o tempo depende da rede e dos discos:

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

Por defecto retira a entrada xestionada `DAWAula` en `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`, conservando a activación baixo demanda. Para unha aula exclusiva, `-AutoInicio` permite expresamente executar o instalador na conta que inicia sesión. Non se modifica a política permanente de execución de PowerShell. A copia comproba tamén os hashes dos scripts; actualizar paquetes antigos con `actualizar-paquete.ps1`.

Se xa está conectado o alumno, non necesita pechar sesión:

```powershell
.\wsl\aula\gestionar-aula.ps1 -Action InstalarUsuario -Aula 31 -Numero 1
.\wsl\aula\gestionar-aula.ps1 -Action Estado -Aula 31 -Numero 1 | Format-List
```

A tarefa usa `LogonType Interactive` e `RunLevel Limited`: non pide contrasinais nin usa SYSTEM.
O comando espera o resultado do GUID e SID da solicitude actual, con timeout e comprobación de erros. **Estado** mostra o último informe por perfil, coa súa data e RequestId; non confundir un rexistro histórico cunha instalación nova.
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
Para iso está a acción seguinte.

### Actualizar os ficheiros dos proxectos xa importados

`ActualizarProxecto` copia `wsl/aula/proxecto/ficheiros` en `/home/ad/proxectos/daw-dev` da
Debian-DAW do alumno conectado, sen volver copiar o modelo de 1,4 GB. O contido actual e as
regras da copia están no [README dos ficheiros do proxecto](../wsl/aula/proxecto/README.md).

```powershell
# Primeiro nun posto; despois no resto, de 5 en 5
.\wsl\aula\gestionar-aula.ps1 -Action ActualizarProxecto -Aula 34 -Numero 16 | Format-List
.\wsl\aula\gestionar-aula-paralelo.ps1 -Action ActualizarProxecto -Aula 34 -Numero @(1..35)
```

Para cada posto:

1. No profesor, prepara unha vez un directorio temporal cos ficheiros, `actualizar-proxecto.ps1`,
   o módulo e `proxecto.json`, cos SHA256 e unha revisión.
2. Por WinRM, crea `C:\ProgramData\DAW-Aula\proxecto` coa mesma ACL ca o paquete (escritura só para
   SYSTEM e Administradores) e baleira o anterior, se non hai unha instalación en curso.
3. Copia o directorio por SMB, restablece as ACL e volve comprobar os SHA256 no posto.
4. Executa `actualizar-proxecto.ps1` cunha tarefa temporal co token do alumno conectado, como
   `InstalarUsuario`, e agarda polo `proxecto-estado.json` desa solicitude.

No alumno, o script comproba que a distribución é o modelo DAW co seu rexistro de orixe e copia
os ficheiros como `ad`. O resultado de cada posto leva en `Data` a revisión e as listas `Created`,
`Replaced`, `Unchanged` e `Kept`, e `Backup` se gardou copias. Os rexistros por usuario están en
`%LOCALAPPDATA%\DAW-Aula\proxecto.log` e `proxecto-estado.json`.

- Necesita unha única sesión de alumno no posto. Sen sesión, ou se a conta aínda non ten
  Debian-DAW, o posto devolve `Success=False` co motivo; repetir só eses postos con `-Numero`.
- O módulo vai na propia copia, polo que non depende dos scripts que deixou `CopiarModelo`.
- Por defecto non reinicia nada: os cambios aplícanse no seguinte `daw-start`. `-Reiniciar` recrea
  o contedor web se está en marcha; pecha unha sesión aberta de Dev Containers e as sesións de PHP.
- Repetila coa mesma revisión non cambia nada. Unha conta que importe Debian-DAW despois
  necesita outra vez `ActualizarProxecto`.

### Activación manual desde o menú Inicio

Desde o 19/11/2026, `CopiarModelo` deixa tamén en cada equipo os ficheiros do proxecto
(`C:\ProgramData\DAW-Aula\proxecto`, cos seus SHA256) e a entrada **DAW Dev → Activar DAW
Dev** no menú Inicio común. Calquera usuario a executa cando a necesita, sen administración:
`activar-dawdev.ps1` lanza `instalar-alumno.ps1` na súa conta e despois
`actualizar-proxecto.ps1`, nunha xanela que amosa o progreso. Non se engade nada ao inicio
de sesión, e os usuarios doutros módulos só ven a entrada no menú.

- Repetir a activación é seguro, e é a forma de que unha conta xa activada reciba as
  ordes `daw-*` e os ficheiros do proxecto novos.
- O instalador rexeita as contas con elevación, como o Administrador integrado (`-500`);
  comprobado no posto A34EQ01. Unha conta de dominio con UAC actívase sen elevar.
- `InstalarUsuario` e `ActualizarProxecto` seguen dispoñibles para facelo desde o
  profesor co alumno conectado.

### Imaxes Docker adicionais: Angular (DWCC)

O servizo `angular` de `compose.yaml` (perfil `angular`, contedor `daw-dev-angular`) trae
Node.js 26 e Angular CLI 22, cos proxectos en `~/proxectos/daw-dev/angular` e
`ng serve` publicado en `127.0.0.1:4200`. Non ten SSH. `daw-code-angular` arranca o
contedor e abre VS Code en Debian-DAW por WSL co espazo de traballo
`docker/angular/DWCC-Angular.code-workspace`, cuxo terminal entra no contedor con
`docker exec`. `daw-start-angular` só o arranca. O uso está na
[guía de Angular para o alumnado](guia-angular-alumnado.md).

Do kit DWCC-Angular (`Angular-Aula.cmd`), que queda como referencia sen manter, tómanse
o contedor sen SSH co usuario `node`, o terminal de VS Code no contedor e a instalación
do VS Code Server desde un `.tar.gz` do mesmo commit. O resto do kit xa o resolve a
aula: WSL, Debian e Docker, as contas, e o grupo `docker` en vez de `sudo`. Engádese
`init: true`: `sleep infinity` non atende SIGTERM, e sen `init` cada `daw-stop` agardaba
10 s polo contedor. Como `angular` está no mesmo proxecto de Compose ca `web` e `db`,
Angular chega ao PHP en `http://web` (comprobado co *proxy* de `ng serve`). Esa é a
base para un proxecto que combine cliente e servidor: `daw-code-proxecto` abre
`docker/angular/DAW-Proxecto.code-workspace`, con `angular` e `www`, e o contedor de Angular
ve `www` en `~/www` para compilar con Node os recursos de Laravel. Na aula, Apache executa
PHP como `www-data`, e Laravel precisa `storage` e `bootstrap/cache` co grupo `www-data` e
permiso de escritura. Os pasos comprobados están na
[guía do proxecto con cliente e servidor](guia-proxecto-integrado.md).

A imaxe `ghcr.io/miguelfm/dwcc-angular:22` publícaa a CI, coa mesma etiqueta que a
versión anterior con SSH. `daw.ps1` distíngueas polo usuario da imaxe (`node` na
actual). Se a conta ten a anterior, carga a do paquete. Se o paquete tamén ten a
anterior, detense e pide actualizar o paquete. Por iso a imaxe nova vai ao paquete
xunto cos scripts:

```powershell
# Na Debian do profesor, despois de que a CI publique a imaxe nova:
#   docker pull ghcr.io/miguelfm/dwcc-angular:22
#   docker save ghcr.io/miguelfm/dwcc-angular:22 | gzip > dwcc-angular.tar.gz
$paquete = "$HOME\Projects\daw-aula-paquete-20261111-final"
.\wsl\aula\engadir-imaxe.ps1 -PackageDirectory $paquete -Archive C:\ruta\dwcc-angular.tar.gz -Name ghcr.io/miguelfm/dwcc-angular:22
.\wsl\aula\actualizar-paquete.ps1 -PackageDirectory $paquete
```

Despois, `CopiarModelo` e `ActualizarProxecto`. Este último leva
`compose.yaml`, `docker/angular/` e `wsl/vscode-server.sh`; cada usuario repite
**Activar DAW Dev** para ter `daw-code-angular`. O manifesto garda a imaxe en `Images`,
co seu SHA256; `Assert-DawPackage` compróbaa e `CopiarModelo` cópiaa. `daw-stop` e
`daw-logs` inclúen o perfil `angular`: sen el, Compose non para os servizos dun perfil.
`daw-status` e `keep-alive.sh` non o precisan, porque `docker compose ps` lista tamén os
servizos con perfil.

**VS Code Server.** Ao conectar por WSL, VS Code descarga o seu servidor desde Debian.
Antes de abrilo, `daw-code-angular` e `daw-code-proxecto` instálano en
`~/.vscode-server/bin/<commit>`. Buscan `vscode-server-linux-x64.tar.gz` en
`C:\ProgramData\DAW-Aula` e na carpeta Descargas do usuario e, se non está, descárgano
con `curl.exe`. Antes de instalalo comproban o commit e a arquitectura. Se nada funciona,
avisan e deixan que VS Code o intente. O paquete pode levalo: o commit é o do VS Code dos
postos (`code --version`, segunda liña), e se os postos teñen VS Code para todo o equipo,
todos comparten o commit.

```powershell
.\wsl\aula\engadir-vscode-server.ps1 -PackageDirectory $paquete -Commit <commit>
```

O script descárgao (ou usa `-Archive` cun ficheiro xa descargado), comproba no seu
`product.json` que o commit coincide e rexístrao en `Files` do manifesto co SHA256.
`Assert-DawPackage` compróbao e `CopiarModelo` cópiao. Cando se actualiza VS Code nos
postos, hai que engadir o servidor do commit novo; mentres tanto, cada conta descárgao.

**Restos da versión con SSH.** En cada conta quedan os volumes `daw-dev_angular_home`
e `daw-dev_angular_claves`, a imaxe anterior sen etiqueta, `docker/angular/inicio.sh` e
`chave.pub` (a copia non borra ficheiros), e a chave `dwcc_angular` coa súa entrada en
`~\.ssh\config` de Windows. Ningún molesta. Cando o contedor xa estea recreado coa imaxe
nova, liberan espazo `docker volume rm daw-dev_angular_home daw-dev_angular_claves` e
`docker image prune -f`.

Para localizar atrasos na instalación de dependencias, na compilación ou no arranque,
segue as [probas de rendemento de Angular en WSL2 e VirtualBox](rendemento-angular-wsl2-virtualbox.md).

## 5. Uso diario sen administrador

Para o material de clase ou entrega ao alumnado, disponse da [guía rápida de inicio e uso en Markdown para PDF](guia-inicio-alumnado.md).

Abre unha terminal nova despois da primeira instalación:

| Comando | Resultado |
|---|---|
| `daw-start` ou `daw-star` | Só PHP + Apache; sen arrancar as dependencias |
| `daw-start-db` | Web + MariaDB |
| `daw-start-all` | Web + MariaDB + phpMyAdmin |
| `daw-start-angular` | Só o contedor de Angular (DWCC) |
| `daw-code-angular` | Contedor de Angular e VS Code co seu terminal no contedor |
| `daw-code-proxecto` | Web, MariaDB e Angular; VS Code con `angular` e `www` e un terminal en cada contedor |
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
  O instalador preinstala automaticamente no perfil do alumno as extensións `ms-vscode-remote.remote-containers` e `ms-vscode-remote.remote-wsl` e comproba que figuren instaladas. Se falta VS Code ou falla a instalación, informa de erro; para omitir expresamente o IDE usar `-SenVSCode`. O alumno só ten que executar:
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

## 6. Apagado remoto da aula desde o posto do profesor

Ao rematar a xornada, o profesorado pode apagar todos os equipos da aula de forma remota e segura desde o posto `.100`, sen desprazarse posto por posto e garantindo que o seu propio equipo nunca se apague:

```powershell
# Desde PowerShell no equipo 100:
.\wsl\aula\gestionar-aula.ps1 -Action Apagar -Aula 34

# Ou chamando directamente ao script de apagado:
.\wsl\aula\apagar-aula.ps1 -Aula 34
```

### Arquitectura de apagado en dúas fases (tolerante a fallos)

1. **Protección do posto docente:** O equipo `100` (`A34EQ100`) está estritamente excluído dos parámetros por deseño.
2. **Fase 1: WinRM en paralelo (porto 5985):**
   Envía a orde `shutdown.exe /s /t 0 /f /d p:2:4` a todos os postos de alumnos en paralelo mediante `Invoke-Command` con Kerberos. É a vía máis rápida (execútase en 2-3 segundos) para todos os equipos que teñan WinRM habilitado.
3. **Fase 2: Rescate por SMB/RPC directo e PsExec:**
   Para aqueles equipos que non teñan aínda WinRM activo (por exemplo, equipos que estivesen apagados durante o despregamento inicial, como 18, 28, 29 ou 31) ou que presenten anomalías na resolución DNS de nomes de dominio (como o equipo 14):
   - O script detecta automaticamente os equipos pendentes que responden a ping.
   - Aplica o apagado directo por rede sobre a súa dirección IP (`172.21.34.X`) mediante `shutdown.exe /m \\172.21.34.X` e, se é preciso, a través do servizo administrativo de `PsExec64.exe` (porto SMB 445).
4. **Fase 3: Verificación final:**
   Realízase un varrido de rede de comprobación que confirma en pantalla se todos os equipos de alumnos da aula quedaron completamente apagados.

> [!NOTE]
> Non se emprega a orde `Stop-Computer` de PowerShell porque depende do porto DCOM/RPC 135, que o cortalumes de Windows 11 bloquea por defecto con erro `0x800706BA`. O esquema híbrido WinRM (5985) + SMB/IP directa garante un 100% de efectividade en calquera escenario.

## 8. Acendido remoto por rede (Wake-on-LAN)

Para acender os equipos dos alumnos ao inicio da xornada sen desprazarse posto por posto, emprégase a tecnoloxía **Wake-on-LAN (WoL)** mediante a difusión de *Magic Packets* (portos UDP 7 e 9) aos enderezos MAC rexistrados da aula:

```powershell
# Acender todos os equipos da Aula 31:
.\wsl\aula\encender-aula.ps1 -Aula 31

# Acender un posto específico (ex. equipo 01) con monitorización:
.\wsl\aula\encender-aula.ps1 -Aula 31 -Numero 1 -MonitorizarArranque
```

Tamén pode empregarse a interface gráfica de **Veyon Master** seleccionando os equipos e premendo no botón **«Encender»**, grazas ao saneamento e rexistro previo das MACs en `BuiltinDirectory/NetworkObjects` (rexistradas no ficheiro de apoio `wsl/aula/a31-macs.csv`).


## Fontes e comprobacións

- [WSL por usuario: preguntas frecuentes Microsoft](https://learn.microsoft.com/en-us/windows/wsl/faq).
- [Importar distribucións WSL](https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro).
- [Systemd non mantén WSL aberto por si só](https://learn.microsoft.com/en-us/windows/wsl/systemd).
- [PsExec oficial Microsoft](https://learn.microsoft.com/en-us/sysinternals/downloads/psexec).
- [WinRM e autenticación](https://learn.microsoft.com/en-us/windows/win32/winrm/authentication-for-remote-connections).
- [Veyon StartApp executa como usuario conectado](https://github.com/veyon/veyon/blob/main/plugins/desktopservices/DesktopServicesFeaturePlugin.cpp).
- [Permisos do grupo Docker](https://docs.docker.com/engine/install/linux-postinstall/).

As probas reais e as súas limitacións desta entrega rexístranse en `docs/aula-validacion.md`.
