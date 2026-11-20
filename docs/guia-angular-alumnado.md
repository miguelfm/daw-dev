# Angular con DAW Dev (DWCC)

O contedor `angular` de DAW Dev trae Node.js 26, npm e Angular CLI 22.
Funciona dentro de `Debian-DAW`, sen Docker Desktop. Visual Studio Code
ábrese en Debian e o seu terminal entra no contedor: os ficheiros edítanse
en Debian e as ordes `ng`, `npm` e `node` execútanse no contedor. Os
proxectos gárdanse na túa conta deste computador e vense tamén desde o
Explorador de Windows.

## Antes da primeira vez

1. Activa DAW Dev na túa conta: no menú Inicio, **DAW Dev → Activar DAW
   Dev**. Se xa o activaras e `daw-help` non amosa `daw-code-angular`,
   actívao outra vez: así chegan a orde e os ficheiros novos do contedor.
   Repetir a activación conserva os teus ficheiros e as bases de datos.
2. VS Code precisa a extensión **WSL** (`ms-vscode-remote.remote-wsl`), que
   a activación xa instala.

## Abrir Angular en Visual Studio Code

Nun terminal de PowerShell:

```powershell
daw-code-angular
```

A orde arranca o contedor `daw-dev-angular` e abre VS Code co espazo de
traballo **DWCC-Angular**. A primeira vez tarda algo máis:

- carga a imaxe do contedor desde o paquete da aula;
- instala en Debian o servidor de VS Code da mesma versión que o VS Code
  de Windows. Se non o atopa no paquete nin en **Descargas**, descárgao.

Na primeira apertura, VS Code fai algunhas preguntas:

1. Se pregunta se confías nos autores dos ficheiros, escolle **Si, confío
   nos autores** (*Yes, I trust the authors*).
2. Se pide permiso para as tarefas automáticas, escolle **Permitir**
   (*Allow Automatic Tasks*). Así ábrese só o terminal do contedor.

Comproba que a esquina inferior esquerda indica `WSL: Debian-DAW` e que
o terminal se chama **Angular no contedor**, co indicador
`node@…:~/proxectos$`. Todos os terminais novos (**Terminal → New
Terminal**) entran tamén no contedor.

Desde Windows, os mesmos proxectos están no cartafol
`\\wsl.localhost\Debian-DAW\home\ad\proxectos\daw-dev\angular`.

## Crear e executar unha aplicación

No terminal de VS Code, en `~/proxectos`:

```bash
ng new primeira-app --defaults --skip-git --package-manager=npm
cd primeira-app
ng serve --host 0.0.0.0
```

`ng new` descarga as dependencias de Internet e tarda menos dun minuto.
Cando `ng serve` remata de compilar, abre `http://localhost:4200/` no
navegador de Windows. Ao gardar un ficheiro en VS Code, a páxina
actualízase nun segundo.

::: note

`--host 0.0.0.0` é necesario: sen el, `ng serve` só atende dentro do
contedor, e o navegador de Windows non chega á aplicación.

:::

## Conectar coa parte servidor (PHP)

O contedor de Angular está na mesma rede que o contedor web de DAW Dev.
Desde el, `http://web` é o Apache con PHP, e os ficheiros de `www` son os
mesmos que ves en `http://localhost`. Para que a aplicación de Angular
chame ao PHP sen problemas de CORS, usa o *proxy* de `ng serve`:

1. Noutro terminal de PowerShell, arranca o web con `daw-start`, ou con
   `daw-start-db` se o PHP usa a base de datos.
2. No cartafol da aplicación, crea `proxy.conf.json`:

   ```json
   { "/api": { "target": "http://web", "changeOrigin": true } }
   ```

3. Arranca Angular co *proxy*:

   ```bash
   ng serve --host 0.0.0.0 --proxy-config proxy.conf.json
   ```

Desde Angular, unha petición a `/api/ola.php` chega ao ficheiro
`www/api/ola.php` do web. O navegador segue en `http://localhost:4200`.

Para un proxecto completo con Angular e PHP ou Laravel, `daw-code-proxecto`
abre os cartafoles `angular` e `www` cun terminal en cada contedor. Consulta a
guía *Proxecto con cliente e servidor en DAW Dev*.

## Ao rematar

1. No terminal onde se executa `ng serve`, preme `Ctrl+C`.
2. Pecha a xanela de VS Code.
3. En PowerShell, `daw-stop` para todos os contedores de DAW Dev, tamén o
   de Angular. Os proxectos consérvanse.

Outro día: `daw-code-angular` e, no terminal, `cd primeira-app` e
`ng serve --host 0.0.0.0`. `daw-status` amosa se o contedor
`daw-dev-angular` está en marcha. `daw-start-angular` arranca o contedor sen
abrir VS Code.

## Problemas habituais

- **Windows non recoñece `daw-code-angular`.** Volve executar **Activar
  DAW Dev** e abre un terminal novo.
- **O terminal di que o contedor de Angular non está creado.** Executa
  `daw-code-angular` ou `daw-start-angular` en PowerShell e abre un
  terminal novo en VS Code.
- **VS Code queda descargando o servidor ou non conecta con WSL.** Se
  `daw-code-angular` avisou de que non puido instalalo, abre en Edge a
  ligazón que amosa, garda o ficheiro en **Descargas** co nome que indica e
  executa outra vez `daw-code-angular`.
- **O navegador non abre `http://localhost:4200/`.** `ng serve` ten que
  estar en marcha no terminal do contedor, con `--host 0.0.0.0`.
- **O porto 4200 xa está ocupado.** Hai outro `ng serve` ou outro contedor
  de Angular en marcha, como o do kit `Angular-Aula.cmd`. Páralo antes: no
  menú do kit, opción **6 · Deter o contedor**.
- **Antes conectabas por SSH a `dwcc-angular`.** Esa conexión xa non se
  usa; os proxectos seguen en `angular`. Podes borrar a entrada
  `dwcc-angular` do ficheiro `.ssh\config` e a chave `dwcc_angular` da túa
  conta de Windows.
