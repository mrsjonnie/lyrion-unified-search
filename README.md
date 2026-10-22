# Lyrion Unified Search

A small add-on for Lyrion Music Server (LMS) that adds search entries to LMS Global Search, including Material Skin's existing globalsearch items request.

## What it does

- Registers as a real LMS application so Material Skin lists **Unified Search** under **Apps/Applications**, and keeps the Browse menu entry in the LMS Default skin.
- Opens a search prompt in Material Skin and one query form in the Default skin.
- Adds **Local library** and, when SpotOn is enabled, **Spotify (SpotOn)** as selectable results.
- Leaves YouTube's native Global Search provider intact, so it appears alongside the new entries when the YouTube plugin is enabled.
- Registers with LMS Global Search; Material discovers the application through LMS's standard `OPMLBased` app registry. No Material Skin files are modified.
- Uses literal display names for the plugin and search items, so missing translation loading cannot leave PLUGIN_UNIFIEDSEARCH visible.

The repository also includes **YouTube Cast for Chromecast**, a separate add-on
that starts the native YouTube app on a configured Google Cast device whenever
an LMS YouTube track starts. Set the Chromecast's stable IP address or hostname
and enable automatic casting in the add-on settings. The LMS YouTube plugin
streams audio to its selected LMS player; this add-on independently starts the
video on the configured TV.

## Compatibility and requirements

- LMS 8.0 or newer.
- SpotOn is optional; the Spotify entry appears only when Plugins::SpotOn::Plugin is enabled and its existing search callback is available.
- YouTube Cast requires a Chromecast with the native YouTube app, the LMS YouTube plugin, and a configured host reachable from LMS on TCP port 8009.
- The local-library URL is built from LMS's configured server address and HTTP port; it does not depend on a hard-coded installation address.
- YouTube's own provider is not duplicated by this plugin.

## Install

Add this repository in **LMS Settings → Plugins → Additional Repositories**:

https://raw.githubusercontent.com/mrsjonnie/lyrion-unified-search/main/repo.xml

Click **Apply**, install **Lyrion Unified Search** and, if desired, **YouTube
Cast for Chromecast**, then restart LMS if requested. Configure the Chromecast
host in **Settings → Plugins → YouTube Cast for Chromecast** before enabling
automatic casting.

## Development and release

- Plugin source: UnifiedSearch/Plugin.pm
- Repository template: repo.xml.in
- Release workflow: .github/workflows/release.yml

The GitHub Actions workflow packages all add-ons using the versions in their respective `install.xml` files, calculates their SHA-1 hashes, updates `repo.xml`, and publishes a release tagged with the UnifiedSearch version. Bump the version of each changed add-on before publishing a new release.

Disabling an add-on removes its contribution after the LMS web page is refreshed. Unified Search deregisters its Global Search provider and removes its Default and Material app menu entries; Default Logo Home returns the original server-rendered logo link. YouTube Cast only reacts when enabled and a Chromecast host is configured.

DefaultLogoHome changes the logo link in the server-rendered Default skin home page to the LMS root, not the skin-specific `/Default/` path. The package still needs an end-to-end check on the target LMS installation, including the Material Apps entry and SpotOn results.
