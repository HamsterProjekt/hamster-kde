// Drives Hamster.qml against tests/mock_hamster_service.py; see run_backend_test.sh
import QtQuick
import "../../plasmoid/contents/ui" as Ui
import "../../plasmoid/contents/code/stuff.js" as Stuff

Item {
    function i18n(s) { return s; }

    Ui.Hamster { id: hamster }

    function dump(label) {
        console.log(label, "available=" + hamster.available,
                    "facts=" + hamster.facts.length,
                    "ongoing=" + (hamster.ongoing ? hamster.ongoing.name : "none"),
                    "activities=" + JSON.stringify(hamster.activities),
                    "error=" + JSON.stringify(hamster.lastError));
        for (const f of hamster.facts)
            console.log("   ", f.id, Stuff.timeRange(f), Stuff.serialize(f),
                        Stuff.formatDurationHuman(Stuff.delta(f, hamster.now)));
    }

    Timer {
        property int step: 0
        interval: 700; repeat: true; running: true
        onTriggered: {
            step++;
            if (step === 1) { dump("[initial]"); hamster.continueFact(hamster.facts[1]); }
            else if (step === 2) { dump("[after continue, via FactsChanged signal]"); hamster.stopTracking(); }
            else if (step === 3) { dump("[after stop]"); hamster.addFact("reading@personal,, a book, #fun"); }
            else if (step === 4) {
                dump("[after add]");
                console.log("complete('re') =", Stuff.complete("re", hamster.activities));
                console.log("complete('10:30 co') =", Stuff.complete("10:30 co", hamster.activities));
                hamster.editFact(2); hamster.editFact(0); hamster.showOverview(); hamster.showPreferences();
            }
            else if (step === 5) { dump("[after window calls]"); Qt.quit(); }
        }
    }
}
