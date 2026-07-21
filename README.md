Added a self-dev smoke test command /selfdevcheck
Usage: /selfdevcheck
Purpose: Perform a self-dev smoke test to ensure the development environment is functioning correctly.

## Local model compatibility

Lucy now uses an auto-selected local model provider:

- Apple Silicon Macs use MLX by default.
- Intel Macs use a local GGUF model through llama.cpp / llama-cpp-python.
- Cloud APIs remain disabled by default.

For older non-Apple-Silicon Macs, see `docs/intel-mac-local-llm.md` and run:

```zsh
tools/setup_local_llm_intel.sh
```

If you use the Intel setup virtual environment inside the Lucy release/source folder, Lucy now auto-detects that `.venv-local-llm` Python when the app starts. After setup, add a GGUF model under `assets/models` and launch Lucy normally from the same folder.

You can still force that Python manually for debugging:

```zsh
PYTHON="$PWD/.venv-local-llm/bin/python" ./Lucy.app/Contents/MacOS/Lucy
```

## Private/local install without Apple Developer ID

Public Lucy ZIP downloads need Developer ID signing and notarization for the
normal macOS double-click experience. If a browser-downloaded build is not
notarized, macOS may say Lucy is “damaged” or refuse to open it through
Gatekeeper.

For private beta testing on your own Mac, use the local no-cert installer
instead. It builds or repairs Lucy locally, clears browser quarantine metadata
where macOS allows it, ad-hoc signs the app on your Mac, and opens it:

```zsh
zsh ./install_lucy_local_no_cert.sh
```

To repair a private QA ZIP you already downloaded:

```zsh
zsh ./install_lucy_local_no_cert.sh --zip ~/Downloads/Lucy-v0.1-beta.zip
```

If the private ZIP already includes the helper, you can also run it from the
extracted release folder:

```zsh
cd ~/Downloads/Lucy-v0.1-beta
zsh ./install_lucy_local_no_cert.sh --direct-launch
```

If macOS still blocks Finder/LaunchServices opening for an ad-hoc signed app,
launch the executable directly from Terminal:

```zsh
zsh ./install_lucy_local_no_cert.sh --zip ~/Downloads/Lucy-v0.1-beta.zip --direct-launch
```

This is not a replacement for Developer ID notarization for public downloads;
it is a repeatable local/private workaround that avoids Apple certification.

## Publish the live downloadable ZIP

The live install page downloads this GitHub Release asset:

```text
https://github.com/momantic/Lucy/releases/latest/download/Lucy-v0.1-beta.zip
```

After rebuilding `release/Lucy-v0.1-beta.zip`, replace the GitHub Release asset
with:

```zsh
GITHUB_TOKEN="your-token-with-release-permission" zsh ./publish_lucy_release_asset.sh
```

The current private no-cert ZIP should then install smoothly via the install
page’s Terminal command because the ZIP includes `install_lucy_local_no_cert.sh`.

Pushing changes to `main` also runs the private no-cert release workflow at
`.github/workflows/release-macos-private-nocert.yml`, which rebuilds the ZIP on
GitHub Actions and replaces the live `Lucy-v0.1-beta.zip` release asset using
GitHub’s built-in workflow token.

## Private Lucy download tracker

Lucy includes a tiny backend tracker at `backend/download_tracker.py`. It counts
downloads in SQLite, redirects users to the real GitHub release ZIP, and gives
you a token-protected real-time dashboard.

Run locally for testing:

```zsh
LUCY_TRACKER_TOKEN="replace-with-a-long-secret" python3 backend/download_tracker.py
```

Open your private dashboard:

```text
http://127.0.0.1:8787/dashboard?token=replace-with-a-long-secret
```

Public download links should point at:

```text
https://your-tracker-host.example/d/lucy?source=home-hero
```

The static docs keep direct GitHub links by default. To make the buttons and the
install command use the tracker, edit `docs/download-tracker-config.js` and set:

```js
window.LUCY_DOWNLOAD_TRACKER_BASE = "https://your-tracker-host.example";
```