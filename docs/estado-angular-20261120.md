# Estado do traballo de Angular e do proxecto integrado (20/11/2026)

Resumo para continuar noutro equipo: que se fixo, que decisións están
tomadas, en que estado queda o paquete da aula e que falta.

## Onde está o traballo

- Rama `feat/angular-wsl`, no [PR #3](https://github.com/miguelfm/daw-dev/pull/3)
  contra `main`. O PR #2 pechouse só porque se renomeou a súa rama (GitHub
  pecha un PR ao renomear a rama da que sae).
- Para seguir noutro equipo:

  ```bash
  git fetch origin
  git switch feat/angular-wsl
  ```

## Que se fixo

- **Contedor `angular` sen SSH.** Colle as decisións do kit DWCC-Angular
  (`angular-container`, `Angular-Aula.cmd`), que queda como referencia sen
  manter:
  - usuario `node`, `sleep infinity` con `init: true`;
  - VS Code en Debian por WSL, co terminal dentro do contedor.
- **Ordes novas:**
  - `daw-code-angular` abre `docker/angular/DWCC-Angular.code-workspace`,
    co cartafol `angular`.
  - `daw-code-proxecto` arranca `db`, `web` e `angular` e abre
    `DAW-Proxecto.code-workspace`, con `angular` e `www` e un terminal en
    cada contedor.
- **Proxecto con cliente e servidor:**
  - o contedor de Angular ve `www` en `~/www` e publica o porto 5173 (Vite);
  - desde Angular, o PHP é `http://web`;
  - a guía é [guia-proxecto-integrado.md](guia-proxecto-integrado.md), con
    Laravel comprobado.
- **VS Code Server sen descarga en Debian:**
  - `wsl/vscode-server.sh` instala o do commit do VS Code de Windows desde un
    `.tar.gz` que atopa no paquete ou en Descargas, ou que descarga con
    `curl.exe`;
  - `wsl/aula/engadir-vscode-server.ps1` engádeo ao paquete (`Files` do
    manifesto), e `CopiarModelo` cópiao aos postos.
- **Conta da aula como na VM de DWCS:**
  - `ad`, co contrasinal `abc123..`, só se a conta aínda non ten un propio;
  - `ad` no grupo `sudo`;
  - ligazón `~/angular` e acceso directo «DAW - Proxectos (angular)».
- **Correccións:**
  - `encender-aula.ps1` non se analizaba en PowerShell 5.1;
  - `Add-DawPackageImage` garda sempre a imaxe de Angular como
    `dwcc-angular.tar.gz`, o nome que busca `daw.ps1`.

## Decisións tomadas

| Decisión | Detalle |
|---|---|
| Etiqueta da imaxe | `ghcr.io/miguelfm/dwcc-angular:22`, a mesma que a versión con SSH. `daw.ps1` distíngueas polo usuario da imaxe (`node`) |
| Nomes | Sen «v2» en etiquetas, ficheiros nin ramas |
| SSH | Non se engade aos contedores, para non cargalos. Accédese con `docker exec`, que é o que fan os terminais de VS Code e as ordes `daw-*` |
| Ficheiros | No disco Linux de Debian-DAW (`~/proxectos/daw-dev`), nunca en `/mnt/c`. Windows accede por `\\wsl.localhost\Debian-DAW\home\ad\www` e `...\ad\angular` |
| Kit `angular-container` | Só referencia, sen manter |
| Obxectivo | Que daw-dev sexa o contorno do proxecto de fin de ciclo: Angular no cliente; Apache, PHP e Laravel no servidor |

## Paquete da aula

Está en `C:\Users\miguelfm\Projects\daw-aula-paquete-20261111-final` (non vai
no repositorio, ocupa uns 4,8 GB). Para traballar con el noutro equipo hai
que copialo enteiro.

Estado ao 20/11/2026:

