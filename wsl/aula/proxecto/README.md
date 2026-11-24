# Ficheiros do proxecto para a aula

`ficheiros/` contén o que `gestionar-aula.ps1 -Action ActualizarProxecto` copia en
`/home/ad/proxectos/daw-dev` de cada Debian-DAW xa importada, coa mesma ruta relativa.
O procedemento está na [guía de despregamento](../../../docs/aula-windows11.md#actualizar-os-ficheiros-dos-proxectos-xa-importados).

## O que contén agora

O contedor web compórtase como a MV Debian da aula de DWCS, para que as rutas, os
permisos e as directivas coincidan cos enunciados:

| Ficheiro | Efecto |
|---|---|
| `compose.override.yaml` | Apache como `www-data:www-data`, coa máscara `022` de Debian no canto da `002` da imaxe; `www` tamén en `/home/ad/html`, que é a raíz web; `datos/` en `/home/ad/datos`; `www-data` sae do grupo `dev`; `/var/lib/php/sessions` con permisos 1733 |
| `docker/aula/zz-aula.ini` | Os valores do `99-dev.ini` de Apache na MV: `output_buffering = Off`, cookie de sesión `HttpOnly` e `SameSite=Lax`, `use_strict_mode`, `save_path`, 32M nas subidas e Xdebug con `trigger` |
| `docker/aula/000-default.conf` | `DocumentRoot /home/ad/html` |
| `datos/LEME.txt` | Crea `datos/` co usuario `ad`, non con `root` |
| `.devcontainer/devcontainer.json` | O do repositorio, con `../compose.override.yaml` na lista: Dev Containers nomea os ficheiros de Compose e non le o *override* por si só |
| `.vscode/launch.json` | O do repositorio, que traduce tamén `/home/ad/html` a `www`: Apache serve desde esa ruta e Xdebug informa dela |
| `compose.yaml` e `docker/angular/` | Os do repositorio, co servizo `angular` de DWCC (perfil `angular`); `daw-start-angular` precisa tamén os comandos novos, que instala «Activar DAW Dev» |

`daw-start` le `compose.override.yaml` porque está ao lado de `compose.yaml`. Os
cambios aplícanse ao recrear o contedor web: no seguinte `daw-start`, ou co
`-Reiniciar` da acción. A [actualización a PHP 8.6](../../../docs/aula-windows11.md#actualizar-a-php-86-nos-equipos-da-aula)
precarga a imaxe nova e retira do `.env` a versión 8.5 que fixaba o modelo anterior.

## Regras da copia

- Non se copia nada en `www/` nin se borra ningún ficheiro.
- En `datos/` só se crean ficheiros novos; os existentes son do alumnado e consérvanse.
- Os ficheiros que se substitúen gárdanse antes en `.daw-backup/<data>-<proceso>/`.
- Antes de cambiar nada compróbanse os SHA256, as rutas (sen ligazóns no destino)
  e que Compose acepte o `compose.override.yaml` novo; ao rematar, o proxecto completo.
- Unha segunda execución coa mesma revisión non cambia nada.

## Cambiar o contido

Engade ou edita ficheiros en `ficheiros/` coa ruta que deben ter no proxecto. Se
cambia `.devcontainer/devcontainer.json` do repositorio, actualiza a copia de aquí:
`tests/aula.ps1` comproba que só difiren na lista de ficheiros de Compose.
`tests/proxecto.py` executa a copia real en Bash e, se hai Docker, valida o resultado
con `docker compose config`.
