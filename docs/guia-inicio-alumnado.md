# Guía de Inicio e Uso da Contorna de Desenvolvemento (DWCS)

Benvido/a á contorna de desenvolvemento para o módulo de **Desenvolvemento Web en Contorno Servidor (DWCS)**.

Esta contorna baséase en contedores lixeiros sobre **WSL2 (Debian-DAW)** e **Docker Engine**. Funciona de maneira illada e optimizada no teu equipo, sen necesidade de permisos de administrador en Windows nin de software pesado como Docker Desktop.

---

## 1. Onde están os teus proxectos e código (`www`)

O teu cartafol de traballo principal é o *document root* do servidor web Apache:

* **Acceso rápido no Escritorio:** Fai dobre clic na icona **«DAW - Proxectos (www)»**.
* **Desde o Explorador de Windows:** Podes acceder en calquera momento pegando esta ruta na barra de direccións:
  ```text
  \\wsl.localhost\Debian-DAW\home\ad\www
  ```

> [!TIP]
> Calquera ficheiro `.php` ou `.html` que gardes dentro deste cartafol estará inmediatamente dispoñible no navegador web.

---

## 2. Comandos de control diario

Podes controlar os servizos en calquera momento abrindo un terminal de **PowerShell** ou **CMD** (sen permisos de administrador):

| Comando | Que fai | Cando usalo |
|---|---|---|
| `daw-start` | Inicia o servidor web Apache con PHP 8.5 | Para exercicios de PHP sen base de datos. |
| `daw-start-all` | Inicia Web + MariaDB + phpMyAdmin | Para actividades con bases de datos. |
| `daw-stop` | Detén todos os contedores | **Sempre ao rematar a clase** antes de pechar sesión. |
| `daw-status` | Mostra o estado e portos dos contedores | Para comprobar se os servizos están en marcha. |
| `daw-code` | Abre o proxecto en Visual Studio Code | Para comezar a programar. |
| `daw-logs` | Mostra os rexistros e erros en tempo real | Para depurar erros internos de PHP ou Apache (`Ctrl+C` para saír). |
| `daw-help` | Mostra a listaxe rápida de ordes | Cando non lembres algún comando. |

---

## 3. Como traballar con Visual Studio Code

### Opción recomendada: Dev Containers (Contenedor integrado)

A aula está preparada para que poidas programar directamente **dentro do contedor**, coas ferramentas de PHP, Git, Composer e depuración listas:

1. Abre un terminal e executa:
   ```powershell
   daw-code
   ```
2. Ao abrirse Visual Studio Code, aparecerá un aviso na esquina inferior dereita:
   > *Folder contains a Dev Container configuration file. Reopen to run in a container.*
3. Fai clic no botón **«Reopen in Container»**.
   *(Se o aviso desapareceu, preme `F1` ou `Ctrl+Shift+P` e escribe `Dev Containers: Reopen in Container`).*
4. O proxecto abrirase dentro do contedor en poucos segundos:
   - Se abres o terminal integrado (`Ctrl+\``), estarás directamente na liña de ordes de Linux como usuario `dev`.
   - Dispós de `php`, `composer`, `git` e do cliente de consola `mariadb` sen instalar nada en Windows.
   - A depuración paso a paso con **Xdebug** funciona premendo `F5`.

### Opción alternativa: Edición directa de ficheiros

Se prefires traballar co teu editor local sen Dev Containers:
1. Arranca o servizo web co comando `daw-start`.
2. Abre o acceso directo do Escritorio **«DAW - Proxectos (www)»** en VS Code ou no teu editor habitual.
3. Edita e garda os ficheiros `.php` normalmente.

---

## 4. Acceso aos servizos desde o navegador

Unha vez iniciados os servizos, accede desde calquera navegador:

| Servizo | Dirección URL | Credenciais de acceso |
|---|---|---|
| **Servidor Web PHP** | [http://localhost](http://localhost) | Acceso directo aos ficheiros de `www/` |
| **Xestor phpMyAdmin** | [http://localhost:8081](http://localhost:8081) | Servidor: `db`<br>Usuario: `dwcs`<br>Contrasinal: `dwcs` |
| **Consola MariaDB** | Porto `3306` | Usuario root: `root` / `root` |

> [!NOTE]
> Para que funcionen **phpMyAdmin** e a base de datos **MariaDB**, debes arrancar a contorna con `daw-start-all` (ou `daw-start-db`).

---

## 5. Boas prácticas na aula

1. **Peche limpo ao rematar:** Antes de saír da aula ou apagar o equipo, executa sempre no terminal:
   ```powershell
   daw-stop
   ```
   Isto libera os portos de rede (`80`, `8081`, `3306`) e a memoria RAM para outros compañeiros ou sesións.
2. **Persistencia dos teus datos:** Os teus ficheiros en `www` e as bases de datos que crees en MariaDB consérvanse intactos aínda que pares os contedores con `daw-stop`.
3. **Copias de seguridade:** Lembra subir periodicamente o teu código ao teu repositorio persoal de Git (GitHub/GitLab).

---

## 6. Dúbidas habituais e resolución de incidencias

* **A páxina web dá erro de conexión («Non se pode conectar»):**
  Comproba o estado con `daw-status`. Se os contedores están detidos, executa `daw-start` ou `daw-start-all`.
* **Modifiquei un ficheiro PHP ou CSS pero non vexo os cambios:**
  Forza a recarga da páxina no navegador limpando a caché con `Ctrl + F5` (ou `Ctrl + Shift + R`).
* **phpMyAdmin indica erro ao conectar co servidor de base de datos:**
  Verifica que arranquiches con `daw-start-all`. Se arrancaches con `daw-start`, só está activo o servidor web.
* **Non se recoñecen os comandos `daw-*`:**
  Abre unha nova ventá de terminal de PowerShell. Os atallos cárganse ao iniciar sesión na túa conta de usuario.
