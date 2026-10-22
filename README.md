# Lyrion Unified Search

A small add-on for Lyrion Music Server (LMS) that adds search entries to LMS Global Search, including Material Skin's existing globalsearch items request.

## What it does

- Registers as a real LMS application so Material Skin lists **Unified Search** under **Apps/Applications**, and keeps the Browse menu entry in the LMS Default skin.
- Opens the app directly to a focused, live-search field, without an intermediate Unified Search item/button.
- Shows up to **three matches per source** from the local library, **YouTube channels**, **Spotify (Spotty)**, **SpotOn**, **Deezer**, **Qobuz**, **BBC Sounds**, **Radio.net stations**, and **Podcasts** as the query is typed.
- Opens the focused artist search field immediately in the Default skin and uses the enabled streaming plugins' native search callbacks.
- Registers with LMS Global Search; Material discovers the application through LMS's standard `OPMLBased` app registry. No Material Skin files are modified.
- Uses literal display names for the plugin and search items, so missing translation loading cannot leave PLUGIN_UNIFIEDSEARCH visible.

The repository also includes **YouTube Cast for Chromecast**, a separate add-on
that starts the native YouTube app on a configured Google Cast device whenever
an LMS YouTube track receives a Play request. Casting uses the original track
URL, starts the native YouTube app using its MDX/Lounge session, and does not
wait for LMS to start or transcode the audio. The LMS Play request targets the
currently selected playlist video. Enable automatic casting and set
the Chromecast IP address or local hostname beside each LMS player in the
add-on settings; the selected player determines the target.
The LMS YouTube plugin streams audio to its selected LMS player; this add-on
independently starts the video on the mapped TV.
Cast connection failures are written to `youtubecast-worker.log` in the LMS
log directory. Process-start failures include the Perl executable, worker
path, and OS error in the LMS log. On Linux systems, the LMS YouTube plugin
must also have a working yt-dlp runtime; missing system libraries such as
`libutil.so.1` prevent LMS from resolving playable YouTube tracks.

## Compatibility and requirements

- LMS 8.0 or newer.
- YouTube, Spotty, SpotOn, Deezer, Qobuz, BBC Sounds, and Podcasts are optional; matches appear only when the corresponding plugin is enabled and its search callback is available. Radio.net stations are searched live.
- YouTube Cast requires a Chromecast or Google Cast-enabled TV with the native YouTube app, the LMS YouTube plugin, and a mapped device host reachable from LMS on TCP port 8009. Enter only the device IP or hostname, not a URL or port.
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
