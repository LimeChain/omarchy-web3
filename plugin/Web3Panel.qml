import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "limechain.web3"
  ipcTarget: "limechain.web3"
  manageIpc: false

  property var report: ({
    chain: { name: "Web3", ok: false, block_height: null, gas_gwei: null, base_fee_gwei: null },
    local: { ok: false, service_active: false, block_height: null }
  })
  property string lastError: ""
  property bool refreshing: false
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/limechain-web3"
  readonly property int refreshSeconds: Math.max(5, parseInt(setting("refreshIntervalSec", 15), 10) || 15)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool chainHealthy: report.chain && report.chain.ok === true
  readonly property bool localHealthy: report.local && report.local.ok === true
  readonly property bool anvilActive: report.local && report.local.service_active === true
  readonly property string barText: {
    if (chainHealthy && report.chain.block_height !== null)
      return "⬡ " + compactNumber(report.chain.block_height)
    if (localHealthy && report.local.block_height !== null)
      return "A " + compactNumber(report.local.block_height)
    return "⬡"
  }

  function compactNumber(value) {
    var n = Number(value)
    if (!isFinite(n)) return "—"
    if (n >= 1000000) return (n / 1000000).toFixed(2) + "m"
    if (n >= 1000) return (n / 1000).toFixed(1) + "k"
    return String(n)
  }

  function display(value, suffix) {
    if (value === null || value === undefined || value === "") return "—"
    return String(value) + (suffix || "")
  }

  function refresh() {
    if (statusProc.running) return
    lastError = ""
    refreshing = true
    statusProc.running = true
  }

  function runAnvil(action) {
    if (actionProc.running) return
    actionProc.command = [root.cli, "anvil", action]
    actionProc.running = true
  }

  function openLatestBlock() {
    if (!chainHealthy || report.chain.block_height === null || explorerProc.running) return
    explorerProc.command = [root.cli, "open-explorer", "block", String(report.chain.block_height)]
    explorerProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) refresh()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function status(): string { return JSON.stringify(root.report) }
  }

  Process {
    id: statusProc
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          var parsed = JSON.parse(raw)
          if (parsed && parsed.chain && parsed.local) root.report = parsed
          root.lastError = ""
        } catch (error) {
          root.lastError = "Invalid workstation status"
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw) root.lastError = raw.split("\n")[0]
      }
    }
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode !== 0 && root.lastError === "") root.lastError = "Status command failed"
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw) root.lastError = raw.split("\n")[0]
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.lastError === "") root.lastError = "Anvil action failed"
      Qt.callLater(root.refresh)
    }
  }

  Process { id: explorerProc }

  Timer {
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    slotSize: root.chainHealthy ? Style.bar.statusSlot : Style.bar.iconSlot
    tooltipText: root.chainHealthy ? root.report.chain.name + " read-only status" : "Web3 Workstation"
    active: root.localHealthy
    onPressed: function(code) {
      if (code === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)

        PanelHero {
          width: parent.width
          title: report.chain ? report.chain.name : "Web3 Workstation"
          meta: root.chainHealthy ? "Read-only chain telemetry" : "Remote RPC not configured"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "⬡"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          visible: root.lastError !== ""
          width: parent.width
          text: root.lastError
          textFormat: Text.PlainText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSectionHeader {
          text: "REMOTE CHAIN"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        InfoPair { label: "Status"; value: root.chainHealthy ? "healthy" : "unavailable" }
        InfoPair { label: "Block"; value: root.display(report.chain ? report.chain.block_height : null, "") }
        InfoPair { label: "Gas"; value: root.display(report.chain ? report.chain.gas_gwei : null, " gwei") }
        InfoPair { label: "Base fee"; value: root.display(report.chain ? report.chain.base_fee_gwei : null, " gwei") }

        Button {
          visible: root.chainHealthy && report.chain && report.chain.explorer_url !== ""
          text: "Open latest block"
          iconText: "󰖟"
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.openLatestBlock()
        }

        PanelSeparator { foreground: root.foreground }

        PanelSectionHeader {
          text: "LOCAL ANVIL"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        InfoPair { label: "Service"; value: root.anvilActive ? "active" : "inactive" }
        InfoPair { label: "RPC"; value: root.localHealthy ? "healthy" : "offline" }
        InfoPair { label: "Block"; value: root.display(report.local ? report.local.block_height : null, "") }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "Start"
            iconText: "󰐊"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !root.anvilActive && !actionProc.running
            bordered: true
            Layout.fillWidth: true
            onClicked: root.runAnvil("start")
          }
          Button {
            text: "Stop"
            iconText: "󰓛"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: root.anvilActive && !actionProc.running
            bordered: true
            Layout.fillWidth: true
            onClicked: root.runAnvil("stop")
          }
          Button {
            text: "Reset"
            iconText: "󰑐"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: root.anvilActive && !actionProc.running
            bordered: true
            Layout.fillWidth: true
            onClicked: root.runAnvil("reset")
          }
        }

        Text {
          width: parent.width
          text: "No accounts, signing, keys, or transaction submission. Right-click the bar widget to refresh."
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
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
      text: parent.label
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text {
      text: parent.value
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
