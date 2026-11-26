import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Services

Item {
    id: root
    property string pluginId
    property var pluginService
    property string pending

    function request(action) {
        if (backlight.running) {
            pending = action;
            return;
        }
        backlight.command = ["@backlight@", action];
        backlight.running = true;
    }

    Process {
        id: backlight
        onExited: {
            if (root.pending !== "") {
                const action = root.pending;
                root.pending = "";
                Qt.callLater(root.request, action);
            }
        }
    }

    IdleMonitor {
        id: idle
        timeout: 60
        respectInhibitors: true
        enabled: !IdleService.externalInhibitActive && !SessionService.idleInhibited
        onIsIdleChanged: root.request(isIdle ? "idle" : "resume")
    }

    Connections {
        target: SessionService
        function onPreparingForSleepChanged() {
            if (!SessionService.preparingForSleep)
                root.request(idle.isIdle ? "idle" : "wake");
        }
    }

    Component.onCompleted: request("init")
    Component.onDestruction: Quickshell.execDetached(["@backlight@", "resume"])
}
