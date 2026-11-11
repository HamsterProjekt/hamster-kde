// Renders the popup and the panel item outside Plasma, against the mock
// service; see run_view_test.sh
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../../plasmoid/contents/ui" as Ui
import "../../plasmoid/contents/code/stuff.js" as Stuff

Rectangle {
    id: root
    width: Kirigami.Units.gridUnit * 28
    height: Kirigami.Units.gridUnit * 28
    color: Kirigami.Theme.backgroundColor

    function i18n(s, a) { return a === undefined ? s : s.replace("%1", a); }

    // What main.qml provides to the views
    property bool expanded: true
    property int panelAppearance: 2
    property bool showSummary: true
    property bool vertical: false
    readonly property string panelText: hamster.ongoing
        ? hamster.ongoing.name + " " + Stuff.formatDuration(Stuff.delta(hamster.ongoing, hamster.now))
        : i18n("No activity")
    readonly property url stateIcon: Qt.resolvedUrl(hamster.ongoing
        ? "../../plasmoid/contents/icons/hamster-tracking-symbolic.svg"
        : "../../plasmoid/contents/icons/hamster-idle-symbolic.svg")

    Ui.Hamster { id: hamster }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing

        Ui.CompactRepresentation {
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
            Layout.alignment: Qt.AlignRight
        }
        Kirigami.Separator { Layout.fillWidth: true }
        Ui.FullRepresentation {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
