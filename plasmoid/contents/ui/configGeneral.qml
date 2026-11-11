// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property alias cfg_panelAppearance: appearance.currentIndex
    property alias cfg_showSummary: summary.checked

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: appearance
            Kirigami.FormData.label: i18n("Show in panel:")
            model: [i18n("Activity and time"), i18n("Icon"), i18n("Icon, activity and time")]
        }

        QQC2.CheckBox {
            id: summary
            Kirigami.FormData.label: i18n("Popup:")
            text: i18n("Show time per category")
        }
    }
}
