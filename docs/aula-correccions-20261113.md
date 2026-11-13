# Correccións da integración de aula — 13/11/2026

Esta revisión corrixe o aprovisionamento WSL/Windows de `daw-dev`. Non cambia a versión de PHP, Compose, imaxes, volumes de BD nin a OVA VirtualBox. Os rexistros da aula do 11/11 seguen sendo evidencia histórica; estes cambios non se executaron nos postos.

## Problemas e solucións

| Problema anterior | Comportamento novo |
|---|---|
| CopiarModelo recreaba sempre o Run global, incluso na aula compartida | Baixo demanda por defecto. Retírase só a entrada DAWAula recoñecida, antes de copiar. AutoInicio é opt-in explícito. Unha orde allea no mesmo nome detense para revisión. |
| O instalador renomeaba usuarios/modificaba wsl.conf antes de comprobar o modelo | Lee o marcador como root e valida a orixe SHA antes de migrar. Rexeitamento dun modelo alleo sen modificalo. |
| pkill, chown recursivo e substitución de ligazóns | Sen matar procesos, sen chown recursivo nin borrar datos. Procesos activos, usuarios duplicados, UID inesperado ou directorios con datos provocan erro. |
| Os cambios de wsl.conf podían afectar outras seccións | Cambia só default da sección user e garda copia previa. Conserva outras seccións, comentarios e claves. |
| Instalación de extensións/acceso directo en catch baleiros | Códigos de saída e lista final de extensións comprobados; acceso directo verificado. O fallo queda no estado, sen Success=true. |
| Invocar unha tarefa devolvía éxito antes de coñecer a instalación | Solicitude GUID, SID e fase correlacionados. Espera un Completed da solicitude actual; ignora estados antigos/corruptos. Detecta erros do Planificador e timeout. |
| Paralelo creaba un job por posto sen límite interno | ThrottleLimit real, 5 por defecto (1–10). O mesmo xestor aplica políticas, validacións e comprobacións nos modos serie e paralelo. |

A biblioteca `wsl/aula/daw-aula.psm1` reúne os contratos de paquete, orixe, procesos nativos, autoarranque, estado e tarefas. Os scripts Windows levan BOM UTF-8 e a migración Bash normalízase a LF. Os procesos nativos teñen tempo límite e drénanse stdout/stderr simultaneamente.

## Actualizar un paquete xa preparado

Non é necesario reconstruír nin exportar de novo Debian. No **docente**, actualizar o repositorio e executar sobre a súa copia local do paquete:

```powershell
.\wsl\aula\actualizar-paquete.ps1 -PackageDirectory "$HOME\Projects\daw-aula-paquete-20261111-final" -WhatIf
.\wsl\aula\actualizar-paquete.ps1 -PackageDirectory "$HOME\Projects\daw-aula-paquete-20261111-final"
```

Isto verifica e conserva a imaxe e o seu SHA-256. Garda os scripts/manifesto anteriores en `build/setup-backup-*` e actualiza `SetupRevision=2` e `ScriptSha256`. O nome e a identidade do modelo non cambian: as distribucións existentes non se substitúen. Os novos paquetes de preparar-modelo xa inclúen estes metadatos.

Un paquete antigo ou incompleto detense cunha mensaxe de actualización, antes de distribuír ou modificar unha distro. Distribuír **todos** os ficheiros do paquete, incluído daw-aula.psm1; non copiar unicamente instalar-alumno.ps1. A imaxe debe permanecer no paquete para comprobar a súa integridade.

## Distribuír e activar

Só cando o docente decida actualizar os postos:

```powershell
.\wsl\aula\gestionar-aula-paralelo.ps1 -Action CopiarModelo -Aula 34 -Numero @(1..35) -ThrottleLimit 5 -PackageDirectory "$HOME\Projects\daw-aula-paquete-20261111-final"
.\wsl\aula\gestionar-aula.ps1 -Action InstalarUsuario -Aula 34 -Numero @(1..35)
```

