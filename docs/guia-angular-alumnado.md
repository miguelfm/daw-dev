# Angular con DAW Dev (DWCC)

O contedor `angular` de DAW Dev trae Node.js 26, npm e Angular CLI 22.
Funciona dentro de `Debian`, sen Docker Desktop, e entras nel desde
Visual Studio Code por SSH, coa conexión `dwcc-angular`. Os proxectos
gárdanse na túa conta deste computador e vense tamén desde o Explorador de
Windows.

## Antes da primeira vez

1. Activa DAW Dev na túa conta: no menú Inicio, **DAW Dev → Activar DAW
   Dev**. Se xa o activaras antes do 19/11/2026, actívao outra vez: así
   chegan a orde `daw-start-angular` e os ficheiros do contedor. Repetir a
   activación conserva os teus ficheiros e as bases de datos.
2. Comproba que VS Code ten a extensión **Remote - SSH**
   (`ms-vscode-remote.remote-ssh`). Se non a tes, instálaa desde o panel de
   extensións, que se abre con `Ctrl+Maiús+X`.

## Arrancar o contedor

Nun terminal de PowerShell:

```powershell
daw-start-angular
```

A primeira vez, a orde prepara o acceso e carga a imaxe do contedor, e
tarda uns 30 segundos:

- crea a chave `dwcc_angular` no directorio `.ssh` da túa conta de Windows;
- engade a conexión `dwcc-angular` ao ficheiro `.ssh\config`, se non a
  tiñas.

As veces seguintes arranca en poucos segundos. Remata indicando como
conectar e o enderezo da aplicación.

## Entrar desde Visual Studio Code

1. Preme `F1`, escribe `Remote-SSH: Connect to Host...` e escolle
   `dwcc-angular`. Se VS Code pregunta pola plataforma, escolle **Linux**.
2. Na primeira conexión, acepta a identidade do servidor. VS Code instala
   os seus compoñentes no contedor; cando remata, a esquina inferior
   esquerda indica `SSH: dwcc-angular`.
3. Abre o cartafol `/home/node/proxectos` (**File → Open Folder...**) e
   acepta a confianza no cartafol se a pide.
4. Abre un terminal (**Terminal → New Terminal**). É o do contedor, co
   usuario `node`.

Desde Windows, os mesmos proxectos están no cartafol:

```text
\\wsl.localhost\linux\home\ad\workspace\angular
```

## Crear e executar unha aplicación

No terminal de VS Code, en `/home/node/proxectos`:

```bash
ng new primeira-app --defaults --skip-git --package-manager=npm
cd primeira-app
ng serve --host 0.0.0.0
```

`ng new` descarga as dependencias de Internet. Cando `ng serve` remata de
compilar, abre `http://localhost:4200/` no navegador de Windows. Ao gardar
un ficheiro en VS Code, a páxina actualízase.

::: note

`--host 0.0.0.0` é necesario: sen el, `ng serve` só atende dentro do
contedor, e o navegador de Windows non chega á aplicación.

:::

## Ao rematar

1. No terminal onde se executa `ng serve`, preme `Ctrl+C`.
2. Pecha a xanela remota de VS Code.
3. En PowerShell, `daw-stop` para todos os contedores de DAW Dev, tamén o
   de Angular. Os proxectos consérvanse.

Outro día: `daw-start-angular`, conecta VS Code a `dwcc-angular`, abre
`/home/node/proxectos/primeira-app` e executa `ng serve --host 0.0.0.0`.
`daw-status` amosa se o contedor `daw-angular` está en marcha.

## Problemas habituais

- **Windows non recoñece `daw-start-angular`.** Volve executar **Activar
  DAW Dev** e abre un terminal novo.
- **VS Code non conecta con `dwcc-angular`.** Comproba con `daw-status`
  que `daw-angular` está `Up`; se non, executa `daw-start-angular`.
- **O navegador non abre `http://localhost:4200/`.** `ng serve` ten que
  estar en marcha no terminal do contedor, con `--host 0.0.0.0`.
- **O porto 2222 ou o 4200 xa está ocupado.** Se tamén usas o contedor
  DWCC-Angular de Docker Desktop, páralo antes: os dous usan os mesmos
  portos.
