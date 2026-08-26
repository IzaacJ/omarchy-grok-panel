import QtQuick
import QtQuick.Window
import QtCore
import QtWebEngine

Window {
  id: win
  title: "omarchy-grok-panel"
  width: 420
  height: 800
  visible: true
  color: "#111111"
  flags: Qt.FramelessWindowHint | Qt.Window

  WebEngineProfile {
    id: grokProfile
    storageName: "grok"
    offTheRecord: false
    persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    httpCacheType: WebEngineProfile.DiskHttpCache
    persistentStoragePath: StandardPaths.writableLocation(StandardPaths.GenericDataLocation)
      + "/online.izz0.omarchy.grok-panel/webengine"
    cachePath: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)
      + "/online.izz0.omarchy.grok-panel/webengine"
  }

  WebEngineView {
    id: webView
    anchors.fill: parent
    profile: grokProfile
    url: "https://grok.com"
    onNewWindowRequested: function(request) {
      request.openIn(webView)
    }
  }
}
