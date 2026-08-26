document.addEventListener(
  "contextmenu",
  function (event) {
    event.preventDefault()
    event.stopImmediatePropagation()
  },
  true
)

var DISCLAIMER = /by messaging grok|your privacy choices/i
var HEADER_CHROME = /^(toggle sidebar|open grok bot|switch to private chat|share project|toggle canvas)$/i
var PROJECT_CHROME = /share project|toggle canvas|open canvas|close canvas|show canvas|hide canvas/i
var COMPOSER_BOTTOM_PX = 20

function hideNode(el) {
  if (!el || el.getAttribute("data-grok-panel-hidden") === "disclaimer") return
  el.style.setProperty("display", "none", "important")
  el.style.setProperty("height", "0", "important")
  el.style.setProperty("min-height", "0", "important")
  el.style.setProperty("margin", "0", "important")
  el.style.setProperty("padding", "0", "important")
  el.style.setProperty("overflow", "hidden", "important")
  el.setAttribute("data-grok-panel-hidden", "disclaimer")
}

function leftoverText(el) {
  var text = ""
  var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, {
    acceptNode: function (node) {
      var p = node.parentElement
      while (p && p !== el) {
        if (p.getAttribute("data-grok-panel-hidden") === "disclaimer")
          return NodeFilter.FILTER_REJECT
        p = p.parentElement
      }
      return NodeFilter.FILTER_ACCEPT
    }
  })
  var n
  while ((n = walker.nextNode())) text += n.textContent
  return text.replace(/[\s·•|,.\-–—]/g, "")
}

function collapseEmpty(el) {
  var node = el && el.parentElement
  for (var i = 0; i < 8 && node && node !== document.body; i++) {
    if (node.id === "grok-content-area" || node.id === "grok-app-root") break
    if (node.querySelector("textarea, input, [contenteditable]")) break
    if (leftoverText(node).length > 0) break
    if (node.getBoundingClientRect().height > 180) break
    hideNode(node)
    node = node.parentElement
  }
}

function isProjectPage() {
  return /\/project\//.test(location.pathname)
}

function hideHeaderChrome() {
  if (!document.body) return
  var project = isProjectPage()
  var els = document.body.querySelectorAll("a, button, [role='button']")
  for (var i = 0; i < els.length; i++) {
    var el = els[i]
    if (el.getAttribute("data-grok-panel-hidden") === "disclaimer") continue
    var aria = String(el.getAttribute("aria-label") || "").trim()
    var title = String(el.getAttribute("title") || "").trim()
    var text = String(el.textContent || "").replace(/\s+/g, " ").trim()
    var label = aria || title || text
    var blob = (aria + " " + title + " " + text).replace(/\s+/g, " ").trim()
    var match = HEADER_CHROME.test(label) || HEADER_CHROME.test(aria)
    if (project && (PROJECT_CHROME.test(blob) || /^(share|canvas)$/i.test(label)))
      match = true
    if (!match && project) {
      var box = el.getBoundingClientRect()
      if (
        box.width >= 8 && box.width <= 48 &&
        box.height >= 8 && box.height <= 48 &&
        box.top >= 0 && box.top <= 88 &&
        box.right >= window.innerWidth - 120 &&
        !el.querySelector("textarea, input, [contenteditable]")
      )
        match = true
    }
    if (!match) continue
    hideNode(el)
    collapseEmpty(el)
  }
}

function hideDisclaimers() {
  if (!document.body) return
  hideHeaderChrome()
  var nodes = document.body.querySelectorAll("p, span, div, small, a, button, [role='button']")
  for (var i = 0; i < nodes.length; i++) {
    var el = nodes[i]
    if (el.getAttribute("data-grok-panel-hidden") === "disclaimer") continue
    if (el.querySelector("textarea, input, [contenteditable]")) continue
    var text = String(el.textContent || "").replace(/\s+/g, " ").trim()
    if (text.length < 8 || text.length > 400) continue
    if (!DISCLAIMER.test(text)) continue
    var box = el.getBoundingClientRect()
    if (box.height > 160) continue
    hideNode(el)
    collapseEmpty(el)
  }
  tightenComposer()
}

