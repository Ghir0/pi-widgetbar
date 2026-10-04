import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.ghir0.pi-agent"
  ipcTarget: "io.github.ghir0.pi-agent"
  manageIpc: false

  readonly property string scriptPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.ghir0.pi-agent/status.py"

  property var snapshot: ({
    ok: false,
    status: "idle",
    sessions: [],
    activeSessions: [],
    latest: null,
    activeCount: 0,
    sessionCount: 0,
    workingCount: 0,
    needsResponseCount: 0,
    todayCount: 0
  })
  property bool refreshing: false
  property string readError: ""

  readonly property int refreshIntervalSec: {
    var n = parseInt(String(settings && settings.refreshIntervalSec !== undefined ? settings.refreshIntervalSec : 10), 10)
    return isFinite(n) ? Math.max(5, Math.min(120, n)) : 10
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property var activeSessions: root.snapshot.activeSessions || []

  readonly property color statusColor: {
    if (root.readError !== "" || root.activeSessions.length === 0)
      return Qt.rgba(0.60, 0.60, 0.60, 1)
    var s = root.snapshot.status || "idle"
    if (s === "working") return Qt.rgba(0.98, 0.80, 0.08, 1)
    if (s === "needs_response") return Qt.rgba(0.97, 0.44, 0.44, 1)
    return Qt.rgba(0.60, 0.60, 0.60, 1)
  }

  readonly property bool opened: root.controller.open

  // A bar-widget Panel needs explicit dimensions; otherwise its root Item can
  // have zero implicit size and the anchored icon is never visible.
  implicitWidth: barContent.implicitWidth
  implicitHeight: barContent.implicitHeight

  function refreshStatus() {
    if (!statusProcess.running) statusProcess.running = true
  }
  function open() {
    refreshStatus()
    root.controller.show()
  }
  function close() {
    root.controller.hide()
  }
  function toggle() {
    if (opened) close()
    else open()
  }

  function statusLabel() {
    if (!root.snapshot.ok) return "Pi Agent"
    if (root.activeSessions.length === 0) return "No active sessions"
    var parts = []
    if (root.snapshot.workingCount > 0) parts.push(root.snapshot.workingCount + " working")
    if (root.snapshot.needsResponseCount > 0) parts.push(root.snapshot.needsResponseCount + " waiting")
    return "Pi Agent \u00b7 " + parts.join(", ")
  }

  function shortStatusLabel() {
    var counts = { working: 0, needs_response: 0 }
    for (var i = 0; i < root.activeSessions.length; i++) {
      var status = root.activeSessions[i].status
      if (counts[status] !== undefined) counts[status]++
    }

    var labels = []
    if (counts.working > 0) labels.push("Working (" + counts.working + ")")
    if (counts.needs_response > 0) labels.push("Waiting (" + counts.needs_response + ")")
    return labels.join(" - ")
  }

  function formatAge(seconds) {
    if (seconds === null || seconds === undefined) return "unknown"
    if (seconds < 60) return seconds + "s ago"
    if (seconds < 3600) return Math.floor(seconds / 60) + "m ago"
    return Math.floor(seconds / 3600) + "h ago"
  }

  function formatTokenCount(value) {
    var n = Number(value || 0)
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
    if (n >= 1000) return (n / 1000).toFixed(1) + "K"
    return String(Math.round(n))
  }

  function formatCost(value) {
    var n = Number(value || 0)
    if (!isFinite(n)) return "—"
    return "$" + n.toFixed(n > 0 && n < 0.01 ? 4 : 2)
  }

  function tokenBreakdown(usage) {
    var u = usage || {}
    return "In " + root.formatTokenCount(u.input)
      + " · out " + root.formatTokenCount(u.output)
      + "\nCache read " + root.formatTokenCount(u.cacheRead)
      + " · write " + root.formatTokenCount(u.cacheWrite)
  }

  function sessionColor(status) {
    if (status === "working") return Qt.rgba(0.98, 0.80, 0.08, 1)
    if (status === "needs_response") return Qt.rgba(0.97, 0.44, 0.44, 1)
    return Qt.rgba(0.29, 0.87, 0.50, 1)
  }

  function shortCwd(cwd) {
    var parts = String(cwd || "").split("/").filter(function(x) { return x !== "" })
    return parts.slice(-2).join("/") || "Pi session"
  }

  // ------------------------------------------------------------------
  // Bar icon and current state label
  // ------------------------------------------------------------------
  Row {
    id: barContent
    spacing: Style.space(3)

    BarIconButton {
      id: button
      bar: root.bar
      text: "\u25cf"
      useActiveColor: false
      foreground: root.activeSessions.length > 0
        ? root.sessionColor(root.activeSessions[0].status) : root.statusColor
      active: false
      tooltipText: root.statusLabel()
      onPressed: function(buttonCode) {
        if (buttonCode === Qt.MiddleButton) root.refreshStatus()
        else root.toggle()
      }
    }

    Repeater {
      model: root.activeSessions.slice(1)
      delegate: Text {
        required property var modelData
        text: "\u25cf"
        textFormat: Text.PlainText
        color: root.sessionColor(modelData.status)
        font.family: root.bar ? root.bar.fontFamily : "sans-serif"
        font.pixelSize: Style.font.caption
        height: button.implicitHeight
        verticalAlignment: Text.AlignVCenter

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton) root.refreshStatus()
            else root.toggle()
          }
        }
      }
    }

    Text {
      visible: root.activeSessions.length > 0
      text: root.shortStatusLabel()
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.bar ? root.bar.fontFamily : "sans-serif"
      font.pixelSize: Style.font.caption
      height: button.implicitHeight
      verticalAlignment: Text.AlignVCenter

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.MiddleButton) root.refreshStatus()
          else root.toggle()
        }
      }
    }

  }

  Process {
    id: launchPiProcess
    command: ["omarchy", "launch", "tui", "pi"]
  }

  // ------------------------------------------------------------------
  // Data fetcher
  // ------------------------------------------------------------------
  Process {
    id: statusProcess
    command: ["/usr/bin/python3", root.scriptPath]
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.readError = "Could not read Pi sessions"
        return
      }
      try {
        root.snapshot = JSON.parse(statusOutput.text || "{}")
        root.readError = ""
      } catch (e) {
        root.readError = "Invalid Pi status data"
      }
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refreshStatus()
  }

  Component.onCompleted: refreshStatus()

  // ------------------------------------------------------------------
  // Popup panel
  // ------------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
    }

    Column {
      id: content
      // KeyboardPanel applies its own card padding and border insets. Use the
      // content holder's available width, not the outer panel width, so all
      // child text and rows stay inside the visible card.
      width: parent.width
      clip: true
      spacing: Style.space(12)

      // ---------- Header ----------
      Row {
        id: headerRow
        width: parent.width
        spacing: Style.space(10)

        Text {
          id: headerDot
          text: "\u25cf"
          textFormat: Text.PlainText
          color: root.statusColor
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.display
        }

        Column {
          id: headerTitle
          Text {
            text: "Pi Agent"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.bar ? root.bar.fontFamily : "sans-serif"
            font.pixelSize: Style.font.title
          }
          Text {
            text: root.readError || root.statusLabel()
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.bar ? root.bar.fontFamily : "sans-serif"
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          width: Math.max(0, headerRow.width - headerDot.implicitWidth
            - headerTitle.implicitWidth - popupLaunchButton.implicitWidth - Style.space(30))
          height: popupLaunchButton.implicitHeight
        }

        Button {
          id: popupLaunchButton
          text: "+"
          tooltipText: "Apri Pi in una nuova finestra"
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : "sans-serif"
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(3)
          bordered: true
          onClicked: if (!launchPiProcess.running) launchPiProcess.running = true
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
      }

      // ---------- Error ----------
      Text {
        visible: root.readError !== ""
        width: parent.width
        text: root.readError
        textFormat: Text.PlainText
        color: root.statusColor
        font.family: root.bar ? root.bar.fontFamily : "sans-serif"
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      // ---------- Active sessions ----------
      Text {
        visible: root.activeSessions.length > 0
        text: "Active sessions"
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.bar ? root.bar.fontFamily : "sans-serif"
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        visible: root.activeSessions.length === 0
        width: parent.width
        text: "Nessuna sessione attiva, costruiamo qualcosa insieme :D"
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.bar ? root.bar.fontFamily : "sans-serif"
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: root.activeSessions
        delegate: Column {
          required property var modelData
          required property int index
          width: content.width
          spacing: Style.space(4)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "\u25cf"
              textFormat: Text.PlainText
              color: root.sessionColor(modelData.status)
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: root.shortCwd(modelData.cwd) + " · "
                + (modelData.status === "working" ? "Working"
                  : modelData.status === "needs_response" ? "Waiting" : "Active")
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.bar ? root.bar.fontFamily : "sans-serif"
              font.pixelSize: Style.font.body
              elide: Text.ElideMiddle
              width: parent.width - Style.space(20)
            }
          }

          Text {
            text: {
              var parts = []
              if (modelData.model) parts.push(modelData.model)
              if (modelData.provider) parts.push(modelData.provider)
              if (modelData.thinkingLevel) parts.push("thinking: " + modelData.thinkingLevel)
              return parts.join(" · ")
            }
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.bar ? root.bar.fontFamily : "sans-serif"
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }

          Text {
            text: (modelData.messages || 0) + " messages · " + root.formatAge(modelData.ageSeconds)
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.bar ? root.bar.fontFamily : "sans-serif"
            font.pixelSize: Style.font.caption
          }

          Text {
            text: {
              var usage = modelData.tokens || {}
              return root.formatTokenCount(usage.totalTokens) + " tokens"
            }
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.bar ? root.bar.fontFamily : "sans-serif"
            font.pixelSize: Style.font.caption
            width: parent.width
            elide: Text.ElideRight
          }

          Text {
            text: "Session cost: " + (modelData.hasCost
              ? root.formatCost((modelData.cost || {}).total) : "not recorded")
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.bar ? root.bar.fontFamily : "sans-serif"
            font.pixelSize: Style.font.caption
            width: parent.width
            elide: Text.ElideRight
          }

          Rectangle {
            visible: index < root.activeSessions.length - 1
            width: parent.width
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
          }
        }
      }

      Rectangle {
        visible: root.activeSessions.length > 0
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
      }

      // ---------- Token usage ----------
      Column {
        width: parent.width
        spacing: Style.space(4)

        Text {
          text: "Token usage"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          text: "Today: " + root.formatTokenCount((root.snapshot.todayTokenUsage || {}).totalTokens) + " tokens"
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
        }
        Text {
          text: "All saved sessions: " + root.formatTokenCount((root.snapshot.tokenUsage || {}).totalTokens) + " tokens"
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
        }
        Text {
          text: "Cost today: " + (root.snapshot.todayHasCost
            ? root.formatCost((root.snapshot.todayCostUsage || {}).total) : "not recorded")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
        }
        Text {
          text: "Cost all saved sessions: " + (root.snapshot.hasCost
            ? root.formatCost((root.snapshot.costUsage || {}).total) : "not recorded")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
        }
        Text {
          text: root.tokenBreakdown(root.snapshot.tokenUsage)
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
          width: parent.width
          wrapMode: Text.WordWrap
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
      }

      // ---------- Stats ----------
      Flow {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "Sessions: " + root.snapshot.sessionCount
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
        }
        Text {
          text: "Today: " + root.snapshot.todayCount
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
        }
        Text {
          visible: root.snapshot.activeCount > 0
          text: "Active: " + root.snapshot.activeCount
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
        }
      }

      // ---------- Footer ----------
      Text {
        visible: false
        width: parent.width
        text: "Sessions are read locally; prompt contents are not displayed."
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.bar ? root.bar.fontFamily : "sans-serif"
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
    }
  }
}
