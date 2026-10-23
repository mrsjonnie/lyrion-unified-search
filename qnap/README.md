# QNAP LMS YouTube / yt-dlp workaround

The LMS YouTube plugin's built-in **Update yt-dlp** action can fail on QNAP QPKG/chroot installations with:

```
Failed to load Python shared library ... libpython3.13.so.1.0:
libutil.so.1: cannot open shared object file
```

Do not copy arbitrary host libraries into the QPKG chroot. Instead, use the external updater script in this folder. It downloads the official upstream `yt-dlp_linux` release, verifies it against upstream `SHA2-256SUMS`, keeps a timestamped backup, and swaps the binary only after checksum validation.

## Run on QNAP

1. Copy `update-yt-dlp.sh` to the NAS.
2. Make it executable: `chmod 755 update-yt-dlp.sh`.
3. Run it as an account allowed to replace the plugin binary:

   ```sh
   sudo ./update-yt-dlp.sh
   ```

The default target is:

```
/share/CACHEDEV1_DATA/.qpkg/LogitechMediaServer/SlimServer/Cache/InstalledPlugins/Plugins/YouTube/Bin/yt-dlp_linux
```

To specify another target path, pass it as the first argument. The script requires `curl`, `sha256sum`, `awk`, `sed`, `mktemp`, and `date`.

## Important limitation

This is a verified **manual binary updater**, not a fix to the LMS plugin's built-in Update button. That button runs plugin-owned update logic, so making it work requires patching the exact YouTube plugin source installed in the QPKG and validating the changed action against that version. The repository's Unified Search / YouTube Cast code is not the upstream LMS YouTube plugin itself.

The official standalone `yt-dlp_linux` is a PyInstaller executable. If the QNAP runtime cannot load a required system library, simply mirroring a newer release may not resolve that dependency error. The script's `--version` smoke test checks whether the replacement starts, but playback and the plugin UI must still be tested on the NAS.

## Upstream references

- Releases: https://github.com/yt-dlp/yt-dlp/releases
- Checksums and release documentation: https://github.com/yt-dlp/yt-dlp
