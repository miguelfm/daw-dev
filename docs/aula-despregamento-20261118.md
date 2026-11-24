# Despregamento na aula 34 (18/11/2026)

Estado dos postos ao rematar, problemas atopados e procedemento para a
próxima actualización. Este repositorio é público: as contas do alumnado de
cada posto rexístranse fóra del, nos documentos do docente.

## Estado do 19/11/2026

Comprobado desde A34EQ100 ao final da tarde, cos administradores locais
conectados:

| Postos | Estado |
|---|---|
| 01–13, 15–30, 32, 33 | WinRM restrinxido ao profesor, WSL 3.0.5.0 activo, paquete verificado cos scripts de `3366e5b` e a imaxe de Angular, ficheiros do proxecto na revisión `B4077547` e entrada **Activar DAW Dev** no menú Inicio |
| 14 | WSL instalado por IP; sen paquete. O DNS do centro segue resolvendo `A34EQ14` a `172.20.14.3` |
| 31, 34, 35 | Sen resposta; 34 e 35 non teñen rexistro DNS |

- WSL instalouse o 19/11 nos postos 14, 18, 28 e 29, e WinRM no 28 e no 29,
  con reinicio. Os postos 01–03, 10, 13, 19, 20, 22–27, 30, 32 e 33 tiñan o
  paquete do 11/11, sen os scripts corrixidos.
- Contas activadas: as doce do 18/11 e unha activada polo propio usuario no
  posto 01 desde o menú Inicio (instalación en 53 s, proxecto en 4 s). Todas
  están na revisión `471F9A86`: para ter `daw-start-angular` e a revisión
  `B4077547`, cada usuario repite **Activar DAW Dev**.

## Estado dos postos o 18/11/2026

Cada posto instalouse para a conta que tiña a sesión aberta. Outra conta no
mesmo posto aínda non ten o contorno.

| Postos | Estado |
|---|---|
| 04–09, 11, 12, 15–17, 21 | Completos: paquete cos scripts de `400ad03`, `Debian` na conta conectada, extensións Dev Containers e WSL, acceso directo e proxecto na revisión `471F9A86` (`944b03a`) |
| 14 | WinRM activado por IP. O DNS do centro resolve `A34EQ14` a `172.20.14.3`, e o posto está en `172.21.34.14`: os scripts, que usan o nome e Kerberos, non chegan. Sen paquete |
| 18 | WinRM activado. WSL desactivado e sen paquete |
| Os demais | Apagados; sen comprobar |

No posto 14, `ipconfig /registerdns` non corrixe o rexistro: o servidor DNS
(`172.30.1.4`) rexeita a actualización (evento 8018 de `DNS-Client`). Hai
que corrixilo no DNS do centro antes de traballar nese posto.

O paquete é `daw-aula-paquete-20261111-final` (imaxe `2A027CA3…`, do
11/11/2026), cos scripts actualizados por `actualizar-paquete.ps1`.

## Comprobacións

Executado como o alumno conectado no posto A34EQ16, cunha tarefa sen xanela:

- `daw-start` arranca `web` en 3 s; `daw-start-all`, os tres contedores
  en 19 s, coa primeira inicialización de MariaDB.
- Desde Windows, `http://localhost/` e `http://localhost:8081/` responden
  200.
- No contedor: `DocumentRoot /home/ad/html`, Apache como `www-data`, as
  directivas de `zz-aula.ini` e PHP 8.5.12. MariaDB 12.3.3 acepta
  `dwcs`/`abc123.` e `root`/`abc123.`; as variables `DB_*` están definidas.
- `wsl -d Debian` entra como `ad`; `docker compose exec -u dev web`,
  como `dev`, con `php`, `composer`, `git`, `mariadb` e `nano`.

Sen comprobar: abrir o proxecto con Dev Containers e unha sesión real de
Xdebug coa nova tradución de `/home/ad/html` en `launch.json`.

## Problemas e solucións

| Problema | Solución | Commit |
|---|---|---|
| WSL 3.0.5 non recoñece as opcións entre aspas: `"--list"` executábase como orde, e fallaban todas as chamadas a `wsl.exe` | Só se citan os argumentos baleiros ou con espazos ou aspas | `400ad03` |
| VS Code 1.122 garda a CLI nun directorio co commit | Lese a ruta de `bin\code.cmd` | `400ad03` |
| Con Windows Terminal como terminal predeterminado, a tarefa do alumno ábrese nunha xanela visible; ao pechala, a instalación morre con `0xC000013A` | A tarefa execútase en `conhost --headless`, e un fin sen estado detéctase aos 5 s | `400ad03` |
| `New-Module` rexeitou o módulo en `ActualizarProxecto` (`ParameterBindingException`) en todos os postos, sen causa aclarada | O módulo impórtase desde un ficheiro temporal, unha vez por sesión | `400ad03` |
| Apache serve desde `/home/ad/html`, e `launch.json` só traducía `/var/www/html` | `launch.json` traduce as dúas rutas e `ActualizarProxecto` instálao | `944b03a` |
| A guía do alumnado daba `dwcs`/`dwcs` como credenciais | Guía reescrita co comprobado | `944b03a` |

Nos postos 07 e 15, a instalación morreu durante `wsl --import`. A
importación continuou e rematou, pero sen o rexistro de orixe, e o reintento
detívose. Completáronse con `InstalarUsuario -AdoptarExistente`, que comproba
a marca do modelo antes de cambiar nada. Non se debe repetir a instalación
mentres unha importación siga en curso: o tamaño de
`%LOCALAPPDATA%\wsl\Debian\ext4.vhdx` chega a uns 3 GB ao rematar.

## Próxima actualización

Desde a raíz do repositorio, co paquete local actualizado
(`wsl\aula\actualizar-paquete.ps1`):

1. `gestionar-aula.ps1 -Action Comprobar -Aula 34`: postos que responden.
2. `gestionar-aula.ps1 -Action Estado -Aula 34`: para cada perfil, o
   resultado e a data da última instalación (`estado.json`).
3. `gestionar-aula-paralelo.ps1 -Action CopiarModelo`: deixa o paquete local
   en cada posto e comproba os SHA-256. Non toca as distribucións instaladas.
4. Co alumnado conectado, `InstalarUsuario` nas contas que aínda non teñen
   o contorno. Repetila nunha conta instalada é segura: conserva a
   distribución e os datos.
5. `gestionar-aula-paralelo.ps1 -Action ActualizarProxecto`: a revisión de
   cada conta conectada; `Unchanged` en todos os ficheiros indica que xa
   estaba ao día.

`Estado` non amosa a revisión do proxecto nin a versión do paquete de cada
posto. Están en `%LOCALAPPDATA%\DAW-Aula\proxecto-estado.json` de cada perfil
e en `C:\ProgramData\DAW-Aula\manifest.json`. Pendente: unha acción que reúna
os tres datos de todos os postos e contas.
