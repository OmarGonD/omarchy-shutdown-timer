# Changelog

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
