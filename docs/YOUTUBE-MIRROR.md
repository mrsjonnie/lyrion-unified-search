# YouTube plugin mirror

This repository is intended to keep a source mirror of the upstream LMS YouTube add-on from [philippe44/LMS-YouTube](https://github.com/philippe44/LMS-YouTube).

## Where the mirrored add-on lives

The workflow copies the upstream plugin source into [`vendor/LMS-YouTube/`](../vendor/LMS-YouTube/) and records the upstream commit in `UPSTREAM_COMMIT` plus its source URL in `UPSTREAM_SOURCE.txt`.

This is a source mirror for inspection and development. It does not automatically replace the installed YouTube plugin on the QNAP, and it does not by itself fix the QPKG `libutil.so.1` error in the plugin's built-in yt-dlp updater.

## Refresh the mirror

GitHub Actions workflow: [Mirror upstream LMS-YouTube source](../.github/workflows/mirror-lms-youtube.yml). It can be run manually from the Actions tab (`workflow_dispatch`) or is triggered by changes to its workflow file. After a successful run, check `vendor/LMS-YouTube/` for the complete upstream source.

Upstream project: https://github.com/philippe44/LMS-YouTube
