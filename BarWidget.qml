import QtQuick
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.omargond.shutdown-timer"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  function openPanel() {
    if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function") root.bar.shell.summon("io.github.omargond.shutdown-timer", "{}")
    else fallback.running = true
  }
  Process { id: fallback; command: ["shutdown-timer", "menu"] }
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰐥"
    tooltipText: "Shutdown Timer"
    onPressed: root.openPanel()
  }
}
