import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import qs.Services

Item {
    id: root
    property string pluginId
    property var pluginService
    property var pending: []

    function request(action) {
        if (backlight.running) {
            pending.push(action);
            return;
        }
        backlight.command = ["@backlight@", action];
        backlight.running = true;
    }

    Process {
        id: backlight
        onExited: {
            if (root.pending.length > 0)
                Qt.callLater(root.request, root.pending.shift());
        }
    }

    IdleMonitor {
        id: idle
        timeout: 60
        respectInhibitors: true
        enabled: @idleEnabled@ && !IdleService.externalInhibitActive && !SessionService.idleInhibited
        onIsIdleChanged: {
            if (!SessionService.preparingForSleep && !wakeDelay.running)
                root.request(isIdle ? "idle" : "resume");
        }
    }

    Timer {
        id: wakeDelay
        interval: 500
        onTriggered: root.request("wake")
    }

    Connections {
        target: SessionService
        function onPreparingForSleepChanged() {
            if (SessionService.preparingForSleep) {
                wakeDelay.stop();
                root.request("snapshot");
            } else {
                wakeDelay.restart();
            }
        }
    }

    Component.onCompleted: request("init")
}
