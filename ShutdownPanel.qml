import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Translations.js" as I18n

Panel {
    id: root
    moduleName: "io.github.omargond.shutdown-timer"
    manageIpc: false

    // Injected by BarWidget: the bar API, the icon the popout hangs under and
    // the widget that owns this panel (the bar tracks that one, not us).
    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root
    // When the panel is opened from the countdown clock it hangs under the
    // clock; once closed it goes back to its own icon.
    onOpenedChanged: if (!opened && hostWidget && hostWidget.iconItem) anchorItem = hostWidget.iconItem

    readonly property string language: I18n.language(Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || Qt.locale().name)
    property string technicalDetails: ""
    function tr(key, args) { return I18n.tr(language, key, args); }
    property var shell: null
    property var manifest: null
    property string output: ""
    property string customUnit: "m"
    property string timerUnit: "m"
    property var scheduled: null
    property bool editing: false
    property var pendingAction: null
    property var pendingSchedule: null
    property int tab: 0
    property int mode: 0
    property var alarms: []
    readonly property var activeAlarms: alarms
        .filter(function (a) { return a.target_epoch * 1000 > now - 5000; })
        .sort(function (a, b) { return a.target_epoch - b.target_epoch; })
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function fmtLeft(target) {
        var sec = Math.max(0, Math.round(target - now / 1000));
        var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
        return h > 0 ? h + "h " + pad(m) + "m" : pad(m) + ":" + pad(sec % 60);
    }
    function startTimer() {
        var amount = Number(timerInput.text.replace(",", "."));
        if (!isFinite(amount) || amount <= 0) {
            output = root.tr("Ingresa una cantidad mayor que cero.");
            timerInput.forceActiveFocus();
            return;
        }
        var msg = timerMessage.text.trim();
        run(["timer", String(amount) + timerUnit].concat(msg !== "" ? [msg] : []));
    }
    property var tabOrder: [0, 1]
    function moveTab(id, dir) {
        var o = tabOrder.slice(), i = o.indexOf(id), j = i + dir;
        if (i < 0 || j < 0 || j >= o.length) return;
        o.splice(i, 1);
        o.splice(j, 0, id);
        tabOrder = o;
        uiFile.setText(JSON.stringify({tabOrder: o}));
    }
    property string action: "poweroff"
    property bool hibernateAvailable: false
    readonly property bool confirming: pendingSchedule !== null
    readonly property var allActions: [
        {key: "lock",      label: root.tr("Bloquear"),     confirm: false},
        {key: "logout",    label: root.tr("Cerrar sesión"), confirm: true},
        {key: "suspend",   label: root.tr("Suspender"),    confirm: false},
        {key: "hibernate", label: root.tr("Hibernar"),     confirm: false},
        {key: "reboot",    label: root.tr("Reiniciar"),    confirm: true},
        {key: "poweroff",  label: root.tr("Apagar"),       confirm: true}
    ]
    readonly property var actionGlyphs: ({lock: "󰌾", logout: "󰍃", suspend: "󰒲", hibernate: "󰤁", reboot: "󰜉", poweroff: "󰐥"})
    readonly property var actions: allActions.filter(function (a) { return a.key !== "hibernate" || hibernateAvailable; })
    readonly property string scheduledAction: hasSchedule && scheduled.action ? scheduled.action : "poweroff"
    function actionInfo(key) {
        for (var i = 0; i < allActions.length; i++)
            if (allActions[i].key === key) return allActions[i];
        return allActions[5];
    }
    function pickAction(n) {
        var a = allActions[n - 1];
        if (!a || (a.key === "hibernate" && !hibernateAvailable)) return;
        if (tab === 0) runNow(a.key);
        else action = a.key;
    }
    function runNow(key) {
        if (actionInfo(key).confirm) pendingSchedule = {value: "now", mode: "", action: key};
        else run(["--action", key, "now"]);
    }
    property double now: Date.now()
    readonly property bool hasSchedule: scheduled !== null && scheduled.status === "scheduled"

    function loadState() {
        try { scheduled = JSON.parse(stateFile.text()); }
        catch (error) { scheduled = null; }
    }

    function editSchedule() {
        customUnit = "m";
        durationInput.text = String(Math.max(1, Math.ceil((scheduled.target_epoch * 1000 - Date.now()) / 60000)));
        editing = true;
        Qt.callLater(function () {
            durationInput.forceActiveFocus(Qt.OtherFocusReason);
            durationInput.selectAll();
        });
    }

    FileView {
        id: uiFile
        printErrors: false
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/shutdown-timer/ui.json"
        onLoaded: {
            try {
                var o = JSON.parse(text()).tabOrder;
                if (Array.isArray(o) && o.length === 2 && o.indexOf(0) >= 0 && o.indexOf(1) >= 0) root.tabOrder = o;
            } catch (error) {}
        }
    }

    FileView {
        id: alarmsFile
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/shutdown-timer/alarms.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.alarms = JSON.parse(text()); }
            catch (error) { root.alarms = []; }
        }
        onLoadFailed: root.alarms = []
    }

    Timer {
        interval: 1000
        running: root.opened && root.tab === 1 && root.activeAlarms.length > 0
        repeat: true
        onTriggered: root.now = Date.now()
    }

    FileView {
        id: stateFile
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/shutdown-timer/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.loadState()
        onLoadFailed: root.scheduled = null
    }

    Timer {
        interval: 10000
        running: root.opened
        repeat: true
        onTriggered: { root.now = Date.now(); root.refresh(); }
    }
    onPendingScheduleChanged: Qt.callLater(function () { keyCatcher.forceActiveFocus(); })

    readonly property color ink: Color.menu.text
    readonly property color mutedInk: Util.alpha(ink, 0.65)
    readonly property color canvas: Color.menu.background
    readonly property color card: Util.alpha(ink, 0.045)
    readonly property color hairline: Util.alpha(ink, 0.16)
    readonly property color accent: Color.accent
    readonly property color danger: Color.urgent
    readonly property bool busy: proc.running
    readonly property int minutesLeft: hasSchedule ? Math.max(0, Math.ceil((scheduled.target_epoch * 1000 - now) / 60000)) : 0
    readonly property string remaining: minutesLeft >= 60
        ? root.tr("%1 h %2 min", [Math.floor(minutesLeft / 60), minutesLeft % 60])
        : root.tr("%1 min", [minutesLeft])

    function open(payloadJson) {
        pendingSchedule = null;
        now = Date.now();
        root.controller.show();
        tab = tabOrder[0];
        try {
            var payload = JSON.parse(payloadJson || "{}");
            if (payload.tab === "schedule") tab = 1;
            if (payload.tab === "actions") tab = 0;
            if (payload.mode === "timer") mode = 1;
            if (payload.mode === "shutdown") mode = 0;
        } catch (error) {}
        hibernateProbe.running = true;
        refresh();
        Qt.callLater(function () {
            keyCatcher.forceActiveFocus();
        });
    }

    function close() {
        pendingSchedule = null;
        root.controller.hide();
    }

    function dismiss() {
        close();
    }

    function run(args) {
        if (proc.running) {
            if (args.indexOf("status") === -1) {
                if (proc.command.indexOf("status") !== -1) pendingAction = args;
                else output = root.tr("Espera a que termine la operación actual.");
            }
            return;
        }
        technicalDetails = "";
        proc.command = ["shutdown-timer"].concat(args);
        proc.running = true;
    }

    function refresh() {
        run(["status"]);
    }
    function schedule(value, mode) {
        if (value.trim() === "") return;
        if (actionInfo(action).confirm) pendingSchedule = {value: value.trim(), mode: mode || "--replace", action: action};
        else doSchedule(value.trim(), mode || "--replace");
    }
    function doSchedule(value, mode, act) {
        var a = act || action;
        if (value === "now") { run(["--action", a, "now"]); return; }
        run(["--yes", "--action", a, mode, "schedule", value]);
    }
    function confirmPending() {
        var p = pendingSchedule;
        pendingSchedule = null;
        if (p) doSchedule(p.value, p.mode, p.action);
    }
    function extend(value) {
        run(["extend", value]);
    }

    function customDuration() {
        var amount = Number(durationInput.text.replace(",", "."));
        if (!isFinite(amount) || amount <= 0) {
            output = root.tr("Ingresa una cantidad mayor que cero.");
            durationInput.forceActiveFocus();
            return "";
        }
        return String(amount) + customUnit;
    }

    function scheduleCustom(mode) {
        var duration = customDuration();
        if (duration !== "")
            schedule(duration, mode);
    }

    Process {
        id: proc
        onExited: (exitCode, exitStatus) => {
            root.output = exitCode === 0 ? "" : root.tr("No se pudo completar la operación. Consulta los detalles.");
            stateFile.reload();
            alarmsFile.reload();
            if (exitCode === 0 && command.indexOf("timer") === 1) { timerInput.text = ""; timerMessage.text = ""; }
            root.now = Date.now();
            if (exitCode === 0 && command.indexOf("status") === -1) root.editing = false;
            if (root.pendingAction !== null) {
                var action = root.pendingAction;
                root.pendingAction = null;
                Qt.callLater(function () { root.run(action); });
            }
        }
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {}
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (String(text).trim() !== "")
                root.technicalDetails = String(text).trim()
        }
    }

    Process {
        id: hibernateProbe
        command: ["bash", "-c", "command -v omarchy-hibernation-available >/dev/null && omarchy-hibernation-available && echo 1 || echo 0"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.hibernateAvailable = String(text).trim() === "1"
        }
    }


    component ActionButton: Controls.Button {
        id: control
        property bool primary: false
        property bool destructive: false
        readonly property color tone: destructive ? root.danger : root.accent
        implicitHeight: Style.space(38)
        implicitWidth: Math.max(Style.space(80), contentItem.implicitWidth + Style.space(28))
        opacity: enabled ? 1 : 0.45
        hoverEnabled: true
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        contentItem: Text {
            text: control.text
            font: control.font
            color: control.primary ? root.canvas : (control.destructive ? root.danger : root.ink)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: Style.cornerRadius
            color: control.primary ? control.tone
                : Util.alpha(control.tone, control.down ? 0.2 : (control.hovered ? 0.12 : 0.04))
            border.width: control.activeFocus ? 2 : 1
            border.color: control.activeFocus || control.primary ? control.tone : root.hairline
        }
    }

    component ActionTile: Controls.Button {
        id: tile
        property string glyph: ""
        property int number: 0
        property bool selected: false
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: Style.space(82)
        hoverEnabled: true
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        opacity: enabled ? 1 : 0.45
        contentItem: ColumnLayout {
            spacing: Style.space(4)
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.glyph
                color: tile.selected ? root.canvas : root.accent
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.heading
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.text
                color: tile.selected ? root.canvas : root.ink
                font: tile.font
            }
        }
        background: Rectangle {
            radius: Style.cornerRadius
            color: tile.selected ? root.accent : Util.alpha(root.ink, tile.down ? 0.14 : (tile.hovered ? 0.09 : 0.04))
            border.width: tile.activeFocus ? 2 : 1
            border.color: tile.selected || tile.activeFocus ? root.accent : root.hairline
            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Style.space(7)
                text: tile.number
                color: tile.selected ? root.canvas : root.mutedInk
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
            }
        }
    }

    component Label: Text {
        color: root.ink
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
    }

    // Popout hung under the bar icon (same KeyboardPanel the Sessions plugin
    // uses). The width is fixed and only shrinks on a screen narrower than it,
    // so it does not depend on what else is open.
    KeyboardPanel {
        id: popout
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        centerOnBar: false
        focusTarget: keyCatcher
        contentWidth: popout.fittedContentWidth(Style.space(420))
        // Tall enough for the current view; anything longer scrolls inside.
        contentHeight: popout.fittedContentHeight(root.tab === 0 ? Style.space(380)
            : (root.mode === 1 ? Style.space(640) : (root.hasSchedule ? Style.space(680) : Style.space(520))))

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: true

            // The popup colour is translucent and only gets blurred by compositor
            // rules, so paint an opaque base that reaches the card's border.
            Rectangle {
                z: -1
                anchors.fill: parent
                anchors.margins: -popout.padding
                radius: Math.max(0, Style.cornerRadius - 2)
                color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
            }

            Keys.onPressed: function (event) {
                var ctrl = event.modifiers & Qt.ControlModifier;
                var alt = event.modifiers & Qt.AltModifier;
                if (event.key === Qt.Key_Escape) {
                    if (root.pendingSchedule !== null) root.pendingSchedule = null;
                    else root.dismiss();
                    event.accepted = true;
                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.pendingSchedule !== null) {
                    root.confirmPending();
                    event.accepted = true;
                } else if (!root.confirming && ctrl && event.key === Qt.Key_Left) {
                    root.moveTab(root.tab, -1);
                    event.accepted = true;
                } else if (!root.confirming && ctrl && event.key === Qt.Key_Right) {
                    root.moveTab(root.tab, 1);
                    event.accepted = true;
                } else if (!root.confirming && alt && root.tab === 0 && event.key >= Qt.Key_1 && event.key <= Qt.Key_6) {
                    root.pickAction(event.key - Qt.Key_0);
                    event.accepted = true;
                }
            }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(20)
            enabled: !root.confirming

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(12)
                Rectangle {
                    implicitWidth: Style.space(44)
                    implicitHeight: width
                    radius: Style.cornerRadius
                    color: Util.alpha(root.accent, 0.12)
                    Label {
                        anchors.centerIn: parent
                        text: "󰔟"
                        color: root.accent
                        font.pixelSize: Style.font.heading
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(3)
                    Label {
                        Layout.fillWidth: true
                        text: "Shutdown Timer"
                        font.pixelSize: Style.font.title
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.tr("Tu próximo apagado, bajo control")
                        color: root.mutedInk
                        font.pixelSize: Style.font.caption
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)
                Repeater {
                    model: root.tabOrder.map(function (id) { return {t: id, label: id === 0 ? root.tr("Acciones") : root.tr("Programar")}; })
                    Rectangle {
                        id: tabItem
                        required property var modelData
                        readonly property bool current: root.tab === modelData.t
                        Layout.fillWidth: true
                        implicitHeight: Style.space(38)
                        radius: Style.cornerRadius
                        color: current ? root.accent : Util.alpha(root.ink, tabArea.containsMouse ? 0.09 : 0.04)
                        border.width: 1
                        border.color: current ? root.accent : root.hairline
                        Text {
                            anchors.centerIn: parent
                            text: tabItem.modelData.label
                            color: tabItem.current ? root.canvas : root.ink
                            font.family: Style.font.menuFamily
                            font.pixelSize: Style.font.body
                        }
                        MouseArea {
                            id: tabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            property real pressX: 0
                            onPressed: mouse => pressX = mapToItem(null, mouse.x, 0).x
                            onReleased: mouse => {
                                var dx = mapToItem(null, mouse.x, 0).x - pressX;
                                if (Math.abs(dx) > tabItem.width * 0.4) root.moveTab(tabItem.modelData.t, dx > 0 ? 1 : -1);
                                else root.tab = tabItem.modelData.t;
                            }
                        }
                    }
                }
            }

            Controls.ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

                ColumnLayout {
                    width: scroll.availableWidth
                    spacing: Style.space(18)

                    RowLayout {
                        visible: root.tab === 1
                        Layout.fillWidth: true
                        spacing: Style.space(8)
                        Repeater {
                            model: [{m: 0, label: root.tr("Apagado"), glyph: "󰐥"}, {m: 1, label: root.tr("Temporizador"), glyph: "󰔟"}]
                            ActionButton {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: Style.space(54)
                                text: modelData.glyph + "  " + modelData.label
                                primary: root.mode === modelData.m
                                onClicked: root.mode = modelData.m
                            }
                        }
                    }

                    Rectangle {
                        visible: root.tab === 1 && root.mode === 0 && root.hasSchedule
                        Layout.fillWidth: true
                        implicitHeight: statusContent.implicitHeight + Style.space(36)
                        radius: Style.cornerRadius
                        color: Util.alpha(root.accent, 0.07)
                        border.color: Util.alpha(root.accent, 0.25)
                        ColumnLayout {
                            id: statusContent
                            anchors.fill: parent
                            anchors.margins: Style.space(18)
                            spacing: Style.space(10)
                            Label {
                                Layout.fillWidth: true
                                text: root.hasSchedule
                                    ? (root.scheduled.mode === "simulation" ? root.tr("SIMULACIÓN ACTIVA") : (root.scheduledAction === "poweroff" ? root.tr("APAGADO PROGRAMADO") : root.tr("ACCIÓN PROGRAMADA")))
                                    : root.tr("SIN APAGADOS PENDIENTES")
                                color: root.accent
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }
                            Label {
                                Layout.fillWidth: true
                                text: root.hasSchedule ? root.remaining : root.tr("Sigue a tu ritmo")
                                font.pixelSize: Style.font.heading * 1.4
                                font.bold: true
                            }
                            Label {
                                Layout.fillWidth: true
                                text: root.hasSchedule
                                    ? (root.scheduledAction === "poweroff"
                                        ? root.tr("El equipo se apagará el %1", [Qt.formatDateTime(new Date(root.scheduled.target_epoch * 1000), Qt.locale(), Locale.ShortFormat)])
                                        : root.tr("Se ejecutará «%1» el %2", [root.actionInfo(root.scheduledAction).label, Qt.formatDateTime(new Date(root.scheduled.target_epoch * 1000), Qt.locale(), Locale.ShortFormat)]))
                                    : root.tr("Elige una duración y nosotros llevamos la cuenta.")
                                color: root.mutedInk
                            }
                            RowLayout {
                                visible: root.hasSchedule
                                spacing: Style.space(10)
                                ActionButton {
                                    text: root.tr("Editar plazo")
                                    enabled: !root.busy
                                    onClicked: root.editSchedule()
                                }
                                ActionButton {
                                    text: root.tr("Cancelar apagado")
                                    destructive: true
                                    enabled: !root.busy
                                    onClicked: root.run(["cancel"])
                                }
                            }
                            RowLayout {
                                visible: root.hasSchedule
                                spacing: Style.space(8)
                                Label { text: root.tr("Extender") + ":"; color: root.mutedInk }
                                Repeater {
                                    model: ["15m", "30m", "1h"]
                                    ActionButton {
                                        required property string modelData
                                        text: "+" + modelData
                                        enabled: !root.busy
                                        onClicked: root.extend(modelData)
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        visible: root.tab === 0
                        text: root.tr("Se ejecuta al instante")
                        font.bold: true
                    }
                    GridLayout {
                        visible: root.tab === 0
                        Layout.fillWidth: true
                        columns: 3
                        columnSpacing: Style.space(8)
                        rowSpacing: Style.space(8)
                        Repeater {
                            model: root.allActions.map(function (a, i) { return {key: a.key, n: i + 1, label: a.label, glyph: root.actionGlyphs[a.key]}; })
                                .filter(function (a) { return a.key !== "hibernate" || root.hibernateAvailable; })
                            ActionTile {
                                required property var modelData
                                text: modelData.label
                                glyph: modelData.glyph
                                number: modelData.n
                                                                enabled: !root.busy
                                onClicked: root.runNow(modelData.key)
                            }
                        }
                    }

                    Label {
                        visible: root.tab === 1 && root.mode === 0
                        text: root.tr("Duraciones rápidas")
                        font.bold: true
                    }
                    RowLayout {
                        visible: root.tab === 1 && root.mode === 0
                        Layout.fillWidth: true
                        spacing: Style.space(8)
                        Repeater {
                            model: [
                                {label: root.tr("30 min"), value: "30m"},
                                {label: root.tr("45 min"), value: "45m"},
                                {label: root.tr("1 hora"), value: "1h"},
                                {label: root.tr("2 horas"), value: "2h"}
                            ]
                            ActionButton {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitWidth: Style.space(70)
                                text: modelData.label
                                enabled: !root.busy
                                onClicked: root.schedule(modelData.value)
                            }
                        }
                    }

                    Rectangle {
                        visible: root.tab === 1 && root.mode === 0
                        Layout.fillWidth: true
                        implicitHeight: form.implicitHeight + Style.space(32)
                        radius: Style.cornerRadius
                        color: root.card
                        border.color: root.hairline
                        ColumnLayout {
                            id: form
                            anchors.fill: parent
                            anchors.margins: Style.space(16)
                            spacing: Style.space(12)
                            Label {
                                text: root.editing ? root.tr("Editar el apagado") : root.tr("Duración personalizada")
                                font.bold: true
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                Controls.TextField {
                                    id: durationInput
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: Style.space(70)
                                    implicitHeight: Style.space(38)
                                    placeholderText: root.tr("Ej. 20")
                                    Accessible.name: root.tr("Cantidad de tiempo")
                                    color: root.ink
                                    placeholderTextColor: root.mutedInk
                                    selectionColor: root.accent
                                    selectedTextColor: root.canvas
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                    selectByMouse: true
                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                    enabled: !root.busy
                                    background: Rectangle {
                                        radius: Style.cornerRadius
                                        color: root.canvas
                                        border.width: durationInput.activeFocus ? 2 : 1
                                        border.color: durationInput.activeFocus ? root.accent : root.hairline
                                    }
                                    onAccepted: root.scheduleCustom()
                                    readonly property var numpadKeys: ({
                                        [Qt.Key_Insert]: "0", [Qt.Key_End]: "1", [Qt.Key_Down]: "2",
                                        [Qt.Key_PageDown]: "3", [Qt.Key_Left]: "4", [Qt.Key_Clear]: "5",
                                        [Qt.Key_Right]: "6", [Qt.Key_Home]: "7", [Qt.Key_Up]: "8",
                                        [Qt.Key_PageUp]: "9", [Qt.Key_Delete]: "."
                                    })
                                    Keys.onPressed: event => {
                                        if (!(event.modifiers & Qt.KeypadModifier) || !(event.key in numpadKeys)) return;
                                        if (selectedText.length > 0) remove(selectionStart, selectionEnd);
                                        insert(cursorPosition, numpadKeys[event.key]);
                                        event.accepted = true;
                                    }
                                }
                                ActionButton {
                                    text: root.tr("Min")
                                    primary: root.customUnit === "m"
                                    enabled: !root.busy
                                    onClicked: root.customUnit = "m"
                                }
                                ActionButton {
                                    text: root.tr("Horas")
                                    primary: root.customUnit === "h"
                                    enabled: !root.busy
                                    onClicked: root.customUnit = "h"
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                text: root.hasSchedule
                                    ? root.tr("El nuevo plazo reemplaza al actual y empieza desde ahora.")
                                    : root.tr("El plazo empieza al pulsar Programar apagado.")
                                color: root.mutedInk
                                font.pixelSize: Style.font.caption
                            }
                            ActionButton {
                                Layout.fillWidth: true
                                text: root.busy ? root.tr("Procesando…") : (root.hasSchedule ? root.tr("Actualizar apagado") : root.tr("Programar apagado"))
                                primary: true
                                enabled: !root.busy
                                onClicked: root.scheduleCustom()
                            }
                        }
                    }
                    Label {
                        visible: root.tab === 1 && root.mode === 1
                        text: root.tr("Duraciones rápidas")
                        font.bold: true
                    }
                    RowLayout {
                        visible: root.tab === 1 && root.mode === 1
                        Layout.fillWidth: true
                        spacing: Style.space(8)
                        Repeater {
                            model: ["5", "10", "20", "30"]
                            ActionButton {
                                required property string modelData
                                Layout.fillWidth: true
                                implicitWidth: Style.space(70)
                                text: modelData + " min"
                                primary: root.timerUnit === "m" && timerInput.text.trim() === modelData
                                enabled: !root.busy
                                onClicked: { root.timerUnit = "m"; timerInput.text = modelData; }
                            }
                        }
                    }

                    Rectangle {
                        visible: root.tab === 1 && root.mode === 1
                        Layout.fillWidth: true
                        implicitHeight: timerForm.implicitHeight + Style.space(32)
                        radius: Style.cornerRadius
                        color: root.card
                        border.color: root.hairline
                        ColumnLayout {
                            id: timerForm
                            anchors.fill: parent
                            anchors.margins: Style.space(16)
                            spacing: Style.space(12)
                            Label {
                                text: root.tr("Duración personalizada")
                                font.bold: true
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                Controls.TextField {
                                    id: timerInput
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: Style.space(70)
                                    implicitHeight: Style.space(38)
                                    placeholderText: root.tr("Ej. 20")
                                    Accessible.name: root.tr("Cantidad de tiempo")
                                    color: root.ink
                                    placeholderTextColor: root.mutedInk
                                    selectionColor: root.accent
                                    selectedTextColor: root.canvas
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                    selectByMouse: true
                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                    enabled: !root.busy
                                    background: Rectangle {
                                        radius: Style.cornerRadius
                                        color: root.canvas
                                        border.width: timerInput.activeFocus ? 2 : 1
                                        border.color: timerInput.activeFocus ? root.accent : root.hairline
                                    }
                                    onAccepted: timerMessage.forceActiveFocus()
                                    readonly property var numpadKeys: ({
                                        [Qt.Key_Insert]: "0", [Qt.Key_End]: "1", [Qt.Key_Down]: "2",
                                        [Qt.Key_PageDown]: "3", [Qt.Key_Left]: "4", [Qt.Key_Clear]: "5",
                                        [Qt.Key_Right]: "6", [Qt.Key_Home]: "7", [Qt.Key_Up]: "8",
                                        [Qt.Key_PageUp]: "9", [Qt.Key_Delete]: "."
                                    })
                                    Keys.onPressed: event => {
                                        if (!(event.modifiers & Qt.KeypadModifier) || !(event.key in numpadKeys)) return;
                                        if (selectedText.length > 0) remove(selectionStart, selectionEnd);
                                        insert(cursorPosition, numpadKeys[event.key]);
                                        event.accepted = true;
                                    }
                                }
                                ActionButton {
                                    text: root.tr("Min")
                                    primary: root.timerUnit === "m"
                                    enabled: !root.busy
                                    onClicked: root.timerUnit = "m"
                                }
                                ActionButton {
                                    text: root.tr("Horas")
                                    primary: root.timerUnit === "h"
                                    enabled: !root.busy
                                    onClicked: root.timerUnit = "h"
                                }
                            }
                            Controls.TextField {
                                id: timerMessage
                                Layout.fillWidth: true
                                implicitHeight: Style.space(38)
                                placeholderText: root.tr("Recordatorio opcional, ej. apagar la cocina")
                                Accessible.name: root.tr("Recordatorio")
                                color: root.ink
                                placeholderTextColor: root.mutedInk
                                selectionColor: root.accent
                                selectedTextColor: root.canvas
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.body
                                selectByMouse: true
                                enabled: !root.busy
                                background: Rectangle {
                                    radius: Style.cornerRadius
                                    color: root.canvas
                                    border.width: timerMessage.activeFocus ? 2 : 1
                                    border.color: timerMessage.activeFocus ? root.accent : root.hairline
                                }
                                onAccepted: root.startTimer()
                            }
                            Label {
                                Layout.fillWidth: true
                                text: root.tr("El tiempo empieza al pulsar Iniciar temporizador.")
                                color: root.mutedInk
                                font.pixelSize: Style.font.caption
                            }
                            ActionButton {
                                Layout.fillWidth: true
                                text: root.busy ? root.tr("Procesando…") : root.tr("Iniciar temporizador")
                                primary: true
                                enabled: !root.busy
                                onClicked: root.startTimer()
                            }
                        }
                    }

                    Label {
                        visible: root.tab === 1 && root.mode === 1 && root.activeAlarms.length > 0
                        text: root.tr("Temporizadores activos")
                        font.bold: true
                    }
                    Repeater {
                        model: root.tab === 1 && root.mode === 1 ? root.activeAlarms : []
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Style.space(10)
                            Label {
                                text: root.fmtLeft(modelData.target_epoch)
                                color: root.accent
                                font.bold: true
                                wrapMode: Text.NoWrap
                            }
                            Label {
                                Layout.fillWidth: true
                                text: modelData.message !== "" ? modelData.message : root.tr("Sin mensaje")
                                color: modelData.message !== "" ? root.ink : root.mutedInk
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                            }
                            ActionButton {
                                text: "✕"
                                implicitWidth: Style.space(42)
                                destructive: true
                                Accessible.name: root.tr("Cancelar temporizador")
                                enabled: !root.busy
                                onClicked: root.run(["timer-cancel", modelData.id])
                            }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: root.technicalDetails !== ""
                        text: root.tr("Detalles técnicos") + ":\n" + root.technicalDetails
                        textFormat: Text.PlainText
                        color: root.mutedInk
                        font.pixelSize: Style.font.caption
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: root.output !== ""
                        text: root.output
                        color: root.mutedInk
                        font.pixelSize: Style.font.caption
                        textFormat: Text.PlainText
                    }
                }
            }

        }

        Rectangle {
            anchors.fill: parent
            visible: root.confirming
            radius: Style.cornerRadius
            color: Color.menu.scrim
            z: 10
            MouseArea { anchors.fill: parent }
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(Style.space(420), parent.width - Style.space(32))
                height: confirmation.implicitHeight + Style.space(40)
                radius: Style.cornerRadius
                color: root.canvas
                border.color: root.hairline
                ColumnLayout {
                    id: confirmation
                    anchors.fill: parent
                    anchors.margins: Style.space(20)
                    spacing: Style.space(16)
                    Label {
                        Layout.fillWidth: true
                        text: root.pendingSchedule !== null ? (root.pendingSchedule.value === "now" ? root.tr("¿Ejecutar «%1» ahora?", [root.actionInfo(root.pendingSchedule.action).label]) : root.tr("¿Programar «%1» en %2?", [root.actionInfo(root.pendingSchedule.action).label, root.pendingSchedule.value])) : ""
                        font.pixelSize: Style.font.title
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.tr("Guarda tu trabajo antes de continuar.")
                        color: root.mutedInk
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        ActionButton {
                            Layout.fillWidth: true
                            text: root.tr("Volver")
                            onClicked: root.pendingSchedule = null
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            text: root.pendingSchedule !== null && root.pendingSchedule.value === "now" ? root.tr("Sí, ejecutar") : root.tr("Sí, programar")
                            destructive: true
                            primary: true
                            onClicked: root.confirmPending()
                        }
                    }
                }
            }
        }
        }
    }
}
