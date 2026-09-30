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
    cancelPending()
    hibProbe.running = true
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function close() { closingFromHost = true; window.visible = false; closingFromHost = false }
  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide("io.github.omargond.shutdown-timer")
    else window.visible = false
  }
  function run(args) { proc.command = ["shutdown-timer"].concat(args); proc.running = true }
  function refresh() { run(["status"]) }
  readonly property var allActions: [
    { key: "lock",      label: "1 Bloquear",  confirm: false },
    { key: "logout",    label: "2 Cerrar sesión", confirm: true },
    { key: "suspend",   label: "3 Suspender", confirm: false },
    { key: "hibernate", label: "4 Hibernar",  confirm: false },
    { key: "reboot",    label: "5 Reiniciar", confirm: true },
    { key: "poweroff",  label: "6 Apagar",    confirm: true }
  ]
  property bool hibernateAvailable: false
  readonly property var actions: allActions.filter(function(a) { return a.key !== "hibernate" || hibernateAvailable })
  property string action: "poweroff"
  property string pendingValue: ""
  property string pendingMode: ""
  readonly property bool confirming: pendingValue !== ""
  function currentAction() { for (var i = 0; i < actions.length; i++) if (actions[i].key === action) return actions[i]; return actions[0] }
  function pickAction(n) {
    for (var i = 0; i < allActions.length; i++) {
      if (allActions[i].label.charAt(0) === String(n) && actions.indexOf(allActions[i]) >= 0) { action = allActions[i].key; combo.currentIndex = actions.indexOf(allActions[i]); return }
    }
  }
  function schedule(value, mode) {
    if (value === "") return
    if (currentAction().confirm) { pendingValue = value; pendingMode = mode || ""; return }
    doSchedule(value, mode)
  }
  function confirmPending() { var v = pendingValue, m = pendingMode; pendingValue = ""; pendingMode = ""; doSchedule(v, m) }
  function cancelPending() { pendingValue = ""; pendingMode = "" }
  function doSchedule(value, mode) { run(["--yes", "--action", root.action].concat(mode ? [mode] : []).concat(["schedule", value])) }
  function extend(value) { run(["extend", value]) }

  Process {
    id: hibProbe
    command: ["bash", "-c", "command -v omarchy-hibernation-available >/dev/null && omarchy-hibernation-available && echo 1 || echo 0"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.hibernateAvailable = String(text).trim() === "1" }
  }
  Timer { interval: 1000; repeat: true; running: window.visible && !proc.running; onTriggered: root.refresh() }

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
    implicitHeight: 640
    minimumSize: Qt.size(420, 460)
    onVisibleChanged: if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function") root.shell.hide("io.github.omargond.shutdown-timer")

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.confirming ? root.cancelPending() : root.dismiss(); event.accepted = true }
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.confirming) { root.confirmPending(); event.accepted = true }
        else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6 && !input.activeFocus) { root.pickAction(event.key - Qt.Key_0); event.accepted = true }
      }
    }
    Column {
      anchors.fill: parent
      anchors.margins: Style.space(22)
      spacing: Style.space(14)
      Text { text: "Shutdown Timer"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.heading; font.bold: true }
      Text { text: "Programa un apagado normal mediante systemd-logind."; color: Qt.darker(root.foreground, 1.4); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap; width: parent.width }
      Row { spacing: Style.space(7); Text { text: "Acción"; color: root.foreground; anchors.verticalCenter: parent.verticalCenter; font.family: Style.font.family }; ComboBox { id: combo; model: root.actions.map(function(a) { return a.label }); onActivated: root.action = root.actions[currentIndex].key } }
      Row {
        visible: root.confirming; spacing: Style.space(7)
        Text { text: "¿" + (root.currentAction().label.substring(2)) + " en " + root.pendingValue + "?"; color: root.foreground; anchors.verticalCenter: parent.verticalCenter; font.family: Style.font.family; font.bold: true }
        Button { text: "Confirmar (Enter)"; onClicked: root.confirmPending() }
        Button { text: "Cancelar (Esc)"; onClicked: root.cancelPending() }
      }
      Row { spacing: Style.space(7); Repeater { model: ["30m", "45m", "1h", "3h", "4h"]; Button { text: modelData; onClicked: root.schedule(modelData) } } }
      Row { spacing: Style.space(7); Text { text: "Extender"; color: root.foreground; anchors.verticalCenter: parent.verticalCenter; font.family: Style.font.family }; Repeater { model: ["15m", "30m", "1h"]; Button { text: "+" + modelData; onClicked: root.extend(modelData) } } }
      Row { spacing: Style.space(7); TextField { id: input; width: 150; placeholderText: "ej. 2.5h"; onAccepted: if (text !== "") root.schedule(text) }; Button { text: "Apagar en X horas"; onClicked: if (input.text !== "") root.schedule(input.text) } }
      Row { spacing: Style.space(7); Button { text: "Ver apagado programado"; onClicked: root.refresh() }; Button { text: "Cancelar apagado"; onClicked: root.run(["cancel"]) } }
      Row { spacing: Style.space(7); Button { text: "Reemplazar existente"; onClicked: if (input.text !== "") root.schedule(input.text, "--replace") }; Button { text: "Conservar existente"; enabled: input.text !== ""; onClicked: root.schedule(input.text, "--keep") } }
      Text { text: "Resultado"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
      ScrollView { width: parent.width; height: 200; Text { width: parent.width; text: root.output; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; wrapMode: Text.Wrap; textFormat: Text.PlainText } }
      Row { spacing: Style.space(7); Button { text: "Configuración"; onClicked: root.run(["config"]) }; Button { text: "Salir"; onClicked: root.dismiss() } }
    }
  }
}
