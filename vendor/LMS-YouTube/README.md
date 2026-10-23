# Upstream LMS-YouTube mirror

This directory is populated by the GitHub Actions workflow `.github/workflows/mirror-lms-youtube.yml`.

- Upstream project: https://github.com/philippe44/LMS-YouTube
- The exact upstream commit is recorded in `UPSTREAM_COMMIT`.
- This is a source mirror for review and development; it does not automatically install anything on the QNAP NAS.
- Preserve upstream copyright notices and license files when modifying or redistributing the plugin.

## Refresh

Open the repository's **Actions** tab, select **Mirror upstream LMS-YouTube source**, choose **Run workflow**, and optionally provide a branch/tag/commit. The workflow commits the complete upstream source tree under `vendor/LMS-YouTube/`.
