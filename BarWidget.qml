import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// WireGuard VPN toggle for a single NetworkManager-managed profile.
//
// All system work goes through bin/wireguard-vpn (nmcli underneath). The
// widget announces connect/disconnect/error with notifications, including
// changes made outside it. Left click opens the panel, right click toggles.
Panel {
  id: root
  moduleName: "wireguard"

  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("bin/wireguard-vpn")).replace(/^file:\/\//, ""))

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string glyphOn: "󰦝"
  readonly property string glyphOff: "󰒙"
  readonly property string glyphError: "󰻍"

  property var info: ({})
  property bool loaded: false
  property string lastError: ""
  property string confirmRemove: ""
  property bool _wasConnected: false
  property string _pendingAction: ""

  readonly property bool hasProfile: info.profile === "1"
  readonly property string vpnState: String(info.state || "")
  readonly property bool connected: vpnState === "activated"
  readonly property bool working: actionProc.running || vpnState === "activating" || vpnState === "deactivating"
  // Optimistic switch position while an action is in flight.
  readonly property bool switchOn: _pendingAction === "up" ? true : (_pendingAction === "down" ? false : connected)
  readonly property bool fullTunnel: info.fullTunnel === "1"
  readonly property bool awaitingReply: connected && Number(info.rx || 0) === 0

  readonly property string statusText: {
    if (!loaded) return "Checking…"
    if (!hasProfile) return "No profile imported"
    if (_pendingAction === "up" || vpnState === "activating") return "Connecting"
    if (_pendingAction === "down" || vpnState === "deactivating") return "Disconnecting"
    if (lastError !== "") return "Error"
    if (awaitingReply) return "Waiting for server"
    if (connected) return fullTunnel ? "Connected · all traffic" : "Connected · split tunnel"
    return "Disconnected"
  }

  readonly property string barGlyph: lastError !== "" && !connected ? glyphError : (switchOn ? glyphOn : glyphOff)
  readonly property color barColor: {
    var fg = bar ? bar.barForeground : Color.foreground
    if (lastError !== "" && !connected) return urgent
    return fg
  }

  // A bar exists per monitor; only the first instance announces connection
  // changes, so each one notifies once whoever caused it.
  function isLeader() {
    if (!bar || typeof bar.moduleWidgets !== "function") return true
    var items = bar.moduleWidgets(moduleName)
    return !items || items.length === 0 || items[0] === root
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function parseStatus(raw) {
    var next = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq > 0) next[lines[i].slice(0, eq)] = lines[i].slice(eq + 1)
    }
    var nowConnected = next.profile === "1" && next.state === "activated"
    if (loaded && nowConnected !== _wasConnected && isLeader()) {
      if (nowConnected) notify("-g", glyphOn, "VPN connected", String(next.name || ""))
      // Name the profile that was connected: replacing it swaps in a new one.
      else if (next.profile === "1") notify("-g", glyphOff, "VPN disconnected", String(info.name || next.name || ""))
    }
    _wasConnected = nowConnected
    info = next
    loaded = true
  }

  function notify() {
    var args = ["omarchy-notification-send", "--app-name", "WireGuard"]
    for (var i = 0; i < arguments.length; i++) args.push(String(arguments[i]))
    Quickshell.execDetached(args)
  }

  function run(action, extra) {
    if (actionProc.running) return
    lastError = ""
    confirmRemove = ""
    _pendingAction = action
    var cmd = [helper, action]
    if (extra) cmd.push(extra)
    actionProc.action = action
    actionProc.exited = false
    actionProc.errText = ""
    actionProc.command = cmd
    actionProc.running = true
  }

  function toggleVpn() {
    if (!hasProfile) { importProfile(); return }
    run(connected || vpnState === "activating" ? "down" : "up")
  }

  function importProfile() { run("import") }

  function removeProfile() {
    if (confirmRemove !== "remove") { confirmRemove = "remove"; return }
    run("remove")
  }

  function formatBytes(value) {
    var n = Number(value || 0)
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
    return (i === 0 ? n : n.toFixed(1)) + " " + units[i]
  }

  onOpenedChanged: {
    if (opened) refresh()
    else confirmRemove = ""
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: [root.helper, "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseStatus(text) }
  }

  Process {
    id: actionProc
    property string action: ""
    property int exitCode: 0
    property bool exited: false
    property string errText: ""

    function finish() {
      if (!exited || running) return
      if (exitCode !== 0) {
        root.lastError = errText || "Action failed"
        if (action === "up" || action === "down")
          root.notify("-u", "critical", "-g", root.glyphError,
                      action === "up" ? "VPN failed to connect" : "VPN failed to disconnect", root.lastError)
      }
      settleTimer.restart()
    }

    // Exit and stderr completion arrive in either order.
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: { actionProc.errText = String(text || "").trim(); actionProc.finish() }
    }
    onExited: function(code) { actionProc.exitCode = code; actionProc.exited = true; actionProc.finish() }
  }

  // Let NetworkManager settle, then drop the optimistic state and follow
  // what it reports.
  Timer {
    id: settleTimer
    interval: 400
    onTriggered: {
      root._pendingAction = ""
      statusProc.running = false
      root.refresh()
    }
  }

  // NetworkManager pushes every connection change; debounce and re-read.
  Process {
    id: monitorProc
    command: ["nmcli", "monitor"]
    running: true
    stdout: SplitParser { onRead: function(line) { debounce.restart() } }
    onExited: restartMonitor.restart()
  }

  Timer { id: restartMonitor; interval: 5000; onTriggered: monitorProc.running = true }
  Timer { id: debounce; interval: 300; onTriggered: if (!actionProc.running) root.refresh() }

  // Traffic counters only change in sysfs, so poll while the panel is open.
  Timer { interval: 2000; running: root.opened && root.connected; repeat: true; onTriggered: root.refresh() }
  // Slow fallback in case a monitor event is missed.
  Timer { interval: 60000; running: true; repeat: true; onTriggered: root.refresh() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barGlyph
    foreground: root.barColor
    tooltipText: root.opened ? "" : ((root.hasProfile ? String(root.info.name || "VPN") + ": " : "VPN: ") + root.statusText)
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleVpn()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }

    SequentialAnimation on opacity {
      running: root.working
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { from: 1.0; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.35; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.toggleVpn()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") root.toggleVpn()
        else if (t === "i" || t === "I") root.importProfile()
        else if (t === "r" || t === "R") root.refresh()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelHero {
          id: hero
          width: parent.width
          title: root.hasProfile ? String(root.info.name || "WireGuard") : "WireGuard"
          meta: root.statusText.toUpperCase()
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.switchOn ? 1.0 : 0.5
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.barGlyph
              color: root.lastError !== "" && !root.connected ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              id: powerSwitch
              visible: root.hasProfile
              checked: root.switchOn
              busy: actionProc.running
              foreground: root.foreground
              onToggled: root.toggleVpn()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.switchOn ? "Disconnect" : "Connect"
                fontFamily: root.fontFamily
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.lastError !== ""
          width: parent.width
          text: root.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          visible: root.loaded && !root.hasProfile
          width: parent.width
          text: "Import your WireGuard .conf file to get started. It is stored by NetworkManager and never connects on its own."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Column {
          visible: root.hasProfile
          width: parent.width
          spacing: Style.spacing.labelGap

          InfoPair { label: "Server"; value: root.info.endpoint || "—" }
          InfoPair { label: "Address"; value: root.info.address || "—" }
          InfoPair { label: "DNS"; value: root.info.dns || "—" }
          InfoPair { label: "Routing"; value: root.fullTunnel ? "All traffic" : "Split tunnel" }
          InfoPair { visible: root.connected; label: "Received"; value: root.formatBytes(root.info.rx) }
          InfoPair { visible: root.connected; label: "Sent"; value: root.formatBytes(root.info.tx) }
        }

        PanelSeparator { foreground: root.foreground }

        Row {
          id: actions
          width: parent.width
          spacing: Style.space(6)
          readonly property int count: root.hasProfile ? 2 : 1
          readonly property real cellWidth: (width - spacing * (count - 1)) / count

          Button {
            width: actions.cellWidth
            iconText: "󰈔"
            text: root.hasProfile ? "Replace profile" : "Import profile"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: !actionProc.running
            onClicked: root.importProfile()
          }

          Button {
            visible: root.hasProfile
            width: actions.cellWidth
            iconText: "󰆴"
            text: root.confirmRemove === "remove" ? "Confirm remove" : "Remove profile"
            fontSize: Style.font.bodySmall
            foreground: root.confirmRemove === "remove" ? root.urgent : root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: !actionProc.running
            onClicked: root.removeProfile()
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {
      id: pairLabel
      textFormat: Text.PlainText
      text: parent.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      textFormat: Text.PlainText
      text: parent.value
      width: parent.width - pairLabel.implicitWidth - parent.spacing
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideMiddle
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
