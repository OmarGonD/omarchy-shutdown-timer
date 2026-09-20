import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool closingFromHost: false
  property string output: ""
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    refresh()
    Qt.callLater(function() { input.forceActiveFocus() })
  }
  function close() { closingFromHost = true; window.visible = false; closingFromHost = false }
  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide("io.github.omargond.shutdown-timer")
    else window.visible = false
  }
  function run(args) { proc.command = ["shutdown-timer"].concat(args); proc.running = true }
  function refresh() { run(["status"]) }
  function schedule(value, mode) { run(["--yes"].concat(mode ? [mode] : []).concat(["schedule", value])) }

  Process {
    id: proc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.output = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (String(text).trim() !== "") root.output = String(text).trim() }
  }

  FloatingWindow {
    id: window
    title: "Shutdown Timer"
    color: root.background
    implicitWidth: 520
    implicitHeight: 560
    minimumSize: Qt.size(420, 460)
    onVisibleChanged: if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function") root.shell.hide("io.github.omargond.shutdown-timer")

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(22)
      spacing: Style.space(14)
      Text { text: "Shutdown Timer"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.heading; font.bold: true }
      Text { text: "Programa un apagado normal mediante systemd-logind."; color: Qt.darker(root.foreground, 1.4); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap; width: parent.width }
      Row { spacing: Style.space(7); Repeater { model: ["30m", "45m", "1h"]; Button { text: modelData; onClicked: root.schedule(modelData) } } }
      Row { spacing: Style.space(7); TextField { id: input; width: 150; placeholderText: "ej. 2.5h"; onAccepted: if (text !== "") root.schedule(text) }; Button { text: "Apagar en X horas"; onClicked: if (input.text !== "") root.schedule(input.text) } }
      Row { spacing: Style.space(7); Button { text: "Ver apagado programado"; onClicked: root.refresh() }; Button { text: "Cancelar apagado"; onClicked: root.run(["cancel"]) } }
      Row { spacing: Style.space(7); Button { text: "Reemplazar existente"; onClicked: if (input.text !== "") root.schedule(input.text, "--replace") }; Button { text: "Conservar existente"; onClicked: root.schedule(input.text, "--keep") } }
      Text { text: "Resultado"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
      ScrollView { width: parent.width; height: 250; Text { width: parent.width; text: root.output; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; wrapMode: Text.Wrap; textFormat: Text.PlainText } }
      Row { spacing: Style.space(7); Button { text: "Configuración"; onClicked: root.run(["config"]) }; Button { text: "Salir"; onClicked: root.dismiss() } }
    }
  }
}