function tightenComposer() {
  var composer = document.querySelector("textarea, [contenteditable='true']")
  if (!composer) return
  composer.style.setProperty("padding-top", "10px", "important")
  composer.style.setProperty("padding-bottom", "10px", "important")
  composer.style.setProperty("vertical-align", "middle", "important")
  var cr = composer.getBoundingClientRect()
  var node = composer
  for (var depth = 0; depth < 16 && node && node.parentElement; depth++) {
    var parent = node.parentElement
    if (parent.id === "grok-content-area" || parent.id === "grok-app-root") break

    var sib = node.nextElementSibling
    while (sib) {
      var next = sib.nextElementSibling
      if (!sib.contains(composer) && !sib.querySelector("textarea, [contenteditable='true']")) {
        var box = sib.getBoundingClientRect()
        if (box.height < 220 && box.top >= cr.top - 8) hideNode(sib)
      }
      sib = next
    }

    var style = window.getComputedStyle(parent)
    var parentBox = parent.getBoundingClientRect()
    if (parentBox.height < 160) {
      if ((parseFloat(style.paddingBottom) || 0) > 4)
        parent.style.setProperty("padding-bottom", "0", "important")
      if ((parseFloat(style.paddingBlockEnd) || 0) > 4)
        parent.style.setProperty("padding-block-end", "0", "important")
      if ((parseFloat(style.marginBottom) || 0) > 4)
        parent.style.setProperty("margin-bottom", "0", "important")
      parent.style.setProperty("min-height", "0", "important")
    }
    if ((style.position === "absolute" || style.position === "fixed") && (parseFloat(style.bottom) || 0) > COMPOSER_BOTTOM_PX)
      parent.style.setProperty("bottom", COMPOSER_BOTTOM_PX + "px", "important")

    node = parent
  }
  fitComposerToViewport(composer)
  padMessageList(composer)
  hideBelowComposer(composer, composer.getBoundingClientRect())
}

function composerDock(composer) {
  var el = composer
  while (el && el !== document.body) {
    var style = window.getComputedStyle(el)
    if (style.position === "absolute" || style.position === "fixed") return el
    el = el.parentElement
  }
  return composer
}

function padMessageList(composer) {
  var dock = composerDock(composer)
  var pad = Math.ceil(dock.getBoundingClientRect().height + COMPOSER_BOTTOM_PX + 16)
  var root = document.getElementById("grok-content-area") || document.body
  var nodes = root.querySelectorAll("div")
  var scroller = null
  var best = 0
  for (var i = 0; i < nodes.length; i++) {
    var el = nodes[i]
    var oy = window.getComputedStyle(el).overflowY
    if (oy !== "auto" && oy !== "scroll" && oy !== "overlay") continue
    var h = el.getBoundingClientRect().height
    if (h < 200 || h <= best) continue
    best = h
    scroller = el
  }
  if (!scroller) return
  scroller.style.setProperty("padding-bottom", pad + "px", "important")
  scroller.style.setProperty("scroll-padding-bottom", pad + "px", "important")
  var spacer = scroller.querySelector(":scope > .grok-panel-scroll-pad")
  if (!spacer) {
    spacer = document.createElement("div")
    spacer.className = "grok-panel-scroll-pad"
    scroller.appendChild(spacer)
  }
  spacer.style.height = pad + "px"
  spacer.style.flexShrink = "0"
  spacer.setAttribute("aria-hidden", "true")
}

function viewportHeight() {
  if (window.visualViewport && window.visualViewport.height)
    return window.visualViewport.height
  return window.innerHeight
}

function fitComposerToViewport(composer) {
  var el = composer
  while (el && el !== document.body) {
    var style = window.getComputedStyle(el)
    if (style.position === "absolute" || style.position === "fixed") {
      var box = el.getBoundingClientRect()
      var overflow = box.bottom - (viewportHeight() - COMPOSER_BOTTOM_PX)
      if (overflow > 0) {
        var cur = parseFloat(style.bottom) || 0
        el.style.setProperty("bottom", (cur + overflow) + "px", "important")
      }
      return
    }
    el = el.parentElement
  }
}

function hasUsefulControls(el) {
  var hits = el.querySelectorAll("button, [role='button'], textarea, [contenteditable], input, svg")
  for (var i = 0; i < hits.length; i++) {
    var n = hits[i]
    if (n.getAttribute("data-grok-panel-hidden") === "disclaimer") continue
    if (n.closest("[data-grok-panel-hidden='disclaimer']")) continue
    return true
  }
  return false
}

