# Lyrion Unified Search

A small add-on for Lyrion Music Server (LMS) that adds search entries to LMS Global Search, including Material Skin's existing `globalsearch` items request.

## What it does

- Adds a **Local library** item that opens the LMS web search page.
- Adds **Spotify (SpotOn)** as a direct search item by calling SpotOn's existing search-feed callback.
- Leaves native search providers such as YouTube intact.
- Works around Material Skin's client-side allowlist, which otherwise removes custom Global Search source titles from the search results.
- Uses Material Skin's supported `custom.js` hook. It appends a clearly marked block to the Material Skin preferences file and preserves any existing user JavaScript.
- Removes only its marked JavaScript block when the plugin shuts down; on a normal LMS restart, plugin startup installs it again. This also means disabling/removing the plugin does not leave its hook behind.
- The hook only adds the two source names to Material Skin's filter. It does not replace or patch Material Skin's own files.

## Compatibility and requirements

- LMS 8.0 or newer.
- Material Skin is required for the client-side filter workaround; without it the LMS search provider still registers, but the hook is skipped.
- SpotOn is optional; the Spotify entry appears only when `Plugins::SpotOn::Plugin` and its existing search callback are available.
- The local-library URL currently targets `http://192.168.178.99:9001`, the LMS address used for this installation. Change it if LMS is hosted elsewhere.

## Install

Add this repository in **LMS Settings → Plugins → Additional Repositories**:

https://raw.githubusercontent.com/mrsjonnie/lyrion-unified-search/main/repo.xml

Click **Apply**, install **Lyrion Unified Search**, and restart LMS if requested.

## Development and release

- Plugin source: `UnifiedSearch/Plugin.pm`
- Repository template: `repo.xml.in`
- Release workflow: `.github/workflows/release.yml`

The GitHub Actions workflow packages both add-ons, calculates their SHA-1 hashes, updates `repo.xml`, and publishes the version declared in `UnifiedSearch/install.xml`. Bump that version before publishing a new release.

## Validation still required

The source-level workaround is implemented, but it needs an end-to-end check on the target LMS/Material Skin installation. Confirm that both source entries appear in the Material Skin global search results, that Spotify opens SpotOn's results, and that a pre-existing `custom.js` remains intact through restart and plugin disable/enable.