- **Imaxe de Angular:** `dwcc-angular.tar.gz` é a sen SSH (SHA256
  `4DADA4F6…`, 424 MB). Construíuse en local desde o commit `04a46c5`; a
  CI aínda non a publicou.
- **Scripts:** os seis son os da rama, actualizados con
  `actualizar-paquete.ps1` despois do commit `1f32c64`. Se o PR cambia antes
  do merge, hai que repetilo.
- **Copia da versión anterior:** a imaxe con SSH e o manifesto de antes
  están en `build\angular-ssh-anterior`.
- **Sen VS Code Server:** non leva ningún (véxase *Pendente*).

## Pendente

1. **Revisar e facer o merge do PR #3.** Ao facelo, a CI publica a imaxe sen
   SSH como `:22`. Fóra da aula, quen teña a instalación vella e faga
   `docker compose pull` perde o acceso por Remote-SSH.
2. **Despregar na aula, despois do merge:**
   1. `gestionar-aula-paralelo.ps1 -Action CopiarModelo`;
   2. `-Action ActualizarProxecto`, coas contas conectadas;
   3. cada usuario repite **Activar DAW Dev** para ter as ordes novas, o
      contrasinal e o acceso directo de Angular.

   Os pasos están en [aula-windows11.md](aula-windows11.md).
3. **VS Code Server para os postos:**
   - O servidor do kit é para VS Code 1.145.0 (commit `a717861c…`), pero as
     notas do 18/11 din que os postos tiñan a 1.122.
   - Mirar o commit nun posto (`code --version`, segunda liña) e executar
     `.\wsl\aula\engadir-vscode-server.ps1 -PackageDirectory <paquete> -Commit <commit>`.
4. **Sen probar:**
   - unha xanela real de VS Code con `daw-code-angular` ou
     `daw-code-proxecto` (só se probou cun `code.cmd` falso), e nada diso na
     aula;
   - deixar o resultado de `ng build` en `www`;
   - as rutas `api` de Laravel a través do *proxy* (o *proxy* si se probou,
     con PHP simple).
5. **Propostas sen decidir:**
   - **Carga xeral de imaxes.** Hoxe `daw.ps1` só carga do paquete a imaxe
     de Angular, e só se falta ou é a antiga. Unha imaxe nova coa mesma
     etiqueta non se recarga, e as de PHP, MariaDB e phpMyAdmin van no
     modelo sen forma de actualizalas. A proposta: en cada `daw-start*`,
     comparar o SHA256 de cada imaxe do manifesto do posto coa última
     cargada nesa conta e facer `docker load` se cambiou.
   - **Unha acción única para o profesor** (por exemplo,
     `PublicarActualizacion`): engadir imaxes, actualizar scripts,
     `CopiarModelo` e `ActualizarProxecto`.
   - **Configuración de Dev Containers para Angular**
     (`.devcontainer/angular/devcontainer.json`), como alternativa ao
     terminal por `docker exec`. O web xa a ten.

## Probas

- **PowerShell:** `tests/aula.ps1`, 45 probas, en Windows PowerShell 5.1.
- **Python:** `tests/proxecto.py`, `tests/migration.py` e
  `tests/vscode-server.py`. Sen `pwsh`, as dúas primeiras aceptan o script
  xa exportado desde o módulo (`DAW_OVERLAY_SCRIPT`, `DAW_MIGRATION_SCRIPT`).
- **CI:** pasa os tres grupos en GitHub (Windows PowerShell 5.1,
  PowerShell 7 e Linux).
- **Probas reais nun equipo que xa ten daw-dev en marcha:** os nomes dos
  contedores son fixos (`daw-dev-web`…), así que hai que usar unha copia
  illada:
  - `COMPOSE_PROJECT_NAME=daw-dev-proba`;
  - un *override* que renomee `web` e `db` e cambie os seus portos;
  - `DB_VOLUME_NAME` propio, porque se non `up` crea `daw-dev_db_data`;
  - unha etiqueta de proba para a imaxe;
  - e borrar todo ao rematar.
