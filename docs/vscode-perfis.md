# Perfís separados de VS Code para Programación e DWCS

Usa un perfil do editor por módulo e abre cada contorna nunha xanela propia.
Os nomes seguintes son exemplos: se xa tes os perfís preparados, conserva os
seus nomes reais.

| Módulo | Perfil de VS Code | Carpeta que se abre |
|---|---|---|
| Programación, 1º DAW | `PROG - Java` | O proxecto Java no equipo |
| DWCS, 2º DAW | `DWCS - PHP` | A raíz de `daw-dev`, despois reaberta no contedor |

`daw-dev` prepara actualmente a contorna PHP. O perfil de Java precisa o seu
JDK e as ferramentas correspondentes no equipo; seleccionar ese perfil non
engade Java ao contedor PHP.

## Preparar e asociar os perfís

1. Abre **Manage → Profiles**. Se xa existen, selecciónaos; se tes ficheiros
   `.code-profile`, usa **Import Profile**. Para preparalos desde cero, crea
   un perfil para cada módulo.
2. Na xanela de Programación, abre o proxecto Java e selecciona o seu perfil.
3. Abre outra xanela coa raíz de `daw-dev` e selecciona o perfil de DWCS.

O perfil garda preferencias, extensións, atallos e fragmentos de código.
VS Code lembra a asociación coa carpeta ou co espazo de traballo aberto;
revísaa en **Folders & Workspaces** no editor de perfís. A asociación dunha
carpeta non se estende automaticamente a todos os proxectos que conteña.

Se traballas con varios proxectos, podes gardar un `.code-workspace` por
módulo mediante **File → Save Workspace As…** e asociarlle o perfil.

## Abrir DWCS no contedor

Co perfil de DWCS seleccionado:

1. Comproba que a extensión **Dev Containers**
   (`ms-vscode-remote.remote-containers`) está dispoñible no VS Code local.
2. Abre a raíz de `daw-dev`, onde están `compose.yaml`, `.vscode/` e
   `.devcontainer/`; abrir só `www/` non carga esa configuración de proxecto.
3. Pulsa `Ctrl+Shift+P` e executa **Dev Containers: Reopen in Container**.
4. Na xanela conectada, comproba o perfil activo e selecciona o de DWCS
   se fose necesario. A carpeta local e a do contedor teñen identidades distintas.

A [configuración do devcontainer](../.devcontainer/devcontainer.json) abre
o servizo `web`, co usuario `dev` e o proxecto en `/workspace`.
Declara **PHP Debug** (`xdebug.php-debug`) e **Intelephense**
(`bmewburn.vscode-intelephense-client`) para a contorna do contedor.
O código web segue en `www/`, servido tamén desde `/var/www/html`.

As extensións locais e as do contedor teñen ámbitos distintos. Se falta unha
ferramenta PHP, revisa a sección do contedor na vista **Extensions**.
Settings Sync non sincroniza as extensións da xanela remota.

Para a configuración de Docker e WSL2 en Windows, consulta a
[guía de integración de Windows 11](windows11-contedores.md#integración-con-vs-code-en-windows-11).

## Abrir cun perfil desde o terminal

Exemplos para Linux, supondo os proxectos nestas rutas:

```bash
code --new-window --profile "PROG - Java" ~/Projects/java-vs-proj/javaNewProj
code --new-window --profile "DWCS - PHP" ~/Projects/daw-dev
```

Substitúe rutas e nomes polos teus. Se o nome indicado non existe, VS Code
crea un perfil baleiro: non recupera por si só unha configuración anterior.
O segundo comando abre inicialmente a carpeta local; despois executa
**Dev Containers: Reopen in Container**.

## Que configuración se conserva no repositorio

| Elemento | Función neste proxecto |
|---|---|
| Perfil `DWCS - PHP` | Preferencias persoais do editor seleccionadas en VS Code |
| `.vscode/settings.json` | Axustes do proxecto e terminais para Linux e Windows |
| `.vscode/launch.json` | Configuración de depuración con Xdebug |
| `.devcontainer/devcontainer.json` | Servizo, usuario, carpeta e extensións do contedor |

O perfil de terminal **Contedor DAW Dev** de `.vscode/settings.json` abre unha
shell mediante `docker exec`. Non selecciona un perfil do editor nin conecta
o servidor de extensións de VS Code ao contedor. Para esa integración completa,
usa **Reopen in Container**.

## Levar os perfís a outro equipo

Exporta cada perfil desde **Profiles → Export Profile** a un ficheiro
`.code-profile`. Impórtaos no outro equipo e volve asociar as carpetas cos
seus perfís. O clon de `daw-dev` achega `.vscode/` e `.devcontainer/`;
os perfís persoais prepáranse ou impórtanse en VS Code.

## Referencias

- [Perfís e asociacións de carpetas de VS Code](https://code.visualstudio.com/docs/configure/profiles).
- [Opción `--profile` da liña de comandos](https://code.visualstudio.com/docs/configure/command-line).
- [Desenvolvemento dentro dun contedor](https://code.visualstudio.com/docs/devcontainers/containers).

Guía contrastada coa documentación oficial e coa configuración do repositorio
o 1 de novembro de 2026. Describe o procedemento; non acredita unha proba
interactiva de cambio de perfís nin de reconexión ao contedor.
