# Grok Panel

An [Omarchy](https://omarchy.org/) shell plugin that docks **grok.com** as a full-height side panel, like the top bar.

Plugin id: `online.izz0.omarchy.grok-panel`  
Bar label: **Grok**

The **Grok** button lives in omarchy-shell. The docked strip (exclusive zone, native toolbar, resize handle) is a layer-shell surface. grok.com runs in a separate Chromium `--app` window so the browser is not loaded inside the bar process.

Login cookies, the Chromium profile, and the saved default chat stay under `~/.local/share/online.izz0.omarchy.grok-panel/`.

A stock [Omarchy](https://omarchy.org/) install is enough. There are no extra packages to add.

## Install

```bash
omarchy plugin add git@github.com:IzaacJ/omarchy-grok-panel.git --enable
```

That clones the plugin into `~/.config/omarchy/plugins/online.izz0.omarchy.grok-panel/` and adds a **Grok** widget to the bar (you can pick left / center / right). If the widget does not appear, restart the shell:

```bash
omarchy restart shell
```

### Local checkout

For development, point Omarchy at this directory instead of cloning:

```bash
mkdir -p ~/.config/omarchy/plugins
ln -sfn /path/to/omarchy-grok-panel ~/.config/omarchy/plugins/online.izz0.omarchy.grok-panel
omarchy plugin enable online.izz0.omarchy.grok-panel
omarchy restart shell
```

The plugin folder name must match the id.

## Use

| Action | Result |
| --- | --- |
| Left click **Grok** on the bar | Open or close the panel on that monitor |
| SUPER + CTRL + G | Open or close the panel |
| Right click **Grok** | Dock to the opposite side (left ↔ right) |
| Drag the inner red edge | Resize width |
| Click the native title bar | Open or close the chat list |
| Click a chat in the list | Load that chat (does not change the default) |
| Click the pin on a row | Pin that chat as the default for the next launch |
| Refresh (top-right of the list) | Reload the current chat URL/name and the conversation list |
| Click outside the list, or Escape | Close the list without changing anything |

The panel takes the full monitor height below the Omarchy bar and pushes tiled windows aside (Hyprland exclusive zone). Width is clamped between 280px and the smaller of 900px or half the monitor.

On **first login**, if you have no saved default and a grok.com project named **Sidepanel** or **Grok-Panel** exists, that project’s new-chat page becomes the default.

Sign in on grok.com inside the panel when asked (X / Google / Apple / email). The session stays in this plugin’s Chromium profile.

Project chats are grouped under the project name. The first row in each group, **New chat in *project***, opens a new conversation in that project. While a project chat is open, the title bar shows `project \ chat title`.

## Settings

Bar entries in `~/.config/omarchy/shell.json` can set side and width:

```json
{
  "id": "online.izz0.omarchy.grok-panel",
  "side": "right",
  "width": 420
}
```

`side` is `"left"` or `"right"`. `width` is pixels. Changes apply when the widget loads; dragging the inner edge updates the live panel.

Pinned default (and optional project name) is stored in:

```
~/.local/share/online.izz0.omarchy.grok-panel/default-chat.json
```

## Commands

The plugin registers **SUPER + CTRL + G** while it is enabled, unless that key is already bound. Override it in `~/.config/hypr/bindings.lua` if you want a different key.

```bash
omarchy-shell online.izz0.omarchy.grok-panel toggle
omarchy-shell online.izz0.omarchy.grok-panel open
omarchy-shell online.izz0.omarchy.grok-panel close
omarchy-shell online.izz0.omarchy.grok-panel state
omarchy-shell online.izz0.omarchy.grok-panel picker
```

`picker` opens or closes the chat list while the panel is already open.

## Remove

```bash
omarchy plugin remove online.izz0.omarchy.grok-panel
```

That removes the plugin and bar widget. It does not delete `~/.local/share/online.izz0.omarchy.grok-panel/` (login cookies and the pinned default).

## License

MIT
