# Despregar DAW Dev nunha aula Windows 11

Este procedemento está pensado para **contas persoais de alumnado**, WSL2 cunha distribución Debian chamada `linux` e Docker Engine.
O profesor administra desde `172.21.34.100`; os equipos de alumnado son `172.21.34.1–35`.
Os exemplos usan o dominio `iesrodolfoucha.es` e nomes `A34EQ01`…`A34EQ35`.
Con `-Classroom 31 -Number 1` as mesmas ferramentas apuntan só ao equipo 01 da aula 31.

Desde o 26/11/2026 o paquete chámase **DAW Dev** e substitúe sen migración a instalación anterior (DAW-Aula, distribución `Debian`, proxecto en `~/proxectos/daw-dev`): véxase [pasar á instalación DAW Dev](#pasar-á-instalación-daw-dev). Os paquetes anteriores non se poden reutilizar.

O despregamento do 18/11/2026 na aula 34 descríbese en [despregamento na aula 34](aula-despregamento-20261118.md), e a intervención na aula 31 do 19/11/2026 descríbese en [despregamento na aula 31](aula-despregamento-20261119-aula31.md), incluíndo o modelo de aula compartida baixo demanda, a coexistencia con alumnos conectados e a resolución de incidencias DNS locais. Se un posto responde por Veyon pero non por WinRM, comprobar tamén que o seu nome DNS resolva á súa IP da aula: os scripts usan o nome e Kerberos.

## Como funciona

1. O profesor activa WinRM desde a rede con PsExec, unha ferramenta asinada de Microsoft.
2. Instala WSL en cada Windows e reinicia os equipos que o precisen.
3. Constrúe **un modelo limpo**, baseado en Debian, con Docker Engine, Compose, o proxecto e as tres imaxes descargadas.
4. Copia o modelo unha vez a cada equipo, en `C:\ProgramData\DAW-Dev`, protexido contra escritura do alumnado.
5. **Activación da contorna:**
   - **En aulas compartidas (configuración aplicada nas Aulas 31 e 34):** A activación realízase baixo demanda polo propio alumno mediante a entrada do menú Inicio (**DAW Dev → Activar DAW Dev**), ou polo profesor durante a clase mediante `.\windows\classroom\manage.ps1 -Action InstallUser -Classroom 31` (ou `-Classroom 34`). Deste xeito, os alumnos alleos ao módulo que utilicen os mesmos equipos non sofren ningún atraso no inicio de sesión, nin consumo de disco no seu perfil, nin ven ningún aviso nin proceso en segundo plano.
   - **En aulas de uso exclusivo:** Só engadindo `-AutoStart` a `CopyPackage` se activa a entrada `Run` en Windows para que cada alumno importe automaticamente a súa distribución no primeiro inicio de sesión.
6. Cada conta ten a distribución `linux`, co usuario **`ad`** e o proxecto en `/home/ad/workspace`. O acceso directo **«DAW - Web»** do Escritorio abre o seu `www`. Desde PowerShell ou CMD, o alumno pode usar os lanzadores `daw-*` sen elevación.

As distribucións WSL son **por conta Windows e por equipo**: instalar a distribución como administrador non a instala
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
executar `windows/classroom/enable-winrm.ps1`; Veyon StartApp executa co usuario conectado e non concede elevación.

## 1. Diagnóstico desde o profesor

Desde a raíz deste repositorio:

```powershell
# Proba pequena, aula 31
.\windows\classroom\manage.ps1 -Action Check -Classroom 31 -Number 1 | Format-Table -AutoSize

# Aula de destino completa: non modifica os equipos
.\windows\classroom\manage.ps1 -Action Check -Classroom 34 | Format-Table -AutoSize
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
.\windows\classroom\manage.ps1 -Action EnableWinRM -Classroom 31 -Number 1
.\windows\classroom\manage.ps1 -Action InstallWSL -Classroom 31 -Number 1
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

Despois do reinicio comproba de novo WinRM. Para acelerar o despregamento na aula completa, engade `-ThrottleLimit` a `manage.ps1`: as accións `InstallWSL`, `CopyPackage` e `UpdateProject` atenden entón ata ese número de equipos á vez, cada un nun *job* de PowerShell (máximo 10). O tempo depende da rede e dos discos:

```powershell
# Preparación concorrente en lotes de 5
.\windows\classroom\manage.ps1 -Action InstallWSL -Classroom 34 -Number @(1..5) -ThrottleLimit 5
.\windows\classroom\manage.ps1 -Action CopyPackage -Classroom 34 -Number @(1..5) -ThrottleLimit 5 -PackageDirectory C:\DAW-Paquete-2026
```

## 3. Construír o modelo unha vez

No profesor, con WSL2 xa instalado, PowerShell normal, Git e acceso a Internet:

```powershell
.\windows\classroom\build-package.ps1 -OutputDirectory C:\DAW-Paquete-2026
```

O directorio de saída debe ser novo. O script crea unha distribución separada `DAW-Model` e nunca usa a
Debian persoal do profesor. Descarga a base oficial indicada no catálogo Microsoft WSL e comproba SHA256.
Instala Docker desde o repositorio oficial e precarga PHP/Apache, MariaDB e phpMyAdmin.
O modelo exportado non contén contedores nin volumes de BD. Conserva a distribución modelo para inspección.

O código inicial procede de `git archive HEAD`, coa configuración e as guías versionadas
da copia de traballo desde a que se executa o script. Non copia `.env` persoais, traballos non versionados de `www`, claves nin o perfil
do profesor. O usuario Linux é `ad`, UID/GID 1000, con contrasinal bloqueado e acceso ao grupo Docker.
Para administración Linux posterior, o propietario da distribución pode usar `wsl -d linux -u root`.
Isto non lle concede permisos de administrador de Windows.

O modelo usa o Compose do proxecto, incluída a imaxe pública `ghcr.io/miguelfm/dwcs-php:8.6-ad`,
co proxecto en `/home/ad/workspace` e o volume `daw-dev_db_data` para as bases de datos de cada conta.
O ficheiro `/etc/daw-dev-model` identifica o modelo: a activación só substitúe unha distribución que o teña.
Configura `WEB_PORT=127.0.0.1:80`, `PMA_PORT=127.0.0.1:8081` e `DB_PORT=127.0.0.1:3306`.
Non se abre o socket Docker pola rede. VS Code debe conectarse a WSL para usar Xdebug.

`linux.tar.gz` comprime a imaxe para reducir a copia pola LAN.
`manifest.json` rexistra o SHA256 da imaxe, a base oficial, a data e o commit do proxecto.
O subdirectorio `build` é material de construción e non se copia aos alumnos.
Se a construción falla, conserva o log e inspecciona `DAW-Model`: non reutilices unha distribución persoal
nin borres ningunha distribución con traballo. Para outro modelo, usa `-Distribution DAW-Model-v2` e outro
directorio de saída. `-BaseImagePath` permite reutilizar a descarga Debian, verificándoa contra o catálogo actual.

Se falla só a descarga das imaxes, `-Resume` continúa o mesmo modelo a partir do checkpoint verificado,
sen reinstalar Debian. Tamén podes aproveitar imaxes xa descargadas nunha Debian do profesor:

```powershell
wsl -d Debian --exec docker image save --output /mnt/c/DAW-images.tar ghcr.io/miguelfm/dwcs-php:8.6-ad mariadb:lts phpmyadmin:latest
.\windows\classroom\build-package.ps1 -OutputDirectory C:\DAW-Paquete-2026 -Resume -DockerImagesArchive C:\DAW-images.tar
```

Só se copian imaxes; os volumes, contedores e datos do profesor non forman parte de `docker image save`.

## 4. Copiar aos equipos e activar por usuario

### Instalar en toda a aula: `deploy.ps1`

`deploy.ps1` prepara o paquete e instálao en todos os equipos dunha aula. Non activa as contas:
cada alumno activa DAW Dev na súa conta, no menú Inicio (**DAW Dev → Activar DAW Dev**) ou con
`daw-activate` se xa ten as ordes `daw-*`. O profesor precisa Internet, WSL2 e Git.

```powershell
# Primeiro nun posto; despois, a aula completa
.\windows\classroom\deploy.ps1 -Classroom 34 -Number 16 -PackageDirectory C:\DAW-Paquete-2026
.\windows\classroom\deploy.ps1 -Classroom 34 -PackageDirectory C:\DAW-Paquete-2026

# Postos sen WinRM ou sen WSL: preparalos e reiniciar os que non teñen ninguén con sesión
.\windows\classroom\deploy.ps1 -Classroom 31 -Number (1..30) -PackageDirectory C:\DAW-Paquete-2026 -PrepareWindows -RestartComputers

# Cando os alumnos activaron DAW Dev e seguen conectados
.\windows\classroom\deploy.ps1 -Classroom 34 -PackageDirectory C:\DAW-Paquete-2026 -Verify -SkipCopy
```

1. Se o paquete non existe, constrúeo con `build-package.ps1` (tarda un bo anaco); se a construción
   quedou a medias, continúaa. Despois valídao.
2. Diagnostica os postos (`Check`) e continúa só cos que responden por WinRM. Con
   `-PrepareWindows`:
   - activa WinRM con PsExec (`EnableWinRM`) nos que non responden;
   - consulta en cada posto a virtualización, as características de Windows, WSL, se hai un
     reinicio pendente e se hai sesións abertas;
   - instala WSL (`InstallWSL`) só nos que o precisan;
   - con `-RestartComputers`, reinicia os que o necesitan e non teñen ninguén con sesión
     iniciada, agarda a que volvan responder e compróbaos de novo. Sen el, ou cunha sesión
     aberta, márcaos como `Reiniciar`: hai que reinicialos antes de activar DAW Dev.
3. Completa o paquete co que lle falte para traballar sen Internet:
   - o VS Code Server de cada commit de VS Code instalado nos postos que responden, lido por
     WinRM (`add-vscode-server.ps1`);
   - as extensións de VS Code para PHP do Dev Container (`add-vscode-extensions.ps1`);
   - as imaxes da documentación, da última release de daw-doc (`add-doc-images.ps1`);
   - a imaxe de Angular, descargada de ghcr.io co Docker da distribución modelo do paquete.

   Só descarga o que falta. Se algo non se pode engadir, avisa e continúa. `-SkipPrepare` usa o
   paquete tal como está.
4. `CopyPackage` neles, de 5 en 5 (`-ThrottleLimit`), co SHA256 de cada ficheiro comprobado no posto.
5. Con `-Verify`, executa `Verify` na conta conectada de cada posto: comproba o paquete da
   distribución, Docker, o proxecto, os lanzadores, `daw-start-db` con `http://localhost/`,
   `daw-start-doc` cos portos 8080, 5042 e 8088, e VS Code Server. Usa os lanzadores da conta e,
   se a contorna non estaba en marcha, párase ao rematar.

Amosa unha táboa por posto (`Windows`: `OK`, `Reiniciar` ou `Erro`; `Package` e `Verify`: `OK`,
`Erro`, `Sen alumno` ou `Sen activar`) e
gárdaa en CSV en `%LOCALAPPDATA%\DAW-Dev\tools\deploy-<aula>-<data>.csv`. Ao final indica a orde
para repetir só os postos con erro. Non activa contas nin usa `-Reinstall`, e só reinicia con
`-RestartComputers` os postos sen ninguén con sesión iniciada.
Os postos apagados quedan sen resposta: acéndeos con `power-on.ps1` e repite con `-Number`.

### Instalar no propio equipo: `install-package.ps1`

Para probar DAW Dev nun só equipo sen WinRM, por exemplo no do profesor, que os scripts da aula
non tocan, executa en PowerShell **como administrador**:

```powershell
.\windows\classroom\install-package.ps1 -PackageDirectory C:\DAW-Paquete-2026
```

Fai os mesmos pasos ca `CopyPackage`: retira o paquete anterior, copia o novo en
`C:\ProgramData\DAW-Dev` co SHA256 comprobado e a escritura só para SYSTEM e Administradores, e
deixa os ficheiros do proxecto e **Activar DAW Dev** no menú Inicio. Despois, nunha sesión sen
elevar, activa DAW Dev como o alumnado e compróbao con:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\DAW-Dev\verify-user.ps1
```

Nese equipo, a distribución nova chámase `linux`: unha Debian persoal consérvase. Os portos 80,
8080, 8081, 3306, 5042 e 8088 deben estar libres en Windows.

### Accións por separado

```powershell
.\windows\classroom\manage.ps1 -Action CopyPackage -Classroom 31 -Number 1 -PackageDirectory C:\DAW-Paquete-2026
```

Verifica o SHA256 antes e despois da copia. A carpeta local só permite escritura a SYSTEM e Administradores;
os usuarios teñen lectura e execución. Non depende de compartir credenciais nin dun servidor accesible
no momento de iniciar sesión.

Antes de copiar retira do posto o paquete anterior, `C:\ProgramData\DAW-Aula`, e o seu autoarranque
(`DAWAula` en `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`), se non hai unha instalación en curso.
Por defecto retira tamén a entrada `DAWDev` dese mesmo sitio, conservando a activación baixo demanda. Para unha aula exclusiva, `-AutoStart` permite expresamente executar o instalador na conta que inicia sesión. Non se modifica a política permanente de execución de PowerShell. A copia comproba tamén os hashes dos scripts; para cambiar só os scripts dun paquete, usar `update-package.ps1`.

Se xa está conectado o alumno, non necesita pechar sesión:

```powershell
.\windows\classroom\manage.ps1 -Action InstallUser -Classroom 31 -Number 1
.\windows\classroom\manage.ps1 -Action Status -Classroom 31 -Number 1 | Format-List
```

A tarefa usa `LogonType Interactive` e `RunLevel Limited`: non pide contrasinais nin usa SYSTEM.
O comando espera o resultado do GUID e SID da solicitude actual, con timeout e comprobación de erros. **Status** mostra o último informe por perfil, coa súa data e RequestId; non confundir un rexistro histórico cunha instalación nova.
Os rexistros por usuario están en `%LOCALAPPDATA%\DAW-Dev\install.log` e `install-state.json`.
Para executalo manualmente, na conta do alumno:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\DAW-Dev\install-user.ps1
```

### Xestión en aulas compartidas con outros módulos (Activación baixo demanda)

Nas aulas que se comparten con outros ciclos ou materias onde o resto do alumnado non debe ver ningunha información nin sufrir atrasos no inicio de sesión nin consumo de disco no seu perfil:
- **Sen auto-inicio en `HKLM`:** Retírase a entrada `DAWDev` de `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`. Deste xeito, os alumnos alleos traballan sen que Windows execute ningún proceso nin xere accesos directos.
- **Activación puntual na clase de DAW:** Cando os alumnos do módulo están cos equipos iniciados, o profesor activa a contorna desde o seu equipo cun só comando:
  ```powershell
  .\windows\classroom\manage.ps1 -Action InstallUser -Classroom 34
  ```
- A importación execútase de xeito limpo, interactivo e unicamente no perfil do alumno de DAW que estea presente nese posto.

Repetir o instalador co mesmo paquete conserva a distribución e o traballo. Se a conta ten a distribución
doutro paquete, detense: `-Reinstall` (en `InstallUser`, ou `daw-activate -Reinstall` no alumno) elimínaa
con todo o seu contido e importa a nova. Como coa instalación anterior, copia antes a raíz web en
`Documentos\DAW-Dev-www-<data>-linux` e despois cópiaa no `www` novo. Para levar cambios aos proxectos sen reinstalar está a acción seguinte.

### Actualizar os ficheiros dos proxectos xa importados

`UpdateProject` copia `windows/classroom/overlay` en `/home/ad/workspace` da
distribución do alumno conectado, sen volver copiar o modelo de 1,4 GB. O contido actual e as
regras da copia están no [README dos ficheiros do proxecto](../windows/classroom/README.md).

```powershell
# Primeiro nun posto; despois no resto, de 5 en 5
.\windows\classroom\manage.ps1 -Action UpdateProject -Classroom 34 -Number 16 | Format-List
.\windows\classroom\manage.ps1 -Action UpdateProject -Classroom 34 -Number @(1..35) -ThrottleLimit 5
```

Para cada posto:

1. No profesor, prepara unha vez un directorio temporal cos ficheiros, `update-project.ps1`,
   o módulo e `project.json`, cos SHA256 e unha revisión.
2. Por WinRM, crea `C:\ProgramData\DAW-Dev\project` coa mesma ACL ca o paquete (escritura só para
   SYSTEM e Administradores) e baleira o anterior, se non hai unha instalación en curso.
3. Copia o directorio por SMB, restablece as ACL e volve comprobar os SHA256 no posto.
4. Executa `update-project.ps1` cunha tarefa temporal co token do alumno conectado, como
   `InstallUser`, e agarda polo `project-state.json` desa solicitude.

No alumno, o script comproba que a distribución ten o marcador do modelo DAW Dev e copia
os ficheiros como `ad`. O resultado de cada posto leva en `Data` a revisión e as listas `Created`,
`Replaced`, `Unchanged` e `Kept`, e `Backup` se gardou copias. Os rexistros por usuario están en
`%LOCALAPPDATA%\DAW-Dev\project.log` e `project-state.json`.

- Necesita unha única sesión de alumno no posto. Sen sesión, ou se a conta aínda non ten
  a distribución `linux`, o posto devolve `Success=False` co motivo; repetir só eses postos con `-Number`.
- O módulo vai na propia copia, polo que non depende dos scripts que deixou `CopyPackage`.
- Por defecto non reinicia nada: os cambios aplícanse no seguinte `daw-start`. `-Restart` recrea
  o contedor web se está en marcha; pecha unha sesión aberta de Dev Containers e as sesións de PHP.
- Repetila coa mesma revisión non cambia nada. Unha conta que active DAW Dev despois recibe
  os ficheiros da copia que deixou `CopyPackage`; os dun `UpdateProject` posterior, ao repetilo.

Para distribuír cambios nos lanzadores de Windows ou no acceso directo do Escritorio,
actualiza o paquete con `update-package.ps1`, cópiao aos postos e volve executar
**Activar DAW Dev** na conta do alumno. `UpdateProject` aplica os ficheiros da
distribución. A activación instala os lanzadores e actualiza o acceso directo.

### Pasar á instalación DAW Dev

A instalación DAW Dev (26/11/2026) substitúe a anterior sen migrar nada:

| | Antes | DAW Dev |
|---|---|---|
| Paquete no posto | `C:\ProgramData\DAW-Aula` | `C:\ProgramData\DAW-Dev` |
| Estado da conta | `%LOCALAPPDATA%\DAW-Aula` | `%LOCALAPPDATA%\DAW-Dev` |
| Distribución WSL | `Debian` | `linux` |
| Proxecto | `~/proxectos/daw-dev` (e `~/www`) | `~/workspace` |
| Datos das tarefas | `datos/`, no contedor `/home/ad/datos` | `data/`, no contedor `/home/ad/data` |
| Raíz web no contedor | `/var/www/html` e `/home/ad/html` | `/var/www/html` |
| Acceso directo | «DAW - Proxectos (www)» | «DAW - Web» |

O contedor xa non imita a MV de DWCS: os enunciados usan `/home/ad/data`.

1. **O alumnado garda o que non sexa código web** (`datos/`, `angular/` e o que precise das bases
   de datos) fóra da distribución, por exemplo en OneDrive ou nun repositorio Git. A reinstalación
   elimina a distribución anterior con todo o seu contido. Só a raíz web (`www`, ou a que indique
   `WWW_DIR` no `.env`) se copia automaticamente, como se explica no punto 4.
2. Indica a `deploy.ps1` un directorio novo para o paquete: constrúeo e complétao (os paquetes de
   DAW-Aula non valen). Tamén se pode facer a man con `build-package.ps1`, `add-vscode-server.ps1`,
   `add-doc-images.ps1` e `add-package-image.ps1`, como nas seccións seguintes.
3. `deploy.ps1` (ou `CopyPackage`) en cada posto. Retira o paquete anterior e o seu
   autoarranque, e deixa **Activar DAW Dev** no menú Inicio, que agora executa `activate.ps1`. No
   lugar do paquete anterior queda só `activar-dawdev.ps1`, protexido contra escritura, para que o
   `daw-activate` das contas anteriores leve á activación nova.
4. Cada alumno activa DAW Dev na súa conta: **Activar DAW Dev** no menú Inicio ou `daw-activate`
   (tamén o das contas anteriores). O profesor pode usar `InstallUser` co alumno conectado. A primeira vez retira a instalación anterior da conta: a distribución `Debian`
   (só se ten o marcador `/etc/daw-aula-modelo` do modelo anterior; unha Debian persoal
   consérvase), `%LOCALAPPDATA%\DAW-Aula`, `%LOCALAPPDATA%\daw-dev-launcher` e o acceso directo
   vello. Antes de eliminar a distribución copia o contido da súa raíz web en
   `Documentos\DAW-Dev-www-<data>-Debian`. Despois importa `linux`, copia ese contido en
   `~/workspace/www` (substitúe os ficheiros co mesmo nome) e instala os lanzadores novos. A copia
   de Documentos consérvase. Se a activación falla despois de copiar, a seguinte restaura a copia
   pendente (`%LOCALAPPDATA%\DAW-Dev\web-restore.txt`).

As contas que non se activen conservan a súa Debian anterior ata que o fagan, e as súas ordes
`daw-*` seguen usándoa; `daw-activate` ou **Activar DAW Dev** pásaas á instalación nova. Proba primeiro nun posto
cunha conta nova e outra coa instalación anterior, e comproba `daw-start`, `daw-code -Container`,
o acceso directo e que a distribución `Debian` desapareceu.

#### PHP 8.6

O modelo leva a imaxe `ghcr.io/miguelfm/dwcs-php:8.6-ad`, con PHP 8.6, Xdebug e `mbstring`.

<details>
<summary>Publicación histórica de PHP 8.6 (21/11/2026)</summary>

O 21/11/2026 publicouse a imaxe `linux/amd64` con PHP `8.6.0` e Xdebug `3.6.0alpha1`
como `ghcr.io/miguelfm/dwcs-php:8.6` e `ghcr.io/miguelfm/daw-dev:8.6`. Ambas as
etiquetas apuntaban a `sha256:d65fabc7719ed91cd5d232c561cc87e91e717f24edf0b68f4d20fc95981fc64a`.
Confirmouse a descarga pública. Nunha proba local en Linux coa configuración Apache
da aula, Xdebug conectou con `XDEBUG_TRIGGER=1`. Nesa data quedaba pendente a primeira proba nun posto Windows/WSL2 da aula.
[Execución de publicación](https://github.com/miguelfm/daw-dev/actions/runs/44934087884).

Esa imaxe non tiña `mbstring`: a imaxe oficial de PHP 8.6 xa non a compila, como
facía a 8.5, e `mb_strlen()`, que usa DWCS desde a U4, daba un erro fatal. O mesmo
día publicouse de novo con `mbstring` nas dúas etiquetas, que pasaron a apuntar a
`sha256:bb7762ad0e307f1e64bb0c6c6f213d97eaa47311e6e16a29a7aff13d82caa1d6`
([execución](https://github.com/miguelfm/daw-dev/actions/runs/44939197023)). Ten os
mesmos 45 módulos de PHP ca a 8.5.

</details>

### Activación manual desde o menú Inicio

`CopyPackage` deixa tamén en cada equipo os ficheiros do proxecto
(`C:\ProgramData\DAW-Dev\project`, cos seus SHA256) e a entrada **DAW Dev → Activar DAW
Dev** no menú Inicio común. Calquera usuario a executa cando a necesita, sen administración:
`activate.ps1` lanza `install-user.ps1` na súa conta e despois
`update-project.ps1`, nunha xanela que amosa o progreso. Non se engade nada ao inicio
de sesión, e os usuarios doutros módulos só ven a entrada no menú.

Nunha conta cos lanzadores instalados, `daw-activate` executa o mesmo
activador desde PowerShell ou CMD, e `daw-activate -Reinstall` substitúe a distribución
doutro paquete. A copia de `%LOCALAPPDATA%\DAW-Dev\launcher` leva tamén o instalador, e
calquera orde `daw-*` repón os lanzadores que falten e o PATH. Antes de instalar os
lanzadores, tamén podes chamar ao script do paquete desde PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:ProgramData\DAW-Dev\activate.ps1"
```

O activador usa a distribución `linux` por defecto. Para unha proba illada,
pódese indicar `-Distribution` no script. `daw-start` arranca Apache e PHP
despois da activación.

- Repetir a activación co mesmo paquete é seguro, e é a forma de que unha conta xa activada
  reciba as ordes `daw-*` e os ficheiros do proxecto novos.
- O instalador rexeita as contas con elevación, como o Administrador integrado (`-500`);
  comprobado no posto A34EQ01. Unha conta de dominio con UAC actívase sen elevar.
- `InstallUser` e `UpdateProject` seguen dispoñibles para facelo desde o
  profesor co alumno conectado.

### Imaxes Docker adicionais: Angular (DWCC)

O servizo `angular` de `compose.yaml` (perfil `angular`) é o contedor DWCC-Angular: Node.js
26, Angular CLI 22 e SSH en `127.0.0.1:2222`, cos proxectos en
`~/workspace/angular`. O seu uso está na
[guía de Angular para o alumnado](guia-angular-alumnado.md). A imaxe
`ghcr.io/miguelfm/dwcc-angular:22` publícaa a CI; o paquete leva unha copia para cargala
sen Internet:

```powershell
# No Linux do profesor: docker save ghcr.io/miguelfm/dwcc-angular:22 | gzip > dwcc-angular.tar.gz
.\windows\classroom\add-package-image.ps1 -PackageDirectory C:\DAW-Paquete-2026 -Archive C:\ruta\dwcc-angular.tar.gz -Name ghcr.io/miguelfm/dwcc-angular:22
```

O manifesto garda a imaxe en `Images`, co seu SHA256; `Assert-DawPackage` compróbaa e
`CopyPackage` cópiaa. `daw-start-angular` cárgaa con `docker load` a primeira vez en cada
conta, se aínda non a ten. `daw-stop` e `daw-logs` inclúen o perfil `angular`: sen el,
Compose non para os servizos dun perfil.

### VS Code Server sen Internet

Ao abrir o proxecto en WSL ou no Dev Container, VS Code necesita o VS Code Server do seu
mesmo commit. Se o descarga, a rede da aula pode esgotar o tempo («Retrying to download VS
Code Server»). Por iso o paquete leva o servidor de cada commit de VS Code que haxa nos postos.
`deploy.ps1` le eses commits nos postos e engade os que falten; a man:

1. No profesor, co commit do VS Code dos postos: a segunda liña de `code --version` nun posto,
   ou o que amosa `-Action Status` en `CodeServer` (`Missing <commit>`). O VS Code do profesor
   pode ser máis novo, así que non se usa o seu:

   ```powershell
   .\windows\classroom\add-vscode-server.ps1 -PackageDirectory C:\DAW-Paquete-2026 -Commit <commit>
   ```

   Descarga `https://update.code.visualstudio.com/commit:<commit>/server-linux-x64/stable`, cópiao
   ao paquete como `vscode-server-<commit>.tar.gz` e rexístrao en `manifest.json` (`CodeServers`)
   co seu SHA256. Con `-Archive` usa un ficheiro xa descargado. Pódense ter varios commits.
2. `CopyPackage` cópiao aos postos e o posto comproba o SHA256. Os ficheiros que xa están no
   posto co mesmo tamaño e data non se volven copiar.
3. A activación instala o servidor do commit do VS Code do posto en `~/.vscode-server` da
   distribución (Remote - WSL) e copia o arquivo en
   `%TEMP%\vsch\serverCache\<commit>\vscode-server-linux-x64.tar.gz` (Dev Containers).
   `daw-code` repíteo antes de abrir VS Code, polo que tamén serve para as contas xa activadas.

Se o paquete non ten o commit do VS Code do posto, a activación e `daw-code` avisan e VS Code
descarga o servidor de Internet. `-Action Status` amosa en `CodeServer` o resultado de cada
conta (`Installed`, `Ready` ou `Missing` co commit).

Os postos teñen unha directiva que impide actualizar VS Code, así que o commit só cambia cando
a administración actualiza VS Code nos postos. Daquela, executa de novo `add-vscode-server.ps1`
co commit novo e `CopyPackage`. As contas reciben o servidor no seguinte `daw-code`.

#### Extensións de PHP sen Internet

As extensións do Dev Container (`xdebug.php-debug` e Intelephense) descárganse do Marketplace
ao abrir o contedor e, sen máis, pérdense cando o contedor se volve crear. Na aula:

- o paquete leva os seus `.vsix` (`add-vscode-extensions.ps1`, ou `deploy.ps1` se faltan);
- a activación instálaos sen Internet, co VS Code Server do paquete, en `~/.vscode-server` da
  distribución (Remote - WSL) e no volume `daw-vscode-extensions`;
- `compose.override.yaml` monta ese volume en `/home/ad/.vscode-server/extensions` do contedor
  web, así que o Dev Container as atopa xa instaladas e consérvaas aínda que se volva crear.

`-Verify` comproba que están nos dous sitios. A imaxe web crea ese directorio a nome de `ad`;
a activación axusta tamén o propietario do volume. Cunha imaxe anterior ao 26-11-2026, Docker
crea `/home/ad/.vscode-server` como `root` para montar o volume, e VS Code non podería instalar
o servidor (`mkdir: cannot create directory '/home/ad/.vscode-server/bin': Permission denied`).
Por iso `compose.override.yaml` ten un paso `post_start` que deixa ese directorio a nome de
`ad` cada vez que arranca o contedor. Compose remátao antes de que `daw-start` ou Dev Containers
usen o contedor, sexa cal sexa a imaxe.

### Contrasinais

MariaDB usa `abc123..` para `dwcs` e `root`. As contas de Linux non teñen contrasinal:
`ad` usa `sudo` sen contrasinal no contedor, e na distribución `linux` está bloqueada e sen
`sudo`. A guía do alumnado recólleo.

### Documentación sen conexión (daw-doc)

O perfil `doc` de `compose.yaml` arranca o manual de PHP (<http://localhost:8080/>),
a referencia de HTML, HTTP e CSS de MDN (<http://localhost:5042/>) e a documentación de Laravel 13.x
(<http://localhost:8088/>), coas imaxes do proxecto
[daw-doc](https://github.com/miguelfm/daw-doc). Serven para os exames e as clases sen
Internet. As imaxes publícanse como arquivos dunha
[release de daw-doc](https://github.com/miguelfm/daw-doc/releases), e van ao paquete co seu SHA256:

```powershell
$paquete = 'C:\DAW-Paquete-2026'
.\windows\classroom\add-doc-images.ps1 -PackageDirectory $paquete
.\windows\classroom\deploy.ps1 -Classroom 34 -Number 16 -PackageDirectory $paquete
```

`add-doc-images.ps1` descarga sen login a última release (ou a de `-Tag`), comproba o SHA256 de
cada arquivo con `SHA256SUMS` e que garda a imaxe que carga `daw.ps1`, e rexístraa no paquete. Sen
Internet no equipo do profesor, `add-package-image.ps1` rexistra os arquivos copiados doutro xeito.

`UpdateProject` leva o `compose.yaml` co perfil `doc`, e **Activar DAW Dev**, a
orde `daw-start-doc`. A primeira vez en cada conta, `daw-start-doc` carga as imaxes que
falten desde `C:\ProgramData\DAW-Dev` con `docker load`; despois arranca nuns
segundos. Como os outros servizos, os portos só escoitan en `127.0.0.1`, e
`daw-stop-doc` para só a documentación. Os tres arquivos ocupan arredor de 125 MB: cada un leva
a súa copia da capa de nginx.

Para renovar a documentación, xera os arquivos en `daw-doc` con `scripts/empaquetar.sh`, publícaos
nunha release nova (véxase o README de daw-doc) e rexístraos no paquete con `add-doc-images.ps1`. Nas contas que xa
teñen esas etiquetas en Docker, verifica o paquete e carga os arquivos novos
con `docker load -i` antes de executar `daw-start-doc`. O lanzador reutiliza as
imaxes locais cando xa están cargadas.

#### Pendentes de documentación sen conexión

- [x] Empaquetar en inglés a documentación de Laravel 13.x e comprobar a lingua do menú e
  das páxinas na imaxe que se distribúa á aula. Desde o 26/11/2026 os contidos, o menú, a
  portada e a busca do manual de PHP e de Laravel están en inglés.
- [x] Atopar un xeito reproducible de gardar en caché as páxinas das referencias de HTTP e HTML
  en DevDocs e deixalas dispoñibles no despregamento da aula. Desde o 26/11/2026 a imaxe
  `daw-doc-devdocs` é un sitio estático co contido de MDN en inglés que prepara DevDocs, sen a
  súa aplicación, que só funciona desde devdocs.io. Leva as páxinas de HTML, HTTP e CSS e a
  busca Pagefind, e comprobouse cun navegador sen acceso a Internet. Para engadir outras referencias,
  `DEVDOCS_LANGS` en daw-doc.

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
| `daw-stop` | Para os servizos e conserva a BD e o código |
| `daw-status` | Lista tamén contedores parados |
| `daw-code` | Abre o proxecto en VS Code listo para Dev Containers |
| `daw-web-root -Open` | Abre a raíz web no Explorador. `daw-web-root` amosa as rutas de Windows e de WSL. |
| `daw-wsl-shell` | Abre a distribución `linux` no proxecto, tamén con Docker parado |
| `daw-web-shell` | Abre a terminal do contedor de Apache e PHP |
| `daw-help` | Axuda dos comandos Windows |

Accede a `http://localhost`, `http://localhost/index.php` e `http://localhost:8081`.
phpMyAdmin e a comprobación de BD requiren `daw-start-all`. As credenciais de desenvolvemento son as do
`.env.example`; os portos quedan limitados ao equipo local.

### Acceso directo aos ficheiros web e contorna Linux

`ad` é a conta do modelo WSL e da terminal do contedor PHP. As rutas de traballo son:
- **Desde o Explorador de ficheiros:** `\\wsl.localhost\linux\home\ad\workspace\www`. Tamén podes usar o acceso directo **«DAW - Web»** ou `daw-web-root -Open`. Os datos das tarefas están en `\\wsl.localhost\linux\home\ad\workspace\data`.
- **Con VS Code e Dev Containers:**
  O instalador preinstala automaticamente no perfil do alumno as extensións `ms-vscode-remote.remote-containers` e `ms-vscode-remote.remote-wsl` e comproba que figuren instaladas. Se falta VS Code ou falla a instalación, informa de erro; para omitir expresamente o IDE usar `-SkipVSCode`. O alumno só ten que executar:
  ```powershell
  daw-code
  ```
  Ao abrirse o proxecto en VS Code, aparecerá unha mensaxe emerxente para reabrir no contedor (ou premendo `F1` e seleccionando **«Dev Containers: Reopen in Container»**). A imaxe precompilada inclúe PHP 8.6, Composer, Xdebug e o cliente MariaDB.
- **Desde a terminal de Linux:** `daw-wsl-shell` abre `~/workspace` co usuario `ad`.

Os lanzadores Windows arrancan WSL se está parado, agardan por Docker e manteñen unha sesión oculta
mentres existan contedores do proxecto en marcha. `daw-stop` deixa rematar esa sesión en ata 20 segundos.
Dentro da distribución tamén hai comandos de terminal; conserva aberta esa terminal mentres traballas.
O uso diario non necesita UAC, `sudo`, contrasinal Linux nin administrador de Windows. O grupo Docker dá
control administrativo **dentro desta distribución**, como explica a documentación de Docker.

O alumno debe parar a contorna antes de pechar sesión. Evita deixar dous usuarios executando servizos
simultaneamente no mesmo Windows: os portos locais son compartidos e poderían entrar en conflito.
Non se configura autoinicio dos contedores ao iniciar Windows nin se usa `down -v` ou `prune` nos scripts
de usuario. Só a activación elimina distribucións: a do modelo anterior e, con `-Reinstall`, a propia.

## 6. Apagado remoto da aula desde o posto do profesor

Ao rematar a xornada, o profesorado pode apagar todos os equipos da aula de forma remota e segura desde o posto `.100`, sen desprazarse posto por posto e garantindo que o seu propio equipo nunca se apague:

```powershell
# Desde PowerShell no equipo 100:
.\windows\classroom\manage.ps1 -Action PowerOff -Classroom 34

# Ou chamando directamente ao script de apagado:
.\windows\classroom\power-off.ps1 -Classroom 34
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
.\windows\classroom\power-on.ps1 -Classroom 31

# Acender un posto específico (ex. equipo 01) con monitorización:
.\windows\classroom\power-on.ps1 -Classroom 31 -Number 1 -Monitor
```

Tamén pode empregarse a interface gráfica de **Veyon Master** seleccionando os equipos e premendo no botón **«Encender»**, grazas ao saneamento e rexistro previo das MACs en `BuiltinDirectory/NetworkObjects` (rexistradas no ficheiro de apoio `windows/classroom/a31-macs.csv`).


## Fontes e comprobacións

- [WSL por usuario: preguntas frecuentes Microsoft](https://learn.microsoft.com/en-us/windows/wsl/faq).
- [Importar distribucións WSL](https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro).
- [Systemd non mantén WSL aberto por si só](https://learn.microsoft.com/en-us/windows/wsl/systemd).
- [PsExec oficial Microsoft](https://learn.microsoft.com/en-us/sysinternals/downloads/psexec).
- [WinRM e autenticación](https://learn.microsoft.com/en-us/windows/win32/winrm/authentication-for-remote-connections).
- [Veyon StartApp executa como usuario conectado](https://github.com/veyon/veyon/blob/main/plugins/desktopservices/DesktopServicesFeaturePlugin.cpp).
- [Permisos do grupo Docker](https://docs.docker.com/engine/install/linux-postinstall/).

As probas reais e as súas limitacións desta entrega rexístranse en `docs/aula-validacion.md`.
