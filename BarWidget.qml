import QtQuick
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.omargond.shutdown-timer"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && typeof panelLoader.item.open === "function") panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && typeof panelLoader.item.close === "function") panelLoader.item.close()
  }

  function openPanel() {
    if (root.opened) root.close()
    else if (panelLoader.item && typeof panelLoader.item.open === "function") root.open()
    else fallback.running = true
  }
  Process { id: fallback; command: ["shutdown-timer", "menu"] }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("ShutdownPanel.qml")
    visible: false
    onLoaded: {
      if ("shell" in item && root.bar && root.bar.shell) item.shell = root.bar.shell
      if ("manifest" in item && root.manifest) item.manifest = root.manifest
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰐥"
    tooltipText: "Shutdown Timer"
    onPressed: root.openPanel()
  }
}
