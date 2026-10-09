import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property string moduleName: "io.github.bmontythe3rd.display-manager"
  property string helperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + moduleName + "/bin/display-manager"
  property string lastTopology: ""
  property string pendingTopology: ""
  // A profile that fails to apply is retried a few times, then left alone
  // until the set of connected displays changes. Every attempt modesets all
  // outputs twice (apply, then restore), so retrying on each 4 s tick keeps
  // the screens blanking for as long as the topology stays the same.
  property int maxAttempts: 3
  property string failedTopology: ""
  property int failedAttempts: 0

  function checkTopology() {
    if (!topologyProc.running) {
      topologyProc.command = [helperPath, "topology"]
      topologyProc.running = true
    }
  }

  Component.onCompleted: checkTopology()

  Timer { interval: 4000; running: true; repeat: true; onTriggered: root.checkTopology() }

  Process {
    id: topologyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root) return
        var value = String(text || "").trim()
        if (!value || value === root.lastTopology) return
        if (value === root.failedTopology && root.failedAttempts >= root.maxAttempts) return
        if (matchProc.running) return
        root.pendingTopology = value
        matchProc.activeTopology = value
        matchProc.command = [root.helperPath, "profiles-match"]
        matchProc.running = true
      }
    }
  }

  Process {
    id: matchProc
    property string activeTopology: ""

    function handleResult(rawJson) {
      if (!root || !activeTopology) return
      try {
        var result = JSON.parse(String(rawJson || "{}"))
        if (result.ok === true) {
          root.lastTopology = activeTopology
          root.failedTopology = ""
          root.failedAttempts = 0
        }
        if (result.matched) {
          Quickshell.execDetached(["omarchy-notification-send", "-g", "󰍺", "Display profile applied", result.name])
        }
      } catch (e) {}
    }

    stdout: StdioCollector {
      id: matchOutput
      waitForEnd: true
      onStreamFinished: matchProc.handleResult(text)
    }
    stderr: StdioCollector { id: matchError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var detail = String(matchError.text || "").trim()
        console.warn("Display profile match failed" + (detail ? ": " + detail : ""))
        if (root.failedTopology === activeTopology) {
          root.failedAttempts += 1
        } else {
          root.failedTopology = activeTopology
          root.failedAttempts = 1
        }
        if (root.failedAttempts >= root.maxAttempts) {
          console.warn("Display profile failed " + root.failedAttempts + " times; not retrying until the connected displays change")
          Quickshell.execDetached(["omarchy-notification-send", "-g", "󰍺", "Display profile not applied", "Gave up after " + root.failedAttempts + " attempts"])
        }
      } else if (root.lastTopology !== activeTopology) {
        matchProc.handleResult(matchOutput.text)
      }
      if (root) root.pendingTopology = ""
    }
  }
}
