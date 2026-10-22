# Lyrion Unified Search

A standalone add-on for Lyrion Music Server (LMS). It adds a **Unified Search** entry to LMS's **My Music / Browse Library** menu so one query can be routed to the local library, YouTube, or Spotify through SpotOn.

## How it works

1. Open **My Music / Browse Library → Unified Search**.
2. Enter one search term.
3. Choose the source to open its existing results:
   - **Local library (LMS)** — opens LMS's native track search for that query.
   - **YouTube** — calls the installed YouTube plugin's existing search handler.
   - **Spotify (SpotOn)** — calls SpotOn's existing search-feed callback.

The source choice is one extra click after the query. The results themselves remain rendered and played by their existing LMS/plugin integrations; this add-on does not duplicate search APIs or playback logic.

## Compatibility and safety

- LMS 8.0 or newer.
- YouTube and SpotOn are optional; their entries are shown only when their plugin and search callback are available.
- Uses LMS's supported `Slim::Menu::BrowseLibrary->registerNode` extension point.
- Does not modify Material Skin, the Default skin, LMS core, YouTube, SpotOn, or their configuration files.
- The local-library result uses LMS's native Browse Library track-search callback; no hard-coded home-network URL is used.

## Install

The currently published release is still the previous stable version. This branch is a development draft and is not published as an installable release yet. Do not install it until the query flow and all three providers have been tested on a real LMS instance.

Add the repository in **LMS Settings → Plugins → Additional Repositories** after a release is published:

```
https://raw.githubusercontent.com/mrsjonnie/lyrion-unified-search/main/repo.xml
```

## Validation still required

Before release, test on the target LMS instance:

- Plugin loads and the Unified Search item appears under Browse Library.
- A query returns the local-library entry.
- YouTube results open when the YouTube plugin is enabled.
- SpotOn results open when SpotOn is enabled.
- Missing optional plugins do not prevent the other sources from working.
- Disabling/uninstalling Unified Search removes only its own Browse Library node.

## Development

- Plugin source: `UnifiedSearch/Plugin.pm`
- Repository descriptor: `repo.xml`
- Release workflow: `.github/workflows/release.yml`
