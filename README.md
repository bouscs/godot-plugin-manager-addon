# Plugin Manager

A Godot 4.5 editor plugin that auto-updates addons from GitHub Releases. Scans your project for managed addons, checks for new versions, and installs updates with one click.

## Features

- **Auto-discovery** of managed addons via `plugin_manager.json` config files
- **GitHub Releases integration** to check for latest versions
- **One-click updates** with download progress tracking
- **Safe installation** — old addon moved to trash, config preserved
- **Bottom panel UI** showing all managed addons and their statuses
- **Bulk operations** — check all and update all buttons

## Installation

1. Download the latest release zip
2. Extract `addons/plugin_manager/` into your Godot project root
3. Enable the plugin in **Project > Project Settings > Plugins**

## Managing an Addon

To manage an addon with Plugin Manager, create a `plugin_manager.json` file in the addon's directory:

```
res://addons/my_addon/plugin_manager.json
```

### Minimal Config

```json
{
    "repo": "username/repo-name",
    "current_version": "1.0.0"
}
```

### Full Config

```json
{
    "repo": "username/repo-name",
    "current_version": "1.0.0",
    "use_zipball": false,
    "asset_name": "*.zip",
    "addon_folder": "addons/my_addon",
    "strip_root_dir": true,
    "path_match": "addons/"
}
```

### Config Fields

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `repo` | Yes | — | GitHub repo path (e.g. `"bouscs/my-addon"`) |
| `current_version` | Yes | — | Currently installed version (updated automatically after updates) |
| `use_zipball` | No | `false` | Use GitHub's auto-generated source zip instead of a release asset |
| `asset_name` | No | — | Glob pattern to match a specific release asset (e.g. `"*.zip"`) |
| `addon_folder` | No | `"addons/{id}"` | Installation directory relative to project root |
| `strip_root_dir` | No | `true` | Strip the root directory from the zip when extracting |
| `path_match` | No | `"addons/"` | Only extract files matching this path prefix from the zip |

## Usage

1. Open the **Plugin Manager** panel at the bottom of the editor
2. Click **Check for Updates** to scan all managed addons
3. Addons with available updates show an **Update** button
4. Click **Update** on individual addons, or **Update All** for everything

## License

MIT
