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
  property string remaining: ""
  Process { id: fallback; command: ["shutdown-timer", "menu"] }
  Process {
    id: poll
    command: ["shutdown-timer", "status", "--short"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.remaining = String(text).trim() }
  }
  Timer { interval: 15000; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!poll.running) poll.running = true }
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.remaining !== "" ? "󰐥 " + root.remaining : "󰐥"
    tooltipText: root.remaining !== "" ? "Shutdown Timer: quedan " + root.remaining : "Shutdown Timer"
    onPressed: root.openPanel()
  }
}
