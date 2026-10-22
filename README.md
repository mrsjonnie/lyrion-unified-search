# Lyrion Unified Search

A small add-on for Lyrion Music Server (LMS) that adds search entries to LMS Global Search, including Material Skin's existing globalsearch items request.

## What it does

- Adds a **Unified Search** entry to the LMS Default skin's Browse menu, with one query form for the LMS Global Search providers.
- Adds **Local library** and, when SpotOn is enabled, **Spotify (SpotOn)** as selectable results.
- Leaves YouTube's native Global Search provider intact, so it appears alongside the new entries when the YouTube plugin is enabled.
- Registers with LMS Global Search so Material Skin's existing search field shows the same search providers. Material's own interface is used; no Material Skin files are modified.
- Uses literal display names for the plugin and search items, so missing translation loading cannot leave PLUGIN_UNIFIEDSEARCH visible.

## Compatibility and requirements

- LMS 8.0 or newer.
- SpotOn is optional; the Spotify entry appears only when Plugins::SpotOn::Plugin is enabled and its existing search callback is available.
- The local-library URL is built from LMS's configured server address and HTTP port; it does not depend on a hard-coded installation address.
- YouTube's own provider is not duplicated by this plugin.

## Install

Add this repository in **LMS Settings → Plugins → Additional Repositories**:

https://raw.githubusercontent.com/mrsjonnie/lyrion-unified-search/main/repo.xml

Click **Apply**, install **Lyrion Unified Search**, and restart LMS if requested.

## Development and release

- Plugin source: UnifiedSearch/Plugin.pm
- Repository template: repo.xml.in
- Release workflow: .github/workflows/release.yml

The GitHub Actions workflow packages both add-ons using the versions in their respective `install.xml` files, calculates their SHA-1 hashes, updates `repo.xml`, and publishes a release tagged with the UnifiedSearch version. Bump the version of each changed add-on before publishing a new release.

Disabling either add-on removes its contribution after the LMS web page is refreshed. Unified Search deregisters its Global Search provider and removes its Browse-menu entry; Default Logo Home returns the original server-rendered logo link.

DefaultLogoHome changes the logo link in the server-rendered Default skin home page, so the browser does not depend on a cached JavaScript override. In Material Skin, search from its existing search field; Local library and SpotOn appear in the Global Search results. The package still needs an end-to-end check on the target LMS installation, including both skins and SpotOn results.
