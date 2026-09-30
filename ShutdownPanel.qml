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
    property string output: root.tr("Consultando el estado…")
    property string customUnit: "m"
    property var scheduled: null
    property bool editing: false
    property var pendingAction: null
    property bool confirmingShutdown: false
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
    readonly property bool busy: proc.running || immediateShutdown.running
    readonly property int minutesLeft: hasSchedule ? Math.max(0, Math.ceil((scheduled.target_epoch * 1000 - now) / 60000)) : 0
    readonly property string remaining: minutesLeft >= 60
        ? root.tr("%1 h %2 min", [Math.floor(minutesLeft / 60), minutesLeft % 60])
        : root.tr("%1 min", [minutesLeft])

    function open(payloadJson) {
        confirmingShutdown = false;
        now = Date.now();
        closingFromHost = false;
        window.visible = true;
        refresh();
        Qt.callLater(function () {
            durationInput.forceActiveFocus();
        });
    }

    function close() {
        confirmingShutdown = false;
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
        if (value.trim() !== "")
            run(["--yes", mode || "--replace", "schedule", value.trim()]);
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
            root.output = exitCode === 0 ? root.tr("Operación terminada.") : root.tr("No se pudo completar la operación. Consulta los detalles.");
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
        id: immediateShutdown
        command: ["systemctl", "poweroff"]
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (String(text).trim() !== "") root.technicalDetails = String(text).trim()
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.confirmingShutdown = false;
                root.output = root.tr("No se pudo apagar el equipo.");
            }
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
                if (root.confirmingShutdown) root.confirmingShutdown = false;
                else root.dismiss();
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(24)
            spacing: Style.space(20)
            enabled: !root.confirmingShutdown

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
                RowLayout {
                    spacing: Style.space(8)
                    ActionButton {
                        Layout.fillWidth: true
                        text: root.tr("Cerrar")
                        onClicked: root.dismiss()
                    }
                    ActionButton {
                        Layout.fillWidth: true
                        text: root.tr("Apagar")
                        destructive: true
                        enabled: !root.busy
                        onClicked: root.confirmingShutdown = true
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
                                    ? (root.scheduled.mode === "simulation" ? root.tr("SIMULACIÓN ACTIVA") : root.tr("APAGADO PROGRAMADO"))
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
                                    ? root.tr("El equipo se apagará el %1", [Qt.formatDateTime(new Date(root.scheduled.target_epoch * 1000), Qt.locale(), Locale.ShortFormat)])
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
                        }
                    }

                    Label {
                        text: root.tr("Duraciones rápidas")
                        font.bold: true
                    }
                    RowLayout {
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
            visible: root.confirmingShutdown
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
                        text: root.tr("¿Apagar el equipo ahora?")
                        font.pixelSize: Style.font.title
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.tr("Guarda tu trabajo antes de continuar. El equipo se apagará inmediatamente.")
                        color: root.mutedInk
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        ActionButton {
                            Layout.fillWidth: true
                            text: root.tr("Volver")
                            enabled: !immediateShutdown.running
                            onClicked: root.confirmingShutdown = false
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            text: immediateShutdown.running ? root.tr("Apagando…") : root.tr("Sí, apagar")
                            destructive: true
                            primary: true
                            enabled: !immediateShutdown.running
                            onClicked: immediateShutdown.running = true
                        }
                    }
                }
            }
        }
    }
}
