# Changelog

## 0.6.0 - 2026-09-30

- El panel vuelve a ser un popout colgado bajo el icono de la barra (mismo `Panel` + `KeyboardPanel` que el plugin Sessions) en vez de un overlay a pantalla completa. Ancho fijo `Style.space(420)`, que solo se reduce en pantallas más estrechas, e independiente de las ventanas abiertas.
- Alto ajustado a cada vista (Acciones, Apagado, Temporizador); lo que no cabe se desplaza.
- Si se abre desde el reloj de cuenta regresiva, el popout cuelga bajo el reloj; al cerrarse vuelve a su icono.
- Fondo opaco detrás del contenido (el color de popup es translúcido y solo se desenfoca con reglas del compositor).

## 0.5.0 - 2026-09-30

- El panel ya no es una ventana normal (que Hyprland teselaba y cuyo ancho cambiaba según las apps abiertas) sino un overlay del shell: tarjeta centrada de ancho fijo `Style.space(420)` que solo se reduce si la pantalla es más estrecha, y alto máximo `Style.space(680)` ajustado a la pantalla. Se cierra con `Esc` o haciendo clic fuera.
- Fondo opaco y borde del tema; teclas gestionadas en la tarjeta (`Esc`, `Enter`, `Ctrl+←/→`, `Alt+1…6`).

## 0.4.0 - 2026-09-30

- Programar ahora ofrece dos opciones, «Apagado» y «Temporizador», y muestra solo las opciones de la elegida.
- Widget con `allowMultiple` y ajuste `display`: `countdown` muestra un reloj con la cuenta regresiva que solo aparece con un temporizador o apagado activo.
- El botón de la barra ya no intenta meter texto en el slot de icono; la cuenta regresiva vive en el reloj.
- Tests aislados también de `XDG_DATA_HOME`: antes `uninstall.sh` podía borrar la CLI instalada.

## 0.3.0 - 2026-09-30

- Temporizadores con aviso y recordatorio opcional: `timer`, `timers` y `timer-cancel`, varios a la vez.
- Notificación crítica persistente y sonido al vencer.
- Panel: sección «Temporizador con aviso» en Programar con lista de activos y cuenta regresiva.
- Pestañas Acciones/Programar reordenables (arrastrar o `Ctrl+←/→`); comando `now` y acciones inmediatas.

## 0.2.0 - 2026-09-30

- Nuevo `--action poweroff|reboot|suspend|hibernate` (inspirado en omarchy-power-menu).
- Nuevo comando `extend DURACIÓN` para añadir tiempo a un temporizador activo.
- `status` muestra tiempo restante y acción; `status --short` para el widget.
- El widget de barra muestra la cuenta regresiva; el panel permite elegir acción, extender y se actualiza cada segundo; `Esc` cierra.
- Acciones `lock` y `logout`; panel con atajos `Alt+1`–`Alt+6`, confirmación para acciones destructivas y detección de hibernación.
- Correcciones: el aviso respeta `grace_period_seconds`, no avisa si el temporizador fue cancelado y "Conservar existente" ya no falla con el campo vacío.

## 0.1.0 - 2026-09-20

- Primera fase: programación, estado, consulta y cancelación de apagados.
- Panel gráfico y widget de barra para Omarchy.
- CLI con modo `--dry-run`, notificación a 60 segundos y persistencia XDG.
- Sin detección de agentes de IA, procesos, CPU ni finalización de comandos.