function hideBelowComposer(composer, cr) {
  var els = document.body.querySelectorAll("div, p, span, footer, section")
  for (var i = 0; i < els.length; i++) {
    var el = els[i]
    if (el.getAttribute("data-grok-panel-hidden") === "disclaimer") continue
    if (el === composer || el.contains(composer) || composer.contains(el)) continue
    if (hasUsefulControls(el)) continue
    var box = el.getBoundingClientRect()
    if (box.height < 16 || box.height > 72) continue
    if (box.width < 40) continue
    if (box.top < cr.bottom - 12) continue
    var leftover = leftoverText(el)
    if (leftover.length > 0 && !DISCLAIMER.test(el.textContent || "")) continue
    hideNode(el)
  }
}

var hideScheduled = false
function scheduleHide() {
  if (hideScheduled) return
  hideScheduled = true
  requestAnimationFrame(function () {
    hideScheduled = false
    hideDisclaimers()
  })
}

function hostIsGrok() {
  var host = location.hostname
  return /(^|\.)grok\.com$/.test(host) || /(^|\.)x\.ai$/.test(host)
}

function controlLabel(el) {
  return String((el.getAttribute("aria-label") || "") + " " + (el.textContent || ""))
    .replace(/\s+/g, " ")
    .trim()
}

function findSignInControl() {
  var els = document.querySelectorAll("a, button, [role='button']")
  var fallback = null
  for (var i = 0; i < els.length; i++) {
    var el = els[i]
    if (el.getAttribute("data-grok-panel-hidden") === "disclaimer") continue
    var label = controlLabel(el)
    if (/sign in with x|continue with x|log in with x|login with x|login with 𝕏/i.test(label)) return el
    if (/^(sign in|log in|login)$/i.test(label) && !fallback) fallback = el
  }
  return fallback || document.querySelector('a[href*="sign-in"], a[href*="signin"], a[href*="/login"]')
}

function maybeSignIn() {
  if (!hostIsGrok()) return
  if (sessionStorage.getItem("grok-panel-signin") === "1") return
  var btn = findSignInControl()
  if (!btn) return
  var box = btn.getBoundingClientRect()
  if (box.width < 4 || box.height < 4) return
  sessionStorage.setItem("grok-panel-signin", "1")
  btn.click()
}

function addChat(chats, seen, id, title, url, extra) {
  if (!id || id === "private" || seen[id]) return
  seen[id] = true
  title = String(title || "").replace(/\s+/g, " ").trim()
  if (!title) title = "Chat " + String(id).replace(/^project:/, "").slice(0, 8)
  if (title.length > 80) title = title.slice(0, 79) + "…"
  var row = { id: id, title: title, url: url || ("https://grok.com/c/" + id) }
  if (extra) {
    if (extra.section) row.section = extra.section
    if (extra.workspaceId) row.workspaceId = extra.workspaceId
  }
  chats.push(row)
}

var lastApiAt = 0
var lastApiChats = []
var lastPreferredProject = null
var apiWaiters = []
var apiRequested = false

window.addEventListener("message", function (event) {
  if (event.source !== window) return
  if (!event.data || event.data.type !== "grok-panel-chats") return
  var list = event.data.chats || []
  lastApiAt = Date.now()
  lastApiChats = list
  lastPreferredProject = event.data.preferredProject || null
  apiRequested = false
  var waiters = apiWaiters
  apiWaiters = []
  for (var i = 0; i < waiters.length; i++) waiters[i](list)
})

function fetchChatLists(force) {
  if (!force && lastApiChats.length && Date.now() - lastApiAt < 20000)
    return Promise.resolve(lastApiChats)
  return new Promise(function (resolve) {
    apiWaiters.push(resolve)
    if (apiRequested) return
    apiRequested = true
    window.postMessage({ type: "grok-panel-request-chats" }, "*")
    setTimeout(function () {
      if (!apiWaiters.length) return
      apiRequested = false
      var waiters = apiWaiters
      apiWaiters = []
      for (var i = 0; i < waiters.length; i++) waiters[i](lastApiChats)
    }, 4000)
  })
}

