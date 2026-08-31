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
    local: { installed: true, ok: false, service_active: false, block_height: null },
    solana: { installed: false, ok: false, service_active: false, slot: null, version: null, surfpool_version: null, mode: "offline" }
  })
  property string lastError: ""
  property bool refreshing: false
  property string anvilAction: ""
  property string surfpoolAction: ""
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/limechain-web3"
  readonly property int refreshSeconds: Math.max(5, parseInt(setting("refreshIntervalSec", 15), 10) || 15)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool chainHealthy: report.chain && report.chain.ok === true
  readonly property bool chainConfigured: report.chain && report.chain.configured === true
  readonly property bool localHealthy: report.local && report.local.ok === true
  readonly property bool evmInstalled: report.local && report.local.installed !== false
  readonly property bool anvilActive: report.local && report.local.service_active === true
  readonly property bool solanaInstalled: report.solana && report.solana.installed === true
  readonly property bool solanaHealthy: report.solana && report.solana.ok === true
  readonly property bool surfpoolActive: report.solana && report.solana.service_active === true
  readonly property string barText: {
    if (localHealthy && solanaHealthy)
      return "A " + compactNumber(report.local.block_height) + " · S " + compactNumber(report.solana.slot)
    if (chainHealthy && report.chain.block_height !== null)
      return "⬡ " + compactNumber(report.chain.block_height)
    if (localHealthy && report.local.block_height !== null)
      return "A " + compactNumber(report.local.block_height)
    if (solanaHealthy && report.solana.slot !== null)
      return "S " + compactNumber(report.solana.slot)
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
    if (actionProc.running || anvilAction !== "") return
    anvilAction = action
    lastError = ""
    actionProc.command = [root.cli, "anvil", action]
    actionProc.running = true
    actionTimeout.restart()
  }

  function completeAnvilAction() {
    anvilAction = ""
    actionTimeout.stop()
  }

  function runSurfpool(action) {
    if (surfpoolActionProc.running || surfpoolAction !== "") return
    surfpoolAction = action
    lastError = ""
    surfpoolActionProc.command = [root.cli, "surfpool", action]
    surfpoolActionProc.running = true
    surfpoolActionTimeout.restart()
  }

  function completeSurfpoolAction() {
    surfpoolAction = ""
    surfpoolActionTimeout.stop()
  }

  function localServiceLabel() {
    if (anvilAction === "start") return "starting…"
    if (anvilAction === "stop") return "stopping…"
    if (anvilAction === "reset") return "resetting…"
    return anvilActive ? "active" : "stopped"
  }

  function surfpoolServiceLabel() {
    if (surfpoolAction === "start") return "starting…"
    if (surfpoolAction === "stop") return "stopping…"
    if (surfpoolAction === "reset") return "resetting…"
    return surfpoolActive ? "active" : "stopped"
  }

  function openRemoteGuide() {
    if (guideProc.running) return
    guideProc.command = ["omarchy-launch-floating-terminal-with-presentation", root.cli + " remote-guide --wait"]
    guideProc.running = true
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
          if (parsed && parsed.chain && parsed.local && parsed.solana) {
            root.report = parsed
            if ((root.anvilAction === "start" && parsed.local.service_active === true)
                || (root.anvilAction === "stop" && parsed.local.service_active === false))
              root.completeAnvilAction()
            if (((root.surfpoolAction === "start" || root.surfpoolAction === "reset")
                  && parsed.solana.service_active === true && parsed.solana.ok === true)
                || (root.surfpoolAction === "stop" && parsed.solana.service_active === false))
              root.completeSurfpoolAction()
          }
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
      if (exitCode !== 0) {
        if (root.lastError === "") root.lastError = "Anvil action failed"
        root.completeAnvilAction()
      } else if (root.anvilAction === "reset") {
        root.completeAnvilAction()
      }
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: surfpoolActionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw) root.lastError = raw.split("\n")[0]
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        if (root.lastError === "") root.lastError = "Surfpool action failed"
        root.completeSurfpoolAction()
      }
      Qt.callLater(root.refresh)
    }
  }

  Process { id: explorerProc }
  Process { id: guideProc }

  Timer {
    id: actionPoll
    interval: 300
    running: root.anvilAction !== "" || root.surfpoolAction !== ""
    repeat: true
    onTriggered: root.refresh()
  }


  Timer {
    id: surfpoolActionTimeout
    interval: 12000
    repeat: false
    onTriggered: {
      root.lastError = "Surfpool did not reach the expected state"
      root.completeSurfpoolAction()
      root.refresh()
    }
  }

  Timer {
    id: actionTimeout
    interval: 8000
    repeat: false
    onTriggered: {
      root.lastError = "Anvil did not reach the expected state"
      root.completeAnvilAction()
      root.refresh()
    }
  }

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
    slotSize: root.chainHealthy || root.localHealthy || root.solanaHealthy ? Style.bar.statusSlot : Style.bar.iconSlot
    tooltipText: root.localHealthy && root.solanaHealthy
      ? "Anvil block " + root.display(root.report.local.block_height, "") + " · Surfpool slot " + root.display(root.report.solana.slot, "")
      : root.localHealthy ? "Local Anvil · block " + root.display(root.report.local.block_height, "")
      : root.solanaHealthy ? "Offline Surfpool · slot " + root.display(root.report.solana.slot, "")
      : root.chainHealthy ? root.report.chain.name + " read-only status" : "Web3 Workstation · stopped"
    active: root.localHealthy || root.solanaHealthy
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
          title: root.localHealthy && root.solanaHealthy ? "Web3 Workstation"
            : root.localHealthy ? "Local Anvil"
            : root.solanaHealthy ? "Local Surfpool"
            : root.chainHealthy ? root.report.chain.name : "Web3 Workstation"
          meta: root.localHealthy && root.solanaHealthy ? "EVM + Solana local runtimes ready"
            : root.localHealthy ? "Local development RPC ready · chain 31337"
            : root.solanaHealthy ? "Offline Solana RPC ready · slot " + root.display(root.report.solana.slot, "")
            : root.chainHealthy ? "Read-only remote observer" : "Start a local chain when you need it"
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
          text: "REMOTE OBSERVER (OPTIONAL)"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          visible: !root.chainConfigured
          width: parent.width
          text: "Not connected by default. Local Anvil works independently, and no external service is contacted."
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Button {
          visible: !root.chainConfigured
          text: "Show remote setup guide"
          iconText: "󰒓"
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.openRemoteGuide()
        }

        InfoPair { visible: root.chainConfigured; label: "Status"; value: root.chainHealthy ? "healthy" : "offline" }
        InfoPair { visible: root.chainConfigured; label: "Chain ID"; value: root.display(report.chain ? report.chain.chain_id : null, "") }
        InfoPair { visible: root.chainConfigured; label: "Block"; value: root.display(report.chain ? report.chain.block_height : null, "") }
        InfoPair { visible: root.chainConfigured; label: "Gas"; value: root.display(report.chain ? report.chain.gas_gwei : null, " gwei") }
        InfoPair { visible: root.chainConfigured; label: "Base fee"; value: root.display(report.chain ? report.chain.base_fee_gwei : null, " gwei") }

        Button {
          visible: root.chainHealthy && report.chain && report.chain.explorer_url !== ""
          text: "Open latest block"
          iconText: "󰖟"
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.openLatestBlock()
        }

        PanelSeparator { visible: root.evmInstalled; foreground: root.foreground }

        PanelSectionHeader {
          visible: root.evmInstalled
          text: "LOCAL ANVIL"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        InfoPair { visible: root.evmInstalled; label: "Service"; value: root.localServiceLabel() }
        InfoPair { visible: root.evmInstalled; label: "RPC"; value: root.anvilAction !== "" ? "checking…" : root.localHealthy ? "healthy" : "offline" }
        InfoPair { visible: root.evmInstalled; label: "Chain ID"; value: root.display(report.local ? report.local.chain_id : null, "") }
        InfoPair { visible: root.evmInstalled; label: "Block"; value: root.display(report.local ? report.local.block_height : null, "") }
        InfoPair { visible: root.evmInstalled; label: "Gas"; value: root.display(report.local ? report.local.gas_gwei : null, " gwei") }

        RowLayout {
          visible: root.evmInstalled
          width: parent.width
          spacing: Style.space(8)

          Button {
            visible: !root.anvilActive && root.anvilAction === ""
            text: "Start local Anvil"
            iconText: "󰐊"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            Layout.fillWidth: true
            onClicked: root.runAnvil("start")
          }
          Button {
            visible: root.anvilAction === "start"
            text: "Starting…"
            iconText: "󰑐"
            iconSpinning: true
            foreground: root.dim
            fontFamily: root.fontFamily
            bordered: true
            Layout.fillWidth: true
          }
          Button {
            visible: root.anvilActive && root.anvilAction === ""
            text: "Stop"
            iconText: "󰓛"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            Layout.fillWidth: true
            onClicked: root.runAnvil("stop")
          }
          Button {
            visible: root.anvilActive && root.anvilAction === ""
            text: "Reset"
            iconText: "󰑐"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            Layout.fillWidth: true
            onClicked: root.runAnvil("reset")
          }
          Button {
            visible: root.anvilAction === "stop" || root.anvilAction === "reset"
            text: root.anvilAction === "stop" ? "Stopping…" : "Resetting…"
            iconText: "󰑐"
            iconSpinning: true
            foreground: root.dim
            fontFamily: root.fontFamily
            bordered: true
            Layout.fillWidth: true
          }
        }

        Text {
          visible: root.evmInstalled
          width: parent.width
          text: "Account-free local RPC. No signing, keys, or transaction submission. Right-click the bar widget to refresh."
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { visible: root.solanaInstalled; foreground: root.foreground }

        PanelSectionHeader {
          visible: root.solanaInstalled
          text: "LOCAL SURFPOOL · SOLANA"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        InfoPair { visible: root.solanaInstalled; label: "Service"; value: root.surfpoolServiceLabel() }
        InfoPair { visible: root.solanaInstalled; label: "RPC"; value: root.surfpoolAction !== "" ? "checking…" : root.solanaHealthy ? "healthy" : "offline" }
        InfoPair { visible: root.solanaInstalled; label: "Mode"; value: "offline · loopback only" }
        InfoPair { visible: root.solanaInstalled; label: "Slot"; value: root.display(report.solana ? report.solana.slot : null, "") }
        InfoPair { visible: root.solanaInstalled; label: "Surfpool"; value: root.display(report.solana ? report.solana.surfpool_version : null, "") }
        InfoPair { visible: root.solanaInstalled; label: "Solana core"; value: root.display(report.solana ? report.solana.version : null, "") }

        RowLayout {
          visible: root.solanaInstalled
          width: parent.width
          spacing: Style.space(8)

          Button {
            visible: !root.surfpoolActive && root.surfpoolAction === ""
            text: "Start offline Surfpool"
            iconText: "󰐊"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            Layout.fillWidth: true
            onClicked: root.runSurfpool("start")
          }
          Button {
            visible: root.surfpoolAction === "start"
            text: "Starting…"
            iconText: "󰑐"
            iconSpinning: true
            foreground: root.dim
            fontFamily: root.fontFamily
            bordered: true
            Layout.fillWidth: true
          }
          Button {
            visible: root.surfpoolActive && root.surfpoolAction === ""
            text: "Stop"
            iconText: "󰓛"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            Layout.fillWidth: true
            onClicked: root.runSurfpool("stop")
          }
          Button {
            visible: root.surfpoolActive && root.surfpoolAction === ""
            text: "Reset"
            iconText: "󰑐"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            Layout.fillWidth: true
            onClicked: root.runSurfpool("reset")
          }
          Button {
            visible: root.surfpoolAction === "stop" || root.surfpoolAction === "reset"
            text: root.surfpoolAction === "stop" ? "Stopping…" : "Resetting…"
            iconText: "󰑐"
            iconSpinning: true
            foreground: root.dim
            fontFamily: root.fontFamily
            bordered: true
            Layout.fillWidth: true
          }
        }

        Text {
          visible: root.solanaInstalled
          width: parent.width
          text: "Offline, loopback-only runtime. No wallet, key, remote datasource, signing, or transaction submission through this plugin."
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
