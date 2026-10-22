# Lyrion Unified Search

A small add-on for Lyrion Music Server (LMS) that adds search entries to LMS Global Search, including Material Skin's existing globalsearch items request.

## What it does

- Adds a **Local library** item that opens the LMS web search page.
- Adds **Spotify (SpotOn)** as a direct search item by calling SpotOn's existing search-feed callback.
- Leaves YouTube's native Global Search provider intact, so it appears alongside the new entries when the YouTube plugin is enabled.
- Returns individual search items rather than a nested submenu. This matters because Material Skin renders the top-level Global Search items.
- Uses literal display names for the plugin and search items, so missing translation loading cannot leave PLUGIN_UNIFIEDSEARCH visible.

## Compatibility and requirements

- LMS 8.0 or newer.
- SpotOn is optional; the Spotify entry appears only when Plugins::SpotOn::Plugin is enabled and its existing search callback is available.
- The local-library URL currently targets http://192.168.178.99:9001, the LMS address used for this installation. Change it if LMS is hosted elsewhere.
- YouTube's own provider is not duplicated by this plugin.

## Install

Add this repository in **LMS Settings → Plugins → Additional Repositories**:

https://raw.githubusercontent.com/mrsjonnie/lyrion-unified-search/main/repo.xml

Click **Apply**, install **Lyrion Unified Search**, and restart LMS if requested.

## Development and release

- Plugin source: UnifiedSearch/Plugin.pm
- Repository template: repo.xml.in
- Release workflow: .github/workflows/release.yml

The GitHub Actions workflow packages both add-ons, calculates their SHA-1 hashes, updates repo.xml, and publishes the version declared in UnifiedSearch/install.xml. Bump that version before publishing a new release.

The package still needs an end-to-end check on the target LMS/Material Skin installation. In particular, confirm that the Spotify entry appears in Material Skin and opens SpotOn's search results.
