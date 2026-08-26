import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  property bool opened: false
  property string side: "right"
  property int panelWidth: 420
  property string screenName: ""
  property bool resizing: false
  property real resizeGrabX: 0
  readonly property int minWidth: 280
  readonly property int maxWidth: 900
  readonly property int handleWidth: 8

  readonly property string pluginDir: String((root.manifest && root.manifest.__sourceDir) || "")

  readonly property var targetScreen: {
    var want = String(root.screenName || "")
    var focused = focusedScreenName()
    var screens = Quickshell.screens
    var match = null
    var focusedMatch = null
    for (var i = 0; i < screens.length; i++) {
      var name = String(screens[i].name || "")
      if (name === want) match = screens[i]
      if (name === focused) focusedMatch = screens[i]
    }
    return match || focusedMatch || (screens.length > 0 ? screens[0] : null)
  }

  function applySettings(settings) {
    if (!settings) return
    if (settings.side === "left" || settings.side === "right") root.side = settings.side
    if (settings.width !== undefined && settings.width !== null) {
      var n = Math.round(Number(settings.width))
      if (isFinite(n) && n > 0) root.panelWidth = n
    }
    if (root.opened) root.placeWeb("show")
  }

  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    if (monitor && monitor.name) return String(monitor.name)
    var screens = Quickshell.screens
    return screens.length > 0 ? String(screens[0].name) : ""
  }

  function screenNameFromItem(item) {
    if (!item) return ""
    try {
      var win = item.QsWindow ? item.QsWindow.window : null
      if (win && win.screen && win.screen.name) return String(win.screen.name)
    } catch (e) {}
    return ""
  }

  function openFrom(item) {
    var name = screenNameFromItem(item)
    if (name) root.screenName = name
    open()
  }

  function open() {
    if (!root.screenName) root.screenName = focusedScreenName()
    root.opened = true
    root.ensureWeb()
    root.placeWeb("show")
  }

  function close() {
    root.opened = false
    root.placeWeb("hide")
  }
  function toggle() { root.opened ? close() : open() }

  function cycleSide() {
    root.side = root.side === "right" ? "left" : "right"
    if (root.opened) root.placeWeb("show")
  }

  function clampWidth(value) {
    var screenW = dockWidth()
    var cap = Math.min(root.maxWidth, Math.floor(screenW * 0.5))
    return Util.clamp(Math.round(Number(value) || root.minWidth), root.minWidth, cap)
  }

  function hyprMonitor() {
    try {
      if (window.screen) return Hyprland.monitorFor(window.screen)
    } catch (e) {}
    return null
  }

  function dockX() {
    var mon = hyprMonitor()
    if (mon) return mon.x
    return root.targetScreen ? root.targetScreen.x : 0
  }

  function dockWidth() {
    var mon = hyprMonitor()
    if (mon) return mon.width
    return root.targetScreen ? root.targetScreen.width : 1920
  }

  function barReserve() {
    var mon = hyprMonitor()
    try {
      var r = mon && mon.lastIpcObject ? mon.lastIpcObject.reserved : null
      var top = r ? Number(r[1]) : 0
      if (isFinite(top) && top > 0) return Math.round(top)
    } catch (e) {}
    return 24
  }

  function widthForCursorX(cursorX) {
    if (root.side === "right")
      return clampWidth((dockX() + dockWidth()) - cursorX + root.resizeGrabX)
    return clampWidth(cursorX - dockX() + root.handleWidth - root.resizeGrabX)
  }

  function applyCursorJson(text) {
    if (!root.resizing) return
    var pos
    try { pos = JSON.parse(String(text || "")) } catch (e) { return }
    var x = Number(pos && pos.x)
    if (!isFinite(x)) return
    var next = root.widthForCursorX(x)
    if (next !== root.panelWidth) {
      root.panelWidth = next
      root.placeWeb("show")
    }
  }

  function ensureWeb() {
    if (!root.pluginDir) return
    webProc.command = [root.pluginDir + "/webview/launch.sh"]
    if (!webProc.running) webProc.running = true
  }

  function placeWeb(mode) {
    if (!root.pluginDir) return
    placeProc.command = [root.pluginDir + "/webview/place.sh", mode || (root.opened ? "show" : "hide"),
                         String(root.screenName || ""), root.side, String(root.panelWidth)]
    placeProc.running = false
    placeProc.running = true
  }

  onManifestChanged: if (root.pluginDir) root.ensureWeb()
  Component.onDestruction: {
    webProc.running = false
  }

  onOpenedChanged: {
    if (root.opened) {
      root.ensureWeb()
      placeRetry.tries = 0
      placeRetry.running = true
    } else {
      placeRetry.running = false
      root.placeWeb("hide")
    }
  }

  onSideChanged: if (root.opened) root.placeWeb("show")
  onPanelWidthChanged: if (root.opened && !root.resizing) root.placeWeb("show")
  onScreenNameChanged: if (root.opened) root.placeWeb("show")

  Process {
    id: webProc
    command: ["true"]
  }

  Process {
    id: placeProc
    command: ["true"]
  }

  Timer {
    id: placeRetry
    interval: 150
    repeat: true
    property int tries: 0
    onTriggered: {
      tries += 1
      root.placeWeb("show")
      if (tries >= 20) running = false
    }
  }

  Process {
    id: cursorProbe
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyCursorJson(text)
    }
    onExited: {
      if (root.resizing) running = true
    }
  }

  IpcHandler {
    target: "online.izz0.omarchy.grok-panel"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function ping(): string { return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
  }

  // 1px Top-layer exclusive-zone request. A full-width Top surface covered
  // grok.com; a Bottom exclusive zone also inset the Omarchy bar.
  PanelWindow {
    id: window
    screen: root.targetScreen
    visible: root.opened
    implicitWidth: 1
    color: Qt.rgba(0, 0, 0, 0)
    surfaceFormat.opaque: false
    exclusiveZone: root.opened ? root.panelWidth : 0
    exclusionMode: ExclusionMode.Normal
    aboveWindows: true
    WlrLayershell.namespace: "omarchy-grok"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    anchors {
      top: true
      bottom: true
      left: root.side === "left"
      right: root.side === "right"
    }

    margins {
      top: root.barReserve()
    }
  }

  PanelWindow {
    id: handleWindow
    screen: root.targetScreen
    visible: root.opened
    implicitWidth: root.handleWidth
    color: "transparent"
    surfaceFormat.opaque: false
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    WlrLayershell.namespace: "omarchy-grok-handle"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: root.side === "left"
      right: root.side === "right"
    }

    margins {
      top: root.barReserve()
    }

    Rectangle {
      id: resizeHandle
      anchors.fill: parent
      color: "#ff0000"

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.SizeHorCursor
        preventStealing: true

        onPressed: function(mouse) {
          root.resizeGrabX = mouse.x
          root.resizing = true
          cursorProbe.running = true
        }
        onReleased: {
          root.resizing = false
          if (root.opened) root.placeWeb("show")
        }
        onCanceled: root.resizing = false
      }
    }
  }
}
