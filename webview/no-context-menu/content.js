document.addEventListener(
  "contextmenu",
  function (event) {
    event.preventDefault()
    event.stopImmediatePropagation()
  },
  true
)
