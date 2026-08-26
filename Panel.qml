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
  }

  function close() { root.opened = false }
  function toggle() { root.opened ? close() : open() }

  function cycleSide() {
    root.side = root.side === "right" ? "left" : "right"
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

  // hyprctl cursorpos is compositor layout X. Window-local mouse X moves with
  // exclusiveZone, so it cannot be used as a drag delta.
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
    root.panelWidth = root.widthForCursorX(x)
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

  PanelWindow {
    id: window
    screen: root.targetScreen
    visible: root.opened
    implicitWidth: root.panelWidth
    color: Color.popups.background
    exclusiveZone: root.opened ? root.panelWidth : 0
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.namespace: "omarchy-grok"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: root.side === "left"
      right: root.side === "right"
    }

    Item {
      id: content
      anchors.fill: parent

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(16) + (root.side === "right" ? root.handleWidth : 0)
        anchors.rightMargin: Style.space(16) + (root.side === "left" ? root.handleWidth : 0)
        text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Math.max(12, Style.font.body)
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
      }

      Rectangle {
        id: resizeHandle
        z: 10
        width: root.handleWidth
        height: parent.height
        y: 0
        x: root.side === "right" ? 0 : parent.width - width
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
          onReleased: root.resizing = false
          onCanceled: root.resizing = false
        }
      }
    }
  }
}
