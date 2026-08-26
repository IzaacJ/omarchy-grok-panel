(function () {
  if (window.top !== window) return
  if (window.__grokPanelChatApi) return
  window.__grokPanelChatApi = true

  function get(path) {
    return fetch(path, {
      credentials: "include",
      headers: { Accept: "application/json" }
    }).then(function (res) {
      return res.ok ? res.json() : null
    }).catch(function () {
      return null
    })
  }

  function rec(obj) {
    if (!obj || typeof obj !== "object") return obj
    if (obj.conversation && typeof obj.conversation === "object") return obj.conversation
    return obj
  }

  function recId(obj) {
    obj = rec(obj)
    if (!obj) return ""
    return String(obj.conversationId || obj.conversation_id || obj.id || "").trim()
  }

  function recTitle(obj) {
    obj = rec(obj)
    if (!obj) return ""
    return String(obj.title || obj.name || obj.conversationTitle || obj.displayName || "")
      .replace(/\s+/g, " ").trim()
  }

  function recWorkspace(obj) {
    obj = rec(obj)
    if (!obj) return ""
    return String(obj.workspaceId || obj.projectId || obj.workspace_id || "").trim()
  }

  function nameKey(title) {
    return String(title || "").toLowerCase().replace(/[^a-z0-9]+/g, "")
  }

  function isPanelProject(title) {
    var key = nameKey(title)
    return key === "sidepanel" || key === "grokpanel"
  }

  function pages(query, workspaceId) {
    var out = []
    var seen = {}
    var pageToken = ""
    var n = 0
    function next() {
      var path = "/rest/app-chat/conversations?pageSize=60" + (query || "")
      if (pageToken) path += "&pageToken=" + encodeURIComponent(pageToken)
      return get(path).then(function (data) {
        if (!data) return out
        var list = data.conversations || []
        for (var i = 0; i < list.length; i++) {
          var item = rec(list[i])
          var id = recId(item)
          if (!id || seen[id]) continue
          seen[id] = true
          var title = recTitle(item)
          var ws = recWorkspace(item) || workspaceId || ""
          out.push({
            id: id,
            title: title,
            url: "https://grok.com/c/" + id,
            workspaceId: ws
          })
        }
        pageToken = String(data.nextPageToken || "").trim()
        n += 1
        if (pageToken && n < 3 && out.length < 180) return next()
        return out
      })
    }
    return next()
  }

  function workspaces() {
    return get("/rest/workspaces?pageSize=50&orderBy=ORDER_BY_LAST_USE_TIME&kind=WORKSPACE_KIND_ALL")
      .then(function (data) {
        var list = (data && (data.workspaces || data.projects)) || []
        var out = []
        for (var i = 0; i < list.length; i++) {
          var item = rec(list[i])
          var id = String((item && (item.workspaceId || item.projectId || item.id)) || "").trim()
          if (!id) continue
          out.push({
            id: "project:" + id,
            title: recTitle(item) || ("Project " + id.slice(0, 8)),
            url: "https://grok.com/project/" + id,
            workspaceId: id
          })
        }
        return out
      })
  }

  function pickPreferredProject(projects) {
    var sidepanel = null
    var grokpanel = null
    for (var i = 0; i < projects.length; i++) {
      var key = nameKey(projects[i].title)
      if (key === "sidepanel" && !sidepanel) sidepanel = projects[i]
      if (key === "grokpanel" && !grokpanel) grokpanel = projects[i]
    }
    return sidepanel || grokpanel || null
  }

  function newChatInProject(project) {
    var id = String(project.workspaceId || "").trim()
    var name = String(project.title || "project").trim() || "project"
    return {
      id: "new:" + id,
      title: "New chat in " + name,
      url: "https://grok.com/project/" + id,
      workspaceId: id,
      section: name
    }
  }

  function collect() {
    return workspaces().then(function (projects) {
      var preferred = pickPreferredProject(projects)
      var ordered = []
      if (preferred) ordered.push(preferred)
      for (var i = 0; i < projects.length; i++) {
        if (!preferred || projects[i].workspaceId !== preferred.workspaceId)
          ordered.push(projects[i])
      }
      var cap = Math.min(ordered.length, 8)
      var jobs = [pages("")]
      for (var j = 0; j < cap; j++)
        jobs.push(pages("&workspaceId=" + encodeURIComponent(ordered[j].workspaceId), ordered[j].workspaceId))
      return Promise.all(jobs).then(function (parts) {
        var globalChats = parts[0] || []
        var seen = {}
        var chats = []

        function add(item, section) {
          if (!item || !item.id || seen[item.id]) return
          seen[item.id] = true
          chats.push({
            id: item.id,
            title: item.title,
            url: item.url,
            workspaceId: item.workspaceId || "",
            section: section || item.section || ""
          })
        }

        for (var p = 0; p < cap; p++) {
          var project = ordered[p]
          var projectChats = parts[p + 1] || []
          add(newChatInProject(project), project.title)
          for (var c = 0; c < projectChats.length; c++)
            add(projectChats[c], project.title)
          for (var g = 0; g < globalChats.length; g++) {
            if (globalChats[g].workspaceId === project.workspaceId)
              add(globalChats[g], project.title)
          }
        }
        for (var r = 0; r < globalChats.length; r++)
          add(globalChats[r], "Other chats")

        return {
          chats: chats,
          preferredProject: preferred ? newChatInProject(preferred) : null
        }
      })
    })
  }

  function publish() {
    collect().then(function (result) {
      window.postMessage({
        type: "grok-panel-chats",
        chats: (result && result.chats) || [],
        preferredProject: (result && result.preferredProject) || null
      }, "*")
    }).catch(function () {
      window.postMessage({ type: "grok-panel-chats", chats: [], preferredProject: null }, "*")
    })
  }

  window.addEventListener("message", function (event) {
    if (event.source !== window) return
    if (!event.data || event.data.type !== "grok-panel-request-chats") return
    publish()
  })

  setTimeout(publish, 300)
  setTimeout(publish, 2000)
})()
