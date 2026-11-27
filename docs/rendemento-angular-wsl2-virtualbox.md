# Probas de rendemento de Angular en WSL2 e VirtualBox

Este procedemento compara Docker Engine en Debian sobre WSL2 (Windows 11) con Docker
Engine nunha máquina virtual Debian 13 de VirtualBox. Permite localizar se a diferenza
está no disco, na descarga, na compilación ou no arranque. O rendemento depende do
equipo, das montaxes e do estado das cachés.

## Preparar unha comparación equivalente

- Usa o mesmo equipo físico se é posible e executa un contorno de cada vez. Anota
  o disco físico, a RAM, as CPU dispoñibles, os límites de Docker e se hai outros
  servizos en marcha. As opcións `memory`, `processors` e `swap` de `.wslconfig`
  afectan á MV de WSL2. [Configuración de WSL](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
- Usa a mesma revisión de `daw-dev` e da aplicación, o mesmo `package-lock.json`, a
  mesma imaxe Docker e a mesma configuración Angular. Se VirtualBox executa Node
  directamente en Debian, rexistra ese caso por separado, xa que tamén cambia o modo
  de execución. Dentro do contedor comproba as versións con `node -v`, `npm -v` e,
  tras instalar as dependencias, `./node_modules/.bin/ng version`.
- Fai as probas con copias de traballo dedicadas. Rexistra por separado a primeira
  execución e polo menos tres repeticións coas cachés quentes. Compara as medianas
  das repeticións. Anota que estaba en caché en cada proba (imaxe, npm e Angular).

## Comprobar onde están os ficheiros

Na aula, a contorna está en `~/.daw` na distribución `linux`. Compose monta
`~/angular` en `/home/node/proxectos` do contedor. Desde Windows podes abrir eses
ficheiros en `\\wsl.localhost\linux\home\ad\angular`. Nunha copia do repositorio,
a montaxe por defecto é `./angular`. Se gardas esa copia en `C:`, a montaxe pode
proceder de `/mnt/c`.

Na terminal da distribución ou da máquina virtual, co contedor arrancado,
define `angular_dir` como `~/angular` na aula ou `./angular` desde a raíz do clon:

```bash
angular_dir=~/angular
findmnt -T "$(realpath "$angular_dir")" -o TARGET,SOURCE,FSTYPE
docker inspect frontend-c --format '{{range .Mounts}}{{println .Type .Source "->" .Destination}}{{end}}'
docker inspect frontend-c --format 'imaxe={{.Image}} cpu={{.HostConfig.NanoCpus}} memoria={{.HostConfig.Memory}}'
```

Comproba a orixe da montaxe `/home/node/proxectos` e calquera montaxe específica
para `node_modules`, e compara o identificador da imaxe nos dous contornos. Para
illar o custo do sistema de ficheiros, compara primeiro
WSL2 co proxecto en disco Linux (`/home/...`) coa MV co proxecto no seu disco Linux.
Se no uso habitual traballades en `/mnt/c` ou `/mnt/d`, repite en WSL2 cunha copia baixo
esa ruta e coa mesma imaxe, os mesmos recursos e o mesmo estado das cachés. En
VirtualBox, anota se o proxecto está nun cartafol compartido co anfitrión. npm e
Angular fan moitas operacións sobre ficheiros pequenos, polo que as montaxes
compartidas poden ter un impacto importante. [Sistemas de ficheiros en WSL](https://learn.microsoft.com/en-us/windows/wsl/filesystems)

## Medir cada fase

### Arranque e conexión

En PowerShell, `Measure-Command { daw-start-frontend | Out-Host }` mide o tempo
que percibe o usuario. A primeira execución pode arrincar WSL, agardar por Docker,
preparar as chaves SSH e cargar desde o paquete da aula ou descargar a imaxe. Cronometra
por separado o tempo desde que seleccionas `dwcc-angular` en VS Code ata que abre
o terminal remoto. A primeira conexión pode instalar o servidor de VS Code no contedor.

Para comparar só o arranque do mesmo servizo, executa o seguinte desde o cartafol que
contén `compose.yaml` (`~/.daw` na aula ou a raíz do repositorio na MV). Prepara o
servizo segundo a [guía de Angular](guia-angular-alumnado.md) en WSL. Na MV, se o
preparas manualmente, pon a chave **pública** do cliente SSH en
`docker/angular/ssh-key.pub`, tal e como require a montaxe de Compose. Parte coa mesma
imaxe xa dispoñible nos dous e, se mediches a carga co paquete da aula, apunta ese tempo
separado da descarga por rede.

```bash
docker compose --profile frontend stop frontend
time docker compose --profile frontend up -d --wait --wait-timeout 300 --no-build --pull never frontend
```

Mide a creación do contedor nunha copia de proba que aínda non o teña e o rearranque
dun contedor existente noutra serie. Se tamén queres medir a obtención da imaxe,
cronometra `docker load -i /ruta/daw-angular.tar.gz` ou
`docker compose --profile frontend pull frontend` antes do arranque. Anota se xa había
capas da imaxe no equipo.
`--wait` indica que o servizo está en marcha. Comproba o SSH ou o HTTP por separado
para medir cando responden. Se distribúes a aplicación compilada mediante o servizo
Apache `backend`, mide ese arranque á parte. O Compose base fai que `backend` agarde por
MariaDB cando se arranca con dependencias. [Referencia de `docker compose up`](https://docs.docker.com/reference/cli/docker/compose/up/)

### Instalación e compilación

No terminal do contedor, entra nunha copia de proba da aplicación con `package-lock.json`.
Se partes dun proxecto novo, `ng new --skip-install` permite medir a xeración do proxecto
por separado. Na primeira pasada crea unha caché npm baleira propia da proba. Reutiliza
a mesma ruta nas repeticións de npm. `npm ci` volve instalar `node_modules` en cada pasada.

```bash
cache_npm_proba=$(mktemp -d)
time npm ci --cache "$cache_npm_proba"
time ./node_modules/.bin/ng build --configuration production
```

Mide a primeira compilación nunha copia sen caché Angular e repite o mesmo comando
para medir a compilación coa caché quente. Podes consultar o seu estado con
`./node_modules/.bin/ng cache info`. Para medir o modo desenvolvemento, executa
`./node_modules/.bin/ng serve --host 0.0.0.0` desde o mesmo proxecto. Cronometra ata a primeira resposta
HTTP en `http://127.0.0.1:4200/` desde o Debian que publica o porto, e mide á parte
canto tarda en recompilar tras gardar o mesmo cambio nun ficheiro. Se usas `--poll`,
anota o intervalo. Podes repetir a comprobación HTTP desde Windows para detectar
diferenzas na publicación ou redirección do porto. [npm ci](https://docs.npmjs.com/cli/commands/npm-ci/),
[caché de Angular](https://angular.dev/cli/cache), [Angular `ng serve`](https://angular.dev/cli/serve)

Se o proxecto ten o seu propio `Dockerfile` que instala dependencias e compila
Angular, executa `docker compose --progress plain build SERVIZO` desde ese proxecto,
substituíndo `SERVIZO` polo nome do servizo,
e compara os tempos de transferencia do contexto, de `npm ci` e da compilación.
O `Dockerfile` de `daw-dev` para `frontend` prepara Node, a CLI e SSH. A aplicación
compílase sobre a montaxe dos proxectos. [Caché de compilación de Docker](https://docs.docker.com/build/cache/optimize/)

## Interpretar e rexistrar o resultado

| Patrón observado | Seguinte comprobación |
| --- | --- |
| `npm ci` e a recompilación melloran ao pasar de `/mnt/c` a `/home` | Revisa as montaxes do código, `node_modules` e a caché de Angular. Para recompilacións, comproba tamén se está activo `--poll`. |
| Só tarda a primeira instalación ou a carga da imaxe | Separa `docker load` de `docker pull` e compara `npm ci` con caché baleira e quente. Revisa o rexistro npm, DNS ou proxy se o atraso aparece nas descargas. |
| A compilación segue lenta en disco Linux e coa caché quente | Durante a compilación, comproba `docker stats frontend-c` e `vmstat 1` no Debian correspondente. Compara CPU, RAM, actividade de *swap* e espera de disco. |
| O contedor arranca axiña, pero tarda VS Code ou o navegador | Separa a instalación remota de VS Code do tempo de `ng serve`. Compara o acceso HTTP desde Debian co acceso desde Windows. Se usas Apache, mide tamén a espera de MariaDB. |

Rexistra os tempos en segundos por fase. Usa unha fila por fase e estado da caché,
e anota o tipo de montaxe, as versións e calquera cambio feito para illar a causa.

| Fase e estado da caché | WSL2 en `/home` | VirtualBox en disco Linux | WSL2 en `/mnt/c` (se procede) | Observacións |
| --- | ---: | ---: | ---: | --- |
| Carga ou descarga da imaxe | | | | |
| Arranque coa creación do contedor | | | | |
| Arranque co contedor existente | | | | |
| Primeira conexión de VS Code | | | | |
| `npm ci` con caché baleira | | | | |
| `npm ci` con caché quente | | | | |
| `ng build` con caché baleira | | | | |
| `ng build` con caché quente | | | | |
| Primeira resposta HTTP con `ng serve` | | | | |
| Recompilación ao gardar | | | | |
