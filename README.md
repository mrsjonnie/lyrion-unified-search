# Lyrion Unified Search

A small add-on for Lyrion Music Server (LMS) that adds search entries to LMS Global Search, including Material Skin's existing globalsearch items request.

## What it does

- Registers as a real LMS application so Material Skin lists **Unified Search** under **Apps/Applications**, and keeps the Browse menu entry in the LMS Default skin.
- Opens the app directly to a focused, live-search field, without an intermediate Unified Search item/button.
- Shows up to **three matches per source** from the local library, **YouTube videos**, **Spotify (Spotty)**, **SpotOn**, **Deezer**, **Qobuz**, **BBC Sounds** (labeled `BBC:`), **Radio.net stations**, and **Podcasts** as the query is typed.
- Opens the focused artist search field immediately in the Default skin and uses the enabled streaming plugins' native search callbacks.
- Registers with LMS Global Search; Material discovers the application through LMS's standard `OPMLBased` app registry. No Material Skin files are modified.
- Uses literal display names for the plugin and search items, so missing translation loading cannot leave PLUGIN_UNIFIEDSEARCH visible.

The repository also includes **YouTube Cast for Chromecast**, a separate add-on
that automatically routes LMS YouTube playback to the Chromecast assigned to the
active LMS player. Enter a device IP address or local hostname beside each LMS
player in the add-on settings. A blank host keeps normal LMS YouTube audio
playback; a configured host starts the original video in the native YouTube app
and supplies a silent MP3 stream to LMS so the playlist, previous/next controls,
and automatic track progression remain under LMS control. The mapping is
player-specific; there is no global Chromecast fallback.
Cast connection failures are written to `youtubecast-worker.log` in the LMS
log directory. The LMS YouTube plugin still resolves track metadata and
duration through its yt-dlp runtime.
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
Cast for Chromecast**, then restart LMS if requested. Configure a Chromecast IP or hostname per LMS player in **Settings → Plugins → YouTube Cast for Chromecast**. Leave it blank for normal LMS YouTube audio.

## QNAP QPKG: yt-dlp update workaround

For QNAP LMS installations where the YouTube plugin's built-in **Update yt-dlp** action fails because the PyInstaller runtime cannot load `libutil.so.1`, see [qnap/README.md](qnap/README.md). The helper at [qnap/update-yt-dlp.sh](qnap/update-yt-dlp.sh) downloads the official Linux binary, verifies the upstream SHA-256 checksum, keeps a backup, and performs a version smoke test. It bypasses the plugin's self-updater; it does not yet patch the plugin's Update button.

## Upstream YouTube plugin source mirror

A GitHub Actions workflow mirrors the upstream [philippe44/LMS-YouTube](https://github.com/philippe44/LMS-YouTube) add-on source into [`vendor/LMS-YouTube/`](vendor/LMS-YouTube/). The mirror is for source inspection and development; it does not automatically install or replace the plugin on QNAP. See [docs/YOUTUBE-MIRROR.md](docs/YOUTUBE-MIRROR.md) for the workflow and status-check instructions.

## Development and release

- Plugin source: UnifiedSearch/Plugin.pm
- Repository template: repo.xml.in
- Release workflow: .github/workflows/release.yml

The GitHub Actions workflow packages all add-ons using the versions in their respective `install.xml` files, calculates their SHA-1 hashes, updates `repo.xml`, and publishes a release tagged with the UnifiedSearch version. Bump the version of each changed add-on before publishing a new release.

Disabling an add-on removes its contribution after the LMS web page is refreshed. Unified Search deregisters its Global Search provider and removes its Default and Material app menu entries; Default Logo Home returns the original server-rendered logo link. YouTube Cast automatically intercepts YouTube tracks only for players with a configured Chromecast host; unloading the plugin restores the original YouTube protocol handler.

DefaultLogoHome changes the logo link in the server-rendered Default skin home page to the LMS root, not the skin-specific `/Default/` path. The package still needs an end-to-end check on the target LMS installation, including the Material Apps entry and SpotOn results.
