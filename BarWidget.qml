import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Translations.js" as I18n

// Two instances of this widget can live on the bar (see manifest allowMultiple):
//   display "full"       (default) power-timer icon that opens the panel.
//   display "countdown"  a clock that only appears while a timer or a scheduled
//                        shutdown is running and counts down to the soonest one.
BarWidget {
  id: root
  moduleName: "io.github.omargond.shutdown-timer"

  readonly property bool countdownMode: setting("display", "full") === "countdown"
  readonly property string language: I18n.language(Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || Qt.locale().name)
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/shutdown-timer"

  // `clock.visible` would be the *effective* visibility, which also depends on
  // this item, so the widget could never reappear once hidden. Use our own flag.
  readonly property bool showClock: countdownMode && nextEntry !== null

  implicitWidth: countdownMode ? (showClock ? clock.implicitWidth : 0) : button.implicitWidth
  implicitHeight: countdownMode ? (showClock ? clock.implicitHeight : 0) : button.implicitHeight
  visible: !countdownMode || showClock

  // ---- Panel (only the full instance hosts it) --------------------------
  readonly property bool hasPanel: !countdownMode && panelLoader.item !== null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property var iconItem: button
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target && !target.opened) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("manifest" in target && root.manifest) target.manifest = root.manifest
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  function open(payloadJson) {
    if (panelLoader.item && typeof panelLoader.item.open === "function") panelLoader.item.open(payloadJson)
  }

  function close() {
    if (panelLoader.item && typeof panelLoader.item.close === "function") panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item && typeof panelLoader.item.closeForPopoutSwitch === "function") panelLoader.item.closeForPopoutSwitch()
  }

  // Open the popout hanging under `anchor` (the countdown clock passes itself).
  function openFrom(anchor, payloadJson) {
    if (!panelLoader.item) return
    if (anchor && "anchorItem" in panelLoader.item) panelLoader.item.anchorItem = anchor
    open(payloadJson)
  }

  function openPanel() {
    if (root.opened) root.close()
    else if (panelLoader.item && typeof panelLoader.item.open === "function") root.open()
    else fallback.running = true
  }

  // From the countdown clock: reach the instance that hosts the panel and
  // open it under the clock, straight on the view that matches what is counting down.
  function openMainPanel() {
    var payload = nextEntry && nextEntry.kind === "shutdown"
      ? '{"tab":"schedule","mode":"shutdown"}' : '{"tab":"schedule","mode":"timer"}'
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i].hasPanel === true) {
        if (items[i].opened) items[i].close()
        else items[i].openFrom(clock, payload)
        return
      }
    }
    summon.command = ["omarchy-shell", "shell", "summon", moduleName, payload]
    summon.running = true
  }

  Process { id: fallback; command: ["shutdown-timer", "menu"] }
  Process { id: summon }

  Loader {
    id: panelLoader
    active: !root.countdownMode
    source: Qt.resolvedUrl("ShutdownPanel.qml")
    visible: false
    onLoaded: {
      if ("shell" in item && root.bar && root.bar.shell) item.shell = root.bar.shell
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // ---- Countdown data ---------------------------------------------------
  property var alarms: []
  property var shutdown: null
  property double nowMs: Date.now()

  FileView {
    path: root.stateDir + "/alarms.json"
    watchChanges: root.countdownMode
    onFileChanged: reload()
    onLoaded: { try { root.alarms = JSON.parse(text()) } catch (error) { root.alarms = [] } root.nowMs = Date.now() }
    onLoadFailed: root.alarms = []
  }
  FileView {
    path: root.stateDir + "/state.json"
    watchChanges: root.countdownMode
    onFileChanged: reload()
    onLoaded: { try { root.shutdown = JSON.parse(text()) } catch (error) { root.shutdown = null } root.nowMs = Date.now() }
    onLoadFailed: root.shutdown = null
  }

  readonly property var entries: {
    var list = []
    for (var i = 0; i < alarms.length; i++) {
      var a = alarms[i]
      if (a.target_epoch * 1000 > nowMs - 1000) list.push({ kind: "timer", target: a.target_epoch, message: a.message || "" })
    }
    if (shutdown && shutdown.status === "scheduled" && shutdown.target_epoch * 1000 > nowMs - 1000)
      list.push({ kind: "shutdown", target: shutdown.target_epoch, message: "" })
    list.sort(function (x, y) { return x.target - y.target })
    return list
  }
  readonly property var nextEntry: entries.length > 0 ? entries[0] : null

  Timer {
    interval: 1000
    repeat: true
    running: root.countdownMode && root.entries.length > 0
    onTriggered: root.nowMs = Date.now()
  }

  function pad(n) { return (n < 10 ? "0" : "") + n }
  function fmt(target) {
    var sec = Math.max(0, Math.round(target - nowMs / 1000))
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60)
    return h > 0 ? h + "h " + pad(m) + "m" : pad(m) + ":" + pad(sec % 60)
  }
  function glyph(entry) { return entry.kind === "shutdown" ? "󰐥" : "󰔟" }
  function tip() {
    var lines = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var name = e.kind === "shutdown" ? I18n.tr(language, "Apagado") : (e.message !== "" ? e.message : I18n.tr(language, "Temporizador"))
      lines.push(name + ": " + fmt(e.target))
    }
    return lines.join("\n")
  }

  // ---- Countdown clock (center) ----------------------------------------
  // Last minute: a filled pill in the theme's urgent colour with text picked
  // for contrast against it. Red text straight on the bar was hard to read.
  readonly property bool urgentNow: nextEntry !== null && nextEntry.target - nowMs / 1000 < 60
  readonly property color urgentColor: root.bar ? root.bar.urgent : Color.urgent
  readonly property real urgentLuma: 0.2126 * urgentColor.r + 0.7152 * urgentColor.g + 0.0722 * urgentColor.b
  readonly property color onUrgent: urgentLuma > 0.5 ? "#101010" : "#ffffff"

  Rectangle {
    visible: root.showClock && root.urgentNow
    anchors.fill: clock
    anchors.topMargin: Math.max(2, (clock.height - Style.space(20)) / 2)
    anchors.bottomMargin: anchors.topMargin
    anchors.leftMargin: Style.space(2)
    anchors.rightMargin: Style.space(2)
    radius: height / 2
    color: root.urgentColor
  }

  WidgetButton {
    id: clock
    anchors.fill: parent
    bar: root.bar
    visible: root.showClock
    text: root.nextEntry === null ? "" : root.glyph(root.nextEntry) + " " + root.fmt(root.nextEntry.target) + (root.entries.length > 1 ? "  +" + (root.entries.length - 1) : "")
    foreground: root.urgentNow ? root.onUrgent : (root.bar ? root.bar.barForeground : Color.foreground)
    active: false
    tooltipText: root.tip()
    onPressed: root.openMainPanel()
  }

  // ---- Icon (right) -----------------------------------------------------
  property string remaining: ""
  Process {
    id: poll
    command: ["shutdown-timer", "status", "--short"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.remaining = String(text).trim() }
  }
  Timer { interval: 15000; repeat: true; running: !root.countdownMode; triggeredOnStart: true; onTriggered: if (!poll.running) poll.running = true }

  BarIconButton {
    id: button
    anchors.fill: parent
    visible: !root.countdownMode
    bar: root.bar
    text: "󰐥"
    tooltipText: root.remaining !== "" ? "Shutdown Timer: " + root.remaining : "Shutdown Timer"
    onPressed: root.openPanel()
  }
}
