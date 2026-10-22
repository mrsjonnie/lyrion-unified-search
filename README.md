# Lyrion Unified Search

A standalone add-on for Lyrion Music Server (LMS) that adds one grouped entry to LMS Global Search for the local library, YouTube, and SpotOn.

## Current implementation

- Registers a **Unified Search** provider using LMS's `Slim::Menu::GlobalSearch` extension API.
- Adds a local-library destination that opens the LMS web search page on the home-server address currently used by the author: `http://192.168.178.99:9001`.
- Reuses YouTube's existing search handler when the YouTube plugin is installed and enabled.
- Reuses SpotOn's existing search feed when SpotOn is installed and enabled.
- Does not edit Material Skin, YouTube, SpotOn, LMS core, or the Default skin.

The initial implementation groups the three source actions under one search-provider entry. It is not yet a single flat, cross-provider result list; each source continues to render results using its own existing LMS feed. The local-library destination is specific to the author's current LMS address and should be made configurable before a general public release.

## Compatibility and requirements

- LMS 8.0 or newer.
- YouTube and/or SpotOn are optional; their entries are omitted when the respective plugin is not enabled.
- The local-library link currently targets `192.168.178.99:9001`.

## Installation

The initial `0.1.0` package and LMS repository metadata are published in this repository. Add this URL in **LMS Settings → Plugins → Additional Repositories**:

```
https://raw.githubusercontent.com/mrsjonnie/lyrion-unified-search/main/repo.xml
```

Click **Apply**, find **Lyrion Unified Search**, install it, and restart LMS if requested.

The package ZIP is stored at `dist/UnifiedSearch-0.1.0.zip`. For later releases, push a version tag such as `v0.1.1`. The release workflow creates a versioned plugin ZIP, calculates its SHA-1, publishes a GitHub release, and updates `repo.xml` on `main`.

## Uninstall

Disable and uninstall **Lyrion Unified Search** through LMS's plugin settings. The plugin only registers its own Global Search provider; it does not write to the configuration of other plugins.

## Development notes

- Plugin source: `UnifiedSearch/Plugin.pm`
- LMS repository template: `repo.xml.in`
- Release workflow: `.github/workflows/release.yml`

The package has not yet been end-to-end tested on the author's LMS instance, especially the local web-search link and the installed versions of YouTube and SpotOn.
