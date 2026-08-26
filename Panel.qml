import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

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
  readonly property int toolbarHeight: 32
  readonly property string pinOutline: "󰤱"
  readonly property string pinFilled: "󰐃"
  readonly property string refreshIcon: "󰑓"
  property bool pickerOpen: false
  property var chatList: []
  property string defaultChatUrl: "https://grok.com"
  property string defaultChatTitle: "New chat"
  property string defaultChatSection: ""
  property string currentChatUrl: ""
  property string currentChatTitle: "New chat"
  property string currentChatSection: ""
  property string urlDraft: ""
  property bool userPickedDefault: false
  property bool hasSavedDefault: false
  property bool autoDefaultApplied: false
  property var preferredProject: null

  readonly property string pluginDir: String((root.manifest && root.manifest.__sourceDir) || "")
  readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share"))
                                    + "/online.izz0.omarchy.grok-panel"

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
    root.pickerOpen = false
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

  function dockHeight() {
    var mon = hyprMonitor()
    if (mon) return mon.height
    return root.targetScreen ? root.targetScreen.height : 1080
  }

  function panelHeight() {
    var mon = hyprMonitor()
    var bottom = 0
    try {
      var r = mon && mon.lastIpcObject ? mon.lastIpcObject.reserved : null
      var b = r ? Number(r[3]) : 0
      if (isFinite(b) && b > 0) bottom = Math.round(b)
    } catch (e) {}
    return Math.max(1, dockHeight() - barReserve() - bottom)
  }

  readonly property int pickerHeight: {
    var panel = panelHeight()
    return Math.max(160, Math.min(Math.floor(panel * 0.75), panel - toolbarHeight))
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
    var args = [root.pluginDir + "/webview/launch.sh"]
    var url = root.currentChatUrl || root.defaultChatUrl
    if (root.currentChatUrl)
      args.push(root.currentChatUrl)
    else if (url && !root.isHomepage(url))
      args.push(url)
    webProc.command = args
    if (!webProc.running) webProc.running = true
  }

  function placeWeb(mode) {
    if (!root.pluginDir) return
    placeProc.command = [root.pluginDir + "/webview/place.sh", mode || (root.opened ? "show" : "hide"),
                         String(root.screenName || ""), root.side, String(root.panelWidth),
                         String(root.toolbarHeight)]
    placeProc.running = false
    placeProc.running = true
  }

  function normalizeChatUrl(value) {
    var s = String(value || "").trim()
    if (!s) return ""
    if (s.indexOf("http://") === 0 || s.indexOf("https://") === 0) return s
    if (s.indexOf("/c/") === 0) return "https://grok.com" + s
    if (s.indexOf("grok.com/") >= 0) return s.indexOf("https://") === 0 ? s : "https://" + s.replace(/^\/+/, "")
    return "https://grok.com/c/" + s.replace(/^\/+/, "")
  }

  function urlsMatch(a, b) {
    function clean(value) {
      return String(value || "").split("?")[0].split("#")[0].replace(/\/+$/, "")
    }
    var left = clean(a)
    var right = clean(b)
    return left !== "" && left === right
  }

  function isProjectSection(section) {
    var s = String(section || "").trim()
    return s !== "" && s !== "Other chats" && s !== "Projects"
  }

  function displayLabel(title, section) {
    var label = String(title || "").trim() || "New chat"
    var project = String(section || "").trim()
    if (root.isProjectSection(project)) return project + " \\ " + label
    return label
  }

  function lookupChat(url, title, section) {
    var href = root.normalizeChatUrl(url)
    var label = String(title || "").trim()
    var proj = String(section || "").trim()
    if (!href) return null
    for (var i = 0; i < root.chatList.length; i++) {
      var item = root.chatList[i]
      if (!item || !root.urlsMatch(item.url, href)) continue
      if (!label || label.indexOf("http://") === 0 || label.indexOf("https://") === 0)
        label = String(item.title || "")
      if (!proj) proj = String(item.section || "")
      break
    }
    if (!label || label.indexOf("http://") === 0 || label.indexOf("https://") === 0) {
      if (root.isHomepage(href)) label = "New chat"
      else label = href.replace(/^https:\/\/grok\.com\/c\//, "")
    }
    return { url: href, title: label, section: proj }
  }

  function loadChat(url, title, section) {
    var chat = root.lookupChat(url, title, section)
    if (!chat) return
    root.currentChatUrl = chat.url
    root.currentChatTitle = chat.title
    root.currentChatSection = chat.section
    root.pickerOpen = false
    webProc.running = false
    reloadWebTimer.restart()
  }

  function saveDefault(url, title, section) {
    var chat = root.lookupChat(url, title, section)
    if (!chat) return
    root.defaultChatUrl = chat.url
    root.defaultChatTitle = chat.title
    root.defaultChatSection = chat.section
    root.hasSavedDefault = !root.isHomepage(chat.url)
    root.userPickedDefault = true
    if (root.pluginDir)
      saveDefaultProc.exec(["python3", root.pluginDir + "/webview/save-default.py", chat.url, chat.title, chat.section])
  }

  function applyDefaultChat(url, title, section) {
    root.saveDefault(url, title, section)
    root.loadChat(url, title, section)
  }

  function requestChatRefresh() {
    if (!root.pluginDir) return
    refreshProc.exec(["python3", root.pluginDir + "/webview/request-refresh.py"])
  }

  function applyRefreshedCurrent(data, list) {
    var href = String((data && data.current) || "").split("?")[0].split("#")[0]
    if (!href) return
    var title = String((data && data.currentTitle) || "").trim()
    var section = String((data && data.currentSection) || "").trim()
    for (var i = 0; i < list.length; i++) {
      var item = list[i]
      if (!item || !root.urlsMatch(item.url, href)) continue
      href = String(item.url || href)
      if (item.title) title = String(item.title)
      if (item.section) section = String(item.section)
      break
    }
    if (!title) title = root.isHomepage(href) ? "New chat" : href.replace(/^https:\/\/grok\.com\/c\//, "")
    root.currentChatUrl = href
    root.currentChatTitle = title
    root.currentChatSection = section
  }

  function isHomepage(url) {
    var s = String(url || "").replace(/\/+$/, "")
    return s === "" || s === "https://grok.com" || s === "http://grok.com"
  }

  function isPanelProjectTitle(title) {
    var key = String(title || "").toLowerCase().replace(/[^a-z0-9]+/g, "")
    return key === "sidepanel" || key === "grokpanel"
  }

  function findPreferredProject(list) {
    if (root.preferredProject && root.preferredProject.url) return root.preferredProject
    var sidepanel = null
    var grokpanel = null
    for (var i = 0; i < list.length; i++) {
      var item = list[i]
      if (!item || String(item.url || "").indexOf("/project/") < 0) continue
      var label = String(item.section || item.title || "")
      if (!root.isPanelProjectTitle(label)) continue
      var key = label.toLowerCase().replace(/[^a-z0-9]+/g, "")
      if (key === "sidepanel" && !sidepanel) sidepanel = item
      if (key === "grokpanel" && !grokpanel) grokpanel = item
    }
    return sidepanel || grokpanel || null
  }

  function maybeAutoDefault() {
    if (root.autoDefaultApplied || root.userPickedDefault || root.hasSavedDefault) return
    var pref = root.findPreferredProject(root.chatList)
    if (!pref || !pref.url) return
    root.autoDefaultApplied = true
    root.preferredProject = pref
    if (root.defaultChatUrl === pref.url) {
      if (root.pluginDir)
        saveDefaultProc.exec(["python3", root.pluginDir + "/webview/save-default.py", pref.url, pref.title || "Sidepanel"])
      return
    }
    root.applyDefaultChat(pref.url, pref.title || "Sidepanel")
  }

  function parseChats(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      var list = data.chats || []
      var out = []
      for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].url) out.push(list[i])
      }
      root.chatList = out
      if (data.current) root.urlDraft = String(data.current)
      if (data.preferredProject && data.preferredProject.url)
        root.preferredProject = data.preferredProject
      for (var j = 0; j < out.length; j++) {
        var item = out[j]
        if (!item) continue
        if (!root.defaultChatSection && root.urlsMatch(item.url, root.defaultChatUrl))
          root.defaultChatSection = String(item.section || "")
        if (!root.currentChatSection && root.urlsMatch(item.url, root.currentChatUrl || root.defaultChatUrl)) {
          root.currentChatSection = String(item.section || "")
          if (!root.currentChatTitle || root.currentChatTitle === "New chat")
            root.currentChatTitle = String(item.title || root.currentChatTitle)
          if (!root.currentChatUrl) root.currentChatUrl = String(item.url || "")
        }
      }
      if (data.refreshed)
        root.applyRefreshedCurrent(data, out)
      root.maybeAutoDefault()
    } catch (e) {
      root.chatList = []
    }
  }

  function parseDefault(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      if (data.url) {
        root.defaultChatUrl = String(data.url)
        root.hasSavedDefault = !root.isHomepage(data.url)
      }
      if (data.title) root.defaultChatTitle = String(data.title)
      if (data.section) root.defaultChatSection = String(data.section)
      if (!root.currentChatUrl || root.isHomepage(root.currentChatUrl)) {
        root.currentChatUrl = root.defaultChatUrl
        root.currentChatTitle = root.defaultChatTitle
        root.currentChatSection = root.defaultChatSection
      }
    } catch (e) {}
  }

  onManifestChanged: if (root.pluginDir) root.ensureWeb()
  Component.onDestruction: {
    webProc.running = false
    bridgeProc.running = false
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
    id: bridgeProc
    command: root.pluginDir ? ["python3", root.pluginDir + "/webview/bridge.py"] : ["true"]
    running: root.pluginDir !== ""
    onExited: if (root.pluginDir) bridgeRestart.restart()
  }

  Timer {
    id: bridgeRestart
    interval: 400
    repeat: false
    onTriggered: if (root.pluginDir && !bridgeProc.running) bridgeProc.running = true
  }

  Process {
    id: saveDefaultProc
    command: ["true"]
  }

  Process {
    id: refreshProc
    command: ["true"]
  }

  Timer {
    id: reloadWebTimer
    interval: 400
    repeat: false
    onTriggered: {
      root.ensureWeb()
      if (root.opened) {
        placeRetry.tries = 0
        placeRetry.running = true
      }
    }
  }

  FileView {
    path: root.dataDir + "/chats.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.parseChats(text())
    onFileChanged: reload()
  }

  FileView {
    path: root.dataDir + "/default-chat.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.parseDefault(text())
    onFileChanged: reload()
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

  HyprlandFocusGrab {
    active: root.opened && root.pickerOpen
    windows: [picker, toolbar]
    onCleared: root.pickerOpen = false
  }

  IpcHandler {
    target: "online.izz0.omarchy.grok-panel"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function picker(): void { if (root.opened) root.pickerOpen = !root.pickerOpen }
    function ping(): string { return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
  }

  // 1px Top-layer exclusive-zone request. A full-width Top surface covered
  // grok.com; a Bottom exclusive zone also inset the Omarchy bar. Toolbar,
  // handle, and picker must Ignore this zone so they sit in the reserved strip.
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
    exclusionMode: ExclusionMode.Normal
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
      top: root.toolbarHeight
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

  PanelWindow {
    id: toolbar
    screen: root.targetScreen
    visible: root.opened
    implicitWidth: root.panelWidth
    implicitHeight: root.toolbarHeight
    color: Color.popups.background
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Normal
    aboveWindows: true
    WlrLayershell.namespace: "omarchy-grok-toolbar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      left: root.side === "left"
      right: root.side === "right"
    }

    margins {
      top: root.barReserve()
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: Color.popups.border
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.pickerOpen = !root.pickerOpen

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.side === "right" ? root.handleWidth + 8 : 8
        anchors.rightMargin: root.side === "left" ? root.handleWidth + 8 : 8
        spacing: 8

        Text {
          Layout.fillWidth: true
          text: root.displayLabel(root.currentChatTitle || root.defaultChatTitle, root.currentChatSection || root.defaultChatSection)
          elide: Text.ElideRight
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Math.max(12, Style.font.body)
        }

        Text {
          text: root.pickerOpen ? "▴" : "▾"
          color: Color.popups.text
          font.pixelSize: 12
        }
      }
    }
  }

  PanelWindow {
    id: picker
    screen: root.targetScreen
    visible: root.opened && root.pickerOpen
    color: "transparent"
    surfaceFormat.opaque: false
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Normal
    aboveWindows: true
    WlrLayershell.namespace: "omarchy-grok-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.pickerOpen = false
    }

    Item {
      id: pickerCard
      width: root.panelWidth
      height: root.pickerHeight
      x: root.side === "right" ? parent.width - width : 0
      y: root.barReserve() + root.toolbarHeight
      focus: true
      Keys.onEscapePressed: root.pickerOpen = false

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Rectangle {
        anchors.fill: parent
        color: Color.popups.background
      }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 10
      spacing: 8

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
          Layout.fillWidth: true
          text: "Chats"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Math.max(12, Style.font.body)
        }

        MouseArea {
          implicitWidth: 22
          implicitHeight: 22
          cursorShape: Qt.PointingHandCursor
          onClicked: root.requestChatRefresh()

          Text {
            anchors.centerIn: parent
            text: root.refreshIcon
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        MouseArea {
          Layout.fillWidth: true
          implicitHeight: 28
          cursorShape: Qt.PointingHandCursor
          onClicked: root.loadChat("https://grok.com", "New chat", "")

          Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            text: "New chat"
            color: Color.popups.text
            font.pixelSize: 12
            font.bold: root.urlsMatch(root.currentChatUrl, "https://grok.com")
          }
        }

        MouseArea {
          implicitWidth: 22
          implicitHeight: 22
          cursorShape: Qt.PointingHandCursor
          onClicked: root.saveDefault("https://grok.com", "New chat", "")

          Text {
            anchors.centerIn: parent
            text: root.isHomepage(root.defaultChatUrl) ? root.pinFilled : root.pinOutline
            color: root.isHomepage(root.defaultChatUrl) ? Color.accent : Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
          }
        }
      }

      Text {
        visible: root.chatList.length === 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "Loading Grok chat history."
        color: Color.popups.text
        opacity: 0.7
        font.pixelSize: 12
      }

      ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.chatList
        section.property: "section"
        section.criteria: ViewSection.FullString
        section.delegate: Text {
          required property string section
          width: ListView.view ? ListView.view.width : 0
          height: 22
          text: section
          color: Color.popups.text
          opacity: 0.65
          font.pixelSize: 11
          verticalAlignment: Text.AlignBottom
        }
        delegate: Item {
          required property var modelData
          width: ListView.view.width
          height: 28

          RowLayout {
            anchors.fill: parent
            spacing: 6

            MouseArea {
              Layout.fillWidth: true
              Layout.fillHeight: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.loadChat(modelData.url, modelData.title, modelData.section || "")

              Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: modelData.title || modelData.url
                color: Color.popups.text
                font.pixelSize: 12
                font.bold: root.urlsMatch(modelData.url, root.currentChatUrl)
              }
            }

            MouseArea {
              Layout.preferredWidth: 22
              Layout.preferredHeight: 22
              cursorShape: Qt.PointingHandCursor
              onClicked: root.saveDefault(modelData.url, modelData.title, modelData.section || "")

              Text {
                anchors.centerIn: parent
                text: root.urlsMatch(modelData.url, root.defaultChatUrl) ? root.pinFilled : root.pinOutline
                color: root.urlsMatch(modelData.url, root.defaultChatUrl) ? Color.accent : Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
              }
            }
          }
        }
      }
    }
    }
  }
}
