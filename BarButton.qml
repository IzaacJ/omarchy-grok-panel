import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "online.izz0.omarchy.grok-panel"

  readonly property var host: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(root.moduleName)
    : null
  readonly property bool opened: host ? host.opened === true : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function ensureHost() {
    if (root.host) return root.host
    if (root.bar && root.bar.shell && typeof root.bar.shell.ensureService === "function")
      return root.bar.shell.ensureService(root.moduleName)
    return null
  }

  function open() {
    var service = ensureHost()
    if (!service) return
    service.applySettings(root.settings)
    if (typeof service.openFrom === "function") service.openFrom(root)
    else service.open()
  }

  function close() {
    var service = ensureHost()
    if (service) service.close()
  }

  function toggle() { opened ? close() : open() }

  Component.onCompleted: {
    var service = ensureHost()
    if (!service) return
    service.applySettings(root.settings)
    if (typeof service.shortcutScript === "function")
      service.shortcutScript("bind")
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰚩"
    tooltipText: root.opened ? "Close panel" : "Open panel"
    active: root.opened
    onPressed: function(buttonCode) {
      var service = root.ensureHost()
      if (buttonCode === Qt.RightButton) {
        if (service && typeof service.cycleSide === "function") service.cycleSide()
      } else if (buttonCode === Qt.LeftButton) {
        root.toggle()
      }
    }
  }
}
