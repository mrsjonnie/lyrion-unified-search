# Lyrion Unified Search

An add-on for Lyrion Music Server (LMS) to bring searches from multiple providers into one place.

## Goals

- Provide a unified search entry point for the LMS music library and supported search providers.
- Keep the add-on separate from Material Skin, YouTube, SpotOn, and other existing plugins.
- Make installation and removal through LMS repository/plugin management straightforward.
- Avoid changing existing LMS or plugin configuration outside this add-on's own files.

## Status

Initial project scaffold. Provider integrations and the LMS plugin/repository packaging still need implementation and testing against the target LMS version.

## Development principles

- Inspect the actual LMS and provider plugin interfaces before implementing integrations.
- Fail gracefully when a provider is missing or unavailable.
- Keep configuration scoped to this plugin.
- Document installation, configuration, troubleshooting, and uninstall behavior.
