# Shutdown Timer

Plugin nativo para Omarchy con identificador `io.github.omargond.shutdown-timer`.
Esta primera fase permite programar, consultar y cancelar el apagado normal de
la PC mediante un panel gráfico y la CLI `shutdown-timer`.

La detección de finalización de agentes de IA, procesos, CPU y comandos **no
forma parte de esta versión**.

## Requisitos

- Omarchy 4.x con `manifest.json` versión 1.
- `systemd-run --user`, `systemctl --user`, `notify-send`, `jq` y `awk`.
- Una sesión gráfica activa con systemd-logind.

## Instalación y actualización

Desde el repositorio local o una URL Git confiable:

```bash
omarchy plugin add <URL-DEL-REPOSITORIO> --enable --yes
./install.sh
```

`install.sh` es idempotente, no usa sudo y solo instala la CLI en
`~/.local/bin` (o `$XDG_BIN_HOME`) y crea la configuración predeterminada.
La activación del panel se realiza mediante el mecanismo oficial de Omarchy.

Para actualizar un plugin instalado por Git:

```bash
omarchy plugin update io.github.omargond.shutdown-timer --yes
./install.sh
```

## Menú y terminal

El widget de barra abre el panel. También puede abrirse con:

```bash
shutdown-timer menu
```

Ejemplos:

```bash
shutdown-timer 30m
shutdown-timer 45m
shutdown-timer 1h
shutdown-timer 4h
shutdown-timer status
shutdown-timer cancel
shutdown-timer schedule 2.5h
shutdown-timer logs
shutdown-timer --help
```

Se aceptan minutos y horas, incluyendo decimales en horas. El máximo es 168
horas. Se rechazan vacío, cero, negativos, letras, formatos inválidos y valores
mayores al máximo. Si ya existe un temporizador, la CLI permite reemplazarlo,
conservarlo o cancelar la operación (`--replace`, `--keep`, `--cancel`).

## Acciones, extender y cuenta regresiva

```bash
shutdown-timer --action reboot 1h     # poweroff (defecto), reboot, suspend, hibernate, lock, logout
shutdown-timer extend 30m             # suma tiempo al temporizador activo
shutdown-timer status                 # acción, restante y hora prevista
shutdown-timer status --short         # solo la cuenta regresiva (la usa el widget)
```

En el panel: `Alt+1`–`Alt+6` eligen la acción (Bloquear, Cerrar sesión, Suspender, Hibernar, Reiniciar, Apagar); `Hibernar` solo aparece si `omarchy-hibernation-available` lo permite. Programar cerrar sesión, reiniciar o apagar pide confirmación (`Enter` confirma, `Esc` cancela). Los botones «+15m/+30m/+1h» extienden el temporizador activo y el widget de barra muestra la cuenta regresiva.

## Temporizadores con aviso

Además del apagado, puedes crear temporizadores que solo avisan, con un recordatorio opcional. Pueden convivir varios y son independientes del apagado programado.

```bash
shutdown-timer timer 20m apagar la cocina   # avisa en 20 minutos
shutdown-timer timer 1.5h                   # sin mensaje: "Han pasado 1.5h"
shutdown-timer timers                       # lista los activos con el tiempo restante
shutdown-timer timer-cancel ID              # cancela uno (o "all" para todos)
```

Al vencer se muestra una notificación crítica que no desaparece sola (`-u critical -t 0`) y suena `alarm-clock-elapsed`. El aviso se muestra aunque `notifications=false`. En el panel están en **Programar → Temporizador con aviso**, con atajos de 5, 10, 20 y 30 minutos y la lista de activos con su cuenta regresiva y un botón ✕ para cancelarlos. Los temporizadores son unidades de systemd de usuario, así que no sobreviven a un reinicio del equipo (al volver a consultar la lista se limpian los vencidos).

## Reloj de cuenta regresiva en la barra

El widget admite varias instancias. Una segunda instancia con `display: countdown` muestra un reloj que **solo aparece mientras hay un temporizador o un apagado programado** y cuenta hacia el más próximo (`󰔟 19:42`, con `+N` si hay más; se pone en rojo el último minuto). Al pasar el ratón lista todos; al hacer clic abre el panel en Programar, colgado bajo el propio reloj.

Para añadirlo, agrega una entrada más en `bar.layout.center` (o la sección que prefieras) de `~/.config/omarchy/shell.json`:

```json
{ "id": "io.github.omargond.shutdown-timer", "display": "countdown" }
```

La instancia normal (`display: full`, por defecto) sigue siendo el botón que abre el panel; el panel vive en esa instancia, así que conviene mantenerla en la barra. Los widgets de la barra se cargan al iniciar el shell: tras actualizar el plugin ejecuta `omarchy-restart-shell`.

## Funcionamiento y seguridad

Se crean dos unidades transitorias de systemd de usuario: una notifica cuando
faltan 60 segundos y otra ejecuta `systemctl poweroff` al alcanzar la hora
prevista. No dependen de la terminal y no requieren sudo ni reglas sudoers.
La orden real está aislada en `poweroff_command()` para pruebas.

El estado y eventos se guardan en `$XDG_STATE_HOME/shutdown-timer`; la
configuración está en `$XDG_CONFIG_HOME/shutdown-timer/config.ini` y el bloqueo
de concurrencia usa `$XDG_RUNTIME_DIR`. El estado se escribe mediante archivo
temporal y `mv` atómico. Un estado vencido sin unidades activas se elimina.

Configuración predeterminada:

```ini
grace_period_seconds=60
notifications=true
maximum_hours=168
confirm_before_scheduling=true
confirm_before_canceling=false
```

Cancelar sigue siendo posible durante la ventana final:

```bash
shutdown-timer cancel
```

## Simulación

`--dry-run` nunca crea unidades reales ni llama a `systemctl poweroff`:

```bash
shutdown-timer --dry-run 30m
shutdown-timer --dry-run status
shutdown-timer --dry-run cancel
```

La salida muestra los nombres de unidades, la orden hipotética y marca el
estado como `SIMULACIÓN`.

## Desinstalación

```bash
./uninstall.sh
omarchy plugin remove io.github.omargond.shutdown-timer --yes
```

Se cancelan las unidades del plugin y se retira la CLI; configuración y logs se
conservan. Para purgarlos, elimínalos explícitamente después de revisar sus
rutas XDG.

## Pruebas y limitaciones

Las pruebas automatizadas usan un `PATH` falso y mocks de `systemd-run`,
`systemctl` y `notify-send`; nunca apagan el equipo. El panel requiere que
`shutdown-timer` esté instalado en `PATH`. El plugin no puede garantizar que el
apagado continúe después de cerrar por completo la sesión de usuario si el
administrador de usuarios no permanece activo; durante la sesión gráfica
normal las unidades son independientes de la terminal.

La segunda fase puede añadir detección de agentes y procesos, pero no está
incluida aquí.
