# Grok Panel

An [Omarchy](https://omarchy.org/) shell plugin that docks a full-height side panel to the left or right of a monitor, like the top bar.

Plugin id: `online.izz0.omarchy.grok-panel`  
Bar label: **Grok**

The **Grok** bar button lives in omarchy-shell. The docked strip (exclusive zone + resize handle) is a layer-shell surface. **grok.com** runs in a separate `qml6` window with Qt WebEngine so Chromium is not loaded inside the bar process (Quickshell fatals if it hosts WebEngine).

Login cookies stay under `~/.local/share/online.izz0.omarchy.grok-panel/` and `~/.cache/online.izz0.omarchy.grok-panel/`.

## Install

Requires [Omarchy](https://omarchy.org/) with `omarchy-shell`. This repository is private, so Git must be able to clone it (SSH is fine if your GitHub key is loaded).

```bash
omarchy plugin add git@github.com:IzaacJ/omarchy-grok-panel.git --enable
```

That clones the plugin into `~/.config/omarchy/plugins/online.izz0.omarchy.grok-panel/` and adds a **Grok** widget to the right side of the bar.

If the widget does not appear, restart the shell:

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
| Right click **Grok** | Dock to the opposite side (left ↔ right) |
| Drag the inner edge | Resize width |

The panel takes the full monitor height and pushes tiled windows aside (Hyprland exclusive zone). Width is clamped between 280px and the smaller of 900px or half the monitor.

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

## Commands

```bash
omarchy-shell online.izz0.omarchy.grok-panel toggle
omarchy-shell online.izz0.omarchy.grok-panel open
omarchy-shell online.izz0.omarchy.grok-panel close
omarchy-shell online.izz0.omarchy.grok-panel state
```

## Requirements

- Omarchy / `omarchy-shell`
- `qt6-webengine` and `qml6` (from `qt6-declarative`)
- Hyprland (`hyprctl`) to size the grok.com window into the reserved strip

## Remove

```bash
omarchy plugin remove online.izz0.omarchy.grok-panel
```

## License

MIT
