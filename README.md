# Lyrion Unified Search

A small add-on for Lyrion Music Server (LMS) that adds search entries to LMS Global Search, including Material Skin's existing globalsearch items request.

## What it does

- Registers as a real LMS application so Material Skin lists **Unified Search** under **Apps/Applications**, and keeps the Browse menu entry in the LMS Default skin.
- Opens a search prompt in Material Skin and a focused, live-search field in the Default skin.
- Shows up to **three artist matches per source** from the local library, **YouTube**, **Spotify (Spotty)**, **SpotOn**, **Deezer**, and **Qobuz** as the query is typed.
- Opens the focused artist search field immediately in the Default skin and uses the enabled streaming plugins' native search callbacks.
- Registers with LMS Global Search; Material discovers the application through LMS's standard `OPMLBased` app registry. No Material Skin files are modified.
- Uses literal display names for the plugin and search items, so missing translation loading cannot leave PLUGIN_UNIFIEDSEARCH visible.

The repository also includes **YouTube Cast for Chromecast**, a separate add-on
that starts the native YouTube app on a configured Google Cast device whenever
an LMS YouTube track receives a Play request. Casting uses the original track
URL and does not wait for LMS to start or transcode the audio. Enable automatic
casting and map each LMS player name to a Chromecast IP address or local
hostname in the add-on settings; the selected player determines the target.
The LMS YouTube plugin streams audio to its selected LMS player; this add-on
independently starts the video on the mapped TV.
Cast connection failures are written to `youtubecast-worker.log` in the LMS
log directory.

## Compatibility and requirements

- LMS 8.0 or newer.
- YouTube, Spotty, SpotOn, Deezer, and Qobuz are optional; matches appear only when the corresponding plugin is enabled and its search callback is available.
- YouTube Cast requires a Chromecast with the native YouTube app, the LMS YouTube plugin, and a mapped host reachable from LMS on TCP port 8009.
- Local search uses LMS's native browse feeds, including search categories and virtual-library handling; it does not route OPML clients to the HTML search page.
- The app and its result entries use LMS's built-in search icon.

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
