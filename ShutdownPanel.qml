import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Translations.js" as I18n

Item {
    id: root

    readonly property string language: I18n.language(Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || Qt.locale().name)
    property string technicalDetails: ""
    function tr(key, args) { return I18n.tr(language, key, args); }
    property var shell: null
    property var manifest: null
    property bool closingFromHost: false
    property string output: ""
    property string customUnit: "m"
    property var scheduled: null
    property bool editing: false
    property var pendingAction: null
    property var pendingSchedule: null
    property int tab: 0
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
    readonly property bool opened: window.visible

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
        closingFromHost = false;
        window.visible = true;
        hibernateProbe.running = true;
        refresh();
        Qt.callLater(function () {
            durationInput.forceActiveFocus();
        });
    }

    function close() {
        pendingSchedule = null;
        closingFromHost = true;
        window.visible = false;
        closingFromHost = false;
    }

    function dismiss() {
        if (shell && typeof shell.hide === "function")
            shell.hide("io.github.omargond.shutdown-timer");
        else
            window.visible = false;
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

    FloatingWindow {
        id: window
        title: "Shutdown Timer"
        color: root.canvas
        implicitWidth: Style.space(560)
        implicitHeight: Style.space(600)
        minimumSize: Qt.size(Style.space(440), Style.space(480))
        visible: false
        onVisibleChanged: if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
            root.shell.hide("io.github.omargond.shutdown-timer")

        Shortcut {
            sequence: "Escape"
            enabled: root.opened
            onActivated: {
                if (root.pendingSchedule !== null) root.pendingSchedule = null;
                else root.dismiss();
            }
        }
        Shortcut {
            sequences: ["Return", "Enter"]
            enabled: root.opened && root.pendingSchedule !== null
            onActivated: root.confirmPending()
        }
        Shortcut { sequence: "Alt+1"; enabled: root.opened && !root.confirming; onActivated: root.pickAction(1) }
        Shortcut { sequence: "Alt+2"; enabled: root.opened && !root.confirming; onActivated: root.pickAction(2) }
        Shortcut { sequence: "Alt+3"; enabled: root.opened && !root.confirming; onActivated: root.pickAction(3) }
        Shortcut { sequence: "Alt+4"; enabled: root.opened && !root.confirming; onActivated: root.pickAction(4) }
        Shortcut { sequence: "Alt+5"; enabled: root.opened && !root.confirming; onActivated: root.pickAction(5) }
        Shortcut { sequence: "Alt+6"; enabled: root.opened && !root.confirming; onActivated: root.pickAction(6) }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(24)
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
                    model: [{t: 0, label: root.tr("Acciones")}, {t: 1, label: root.tr("Programar")}]
                    ActionButton {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.label
                        primary: root.tab === modelData.t
                        onClicked: root.tab = modelData.t
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

                    Rectangle {
                        visible: root.tab === 1 && root.hasSchedule
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
                        text: root.tab === 0 ? root.tr("Se ejecuta al instante") : root.tr("Acción a programar")
                        font.bold: true
                    }
                    GridLayout {
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
                                selected: root.tab === 1 && root.action === modelData.key
                                enabled: !root.busy
                                onClicked: root.tab === 0 ? root.runNow(modelData.key) : (root.action = modelData.key)
                            }
                        }
                    }

                    Label {
                        visible: root.tab === 1
                        text: root.tr("Duraciones rápidas")
                        font.bold: true
                    }
                    RowLayout {
                        visible: root.tab === 1
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
                        visible: root.tab === 1
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