Revisar Success/Error de **cada resultado**; un proceso PowerShell que remate sen erro fatal non implica que todos os postos teñan Success=true. Non reinstalar características Windows nin reiniciar equipos para actualizar só os scripts.

CopiarModelo desactiva o Run xestionado antes de copiar e rexeita un bloqueo de instalación que estea aberto. A partir de aí non se importa nada ao iniciar sesión. Non copiar paquetes mentres se executan instalacións manuais ou outros despregamentos. Para unha aula de uso exclusivo, engadir **AutoInicio** expresamente a CopiarModelo; a entrada só se habilita despois de comprobar o paquete completo.

## Distribucións existentes

- Modelo recoñecido e orixe coincidente: reintento seguro, conserva datos e distro.
- Outro marcador ou outra orixe: erro antes de migrar.
- Falta o rexistro de orixe dun modelo existente: erro conservador. Só tras revisar que é o modelo correcto, o docente pode engadir `-AdoptarExistente` a InstalarUsuario, ou o alumno ao instalador manual. Non se admite un marcador alleo con esa opción.
- Hai procesos do usuario Linux alumno: gardar traballos e pechalos antes de migrar. O script non mata procesos, non executa terminate/shutdown/unregister e non forza unha migración en uso.
- Existen alumno e ad, unha ligazón distinta ou un directorio www con contido: revisar manualmente, non borrar traballos para facer pasar o instalador.
- Un fallo parcial de usermod/groupmod pode requirir revisión, pero a orixe queda rexistrada para identificar o modelo e permitir un reintento. Nunca se borra a distribución para recuperala automaticamente.

Os lanzadores de aula usan `-LinuxUser ad` explicitamente para non depender de que WSL xa recargase wsl.conf. O usuario predeterminado da consola WSL aplícase no seguinte arranque normal; non se forza unha parada de sesións existentes. Noutros usos de daw.ps1 LinuxUser segue sendo opcional.

## Estado e resultado

`%LOCALAPPDATA%\DAW-Aula\estado.json` usa Schema=2: RequestId, UserSid, StartedUtc, Phase, CheckedUtc, ModelSha256, CodeExtensions, CodeSkipped, Shortcut, Success e Error. Escríbese mediante substitución atómica, baixo un bloqueo exclusivo da instalación.

InstalarUsuario espera o resultado do GUID/SID actual. Non confunde o éxito da orde Start-ScheduledTask cunha instalación rematada, nin acepta o Success dunha execución anterior. As tarefas teñen nome único e elimínanse no finally; un corte de WinRM/Windows pode impedir ese cleanup, polo que hai que revisar o Planificador e o log antes de repetir unha operación que quedase incompleta.

Estado mostra o último informe por perfil, con GUID/data/fase: é unha consulta histórica, non unha instalación nova. Os detalles do resultado do xestor están en Data. Para unha instalación expresamente sen VS Code, indicar **SenVSCode**; o estado marca CodeSkipped=true. A creación do acceso directo aos ficheiros www segue sendo obrigatoria. Non se anuncia unha instalación de IDE cando foi omitida.

## Probas

```powershell
.\tests\aula.ps1
```

```sh
python3 tests/migration.py
```

A batería PowerShell execútase en GitHub Actions con Windows PowerShell 5.1, PowerShell 7 Windows e PowerShell 7 Linux. Comproba erros nativos, hashes, orixes, preservación, autoarranque, estados vellos/corruptos, correlación, timeout, políticas de tarefa e concorrencia real de jobs. En Windows constrúese tamén un principal real Interactive/Limited, sen rexistrar tarefas na aula.

A proba Python executa a migración Bash real nunha árbore temporal: substitúe as rutas /home e /etc e as ferramentas de contas por dobres illados. Proba reexecución, preservación do código/wsl.conf, procesos activos, colisións, UID e fallos de usermod; non modifica as contas reais da máquina.

WinRM, WSL e a execución interactiva no dominio simúlanse nas regresións. Non se certifica con esta CI o estado actual da rede/GPO da aula nin un despregamento real destes novos scripts nos 28 postos. Non se engaden TrustedHosts, contrasinais ou cambios permanentes de políticas Windows.