function scrapeDomChats(chats, seen) {
  var current = location.pathname.match(/\/c\/([A-Za-z0-9_-]+)/)
  if (current)
    addChat(chats, seen, current[1], document.title, location.href.split("?")[0].split("#")[0])
  var project = location.pathname.match(/\/project\/([A-Za-z0-9_-]+)/)
  if (project)
    addChat(chats, seen, "new:" + project[1], "New chat in project", "https://grok.com/project/" + project[1])
  var links = document.querySelectorAll("a[href]")
  for (var i = 0; i < links.length; i++) {
    var href = links[i].getAttribute("href") || ""
    var chatMatch = href.match(/\/c\/([A-Za-z0-9_-]+)/)
    if (chatMatch) {
      var title = String(links[i].getAttribute("aria-label") || links[i].textContent || "")
      addChat(chats, seen, chatMatch[1], title, "https://grok.com/c/" + chatMatch[1])
      continue
    }
    var projectMatch = href.match(/\/project\/([A-Za-z0-9_-]+)/)
    if (projectMatch) {
      addChat(chats, seen, "new:" + projectMatch[1], "New chat in project", "https://grok.com/project/" + projectMatch[1])
    }
  }
}

function pageCurrent() {
  var href = location.href.split("?")[0].split("#")[0]
  var title = String(document.title || "").replace(/\s*[|·\-–—]\s*Grok.*$/i, "").trim()
  if (!title || /^grok$/i.test(title)) title = ""
  var chat = location.pathname.match(/\/c\/([A-Za-z0-9_-]+)/)
  var project = location.pathname.match(/\/project\/([A-Za-z0-9_-]+)/)
  return {
    href: href,
    title: title,
    chatId: chat ? chat[1] : "",
    projectId: project ? project[1] : ""
  }
}

function describeCurrent(chats) {
  var page = pageCurrent()
  var href = page.href
  var title = page.title
  var section = ""
  for (var i = 0; i < (chats || []).length; i++) {
    var item = chats[i]
    if (!item || !item.url) continue
    var itemUrl = String(item.url).split("?")[0].split("#")[0]
    if (itemUrl === href || (page.chatId && item.id === page.chatId) ||
        (page.projectId && item.id === "new:" + page.projectId)) {
      href = item.url
      if (item.title) title = item.title
      if (item.section) section = item.section
      break
    }
  }
  if (!title && page.projectId) title = "New chat in project"
  if (!title) title = "New chat"
  return { href: href, title: title, section: section }
}

function postChatState(chats, extra) {
  var current = describeCurrent(chats)
  var payload = {
    current: current.href,
    currentTitle: current.title,
    currentSection: current.section,
    chats: chats,
    preferredProject: lastPreferredProject,
    refreshedAt: Date.now()
  }
  if (extra) {
    for (var key in extra) payload[key] = extra[key]
  }
  fetch("http://127.0.0.1:18765/state", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  }).catch(function () {})
}

function reportChats(force) {
  if (window.top !== window) return
  if (!/(^|\.)grok\.com$/.test(location.hostname)) return
  var chats = []
  var seen = {}
  scrapeDomChats(chats, seen)
  fetchChatLists(!!force).then(function (apiChats) {
    var merged = []
    var mergedSeen = {}
    for (var i = 0; i < (apiChats || []).length; i++)
      addChat(merged, mergedSeen, apiChats[i].id, apiChats[i].title, apiChats[i].url, apiChats[i])
    for (var j = 0; j < chats.length; j++)
      addChat(merged, mergedSeen, chats[j].id, chats[j].title, chats[j].url, chats[j])
    postChatState(merged, { refreshed: !!force })
  }).catch(function () {
    postChatState(chats, { refreshed: !!force })
  })
}

function pollRefresh() {
  if (window.top !== window) return
  fetch("http://127.0.0.1:18765/refresh")
    .then(function (res) { return res.text() })
    .then(function (text) {
      if (String(text || "").trim() === "1") {
        lastApiAt = 0
        reportChats(true)
      }
    })
    .catch(function () {})
}

function start() {
  hideDisclaimers()
  new MutationObserver(scheduleHide).observe(document.documentElement, {
    childList: true,
    subtree: true,
    characterData: true
  })
  setTimeout(hideDisclaimers, 400)
  setTimeout(function () { hideDisclaimers(); maybeSignIn(); reportChats() }, 700)
  setTimeout(function () { hideDisclaimers(); maybeSignIn(); reportChats() }, 2000)
  setInterval(reportChats, 4000)
  setInterval(pollRefresh, 400)
}

if (document.readyState === "loading")
  document.addEventListener("DOMContentLoaded", start)
else
  start()
