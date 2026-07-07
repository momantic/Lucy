# Lucy Browser Bridge — Chrome Web Store Submission Checklist

This checklist prepares the Lucy Browser Bridge extension for Chrome Web Store submission. The upload package has been built locally at:

```text
release/lucy-browser-bridge-webstore-v0.2.0.zip
```

## Extension package

- Name: `Lucy Browser Bridge`
- Version: `0.2.0`
- Manifest: Manifest V3
- Permissions: `activeTab`, `scripting`
- Host permissions: `http://127.0.0.1:8765/*`
- User action: click the extension icon to send the active page to Lucy
- Privacy policy URL: `https://momantic.github.io/Lucy/privacy.html`

## Store listing copy

### Short description

Send the current webpage to the local Lucy desktop app for private, on-device AI assistance.

### Detailed description

Lucy Browser Bridge connects Chrome to the Lucy desktop app running locally on your Mac. When you click the extension icon, it captures text from the current active tab and sends it to Lucy through a localhost bridge. Lucy can then summarize, extract, and help draft from the page content.

Lucy Browser Bridge is privacy-first: it does not send webpage content to third-party servers, does not sell data, and only reads the active page after you click the extension icon.

### Single purpose statement

Lucy Browser Bridge lets users send the currently active webpage to the local Lucy desktop app so Lucy can process the page privately on the user's Mac.

### Permission justification

- `activeTab`: Allows Lucy Browser Bridge to read the current tab only after the user clicks the extension icon.
- `scripting`: Injects the page-capture script into the active tab after the user clicks the extension icon.
- `http://127.0.0.1:8765/*`: Sends captured page text to the Lucy desktop bridge running locally on the user's Mac.

## Dashboard steps that require the owner account

1. Open the Chrome Web Store Developer Dashboard.
2. Pay/confirm the Chrome Web Store developer registration if the account has not been activated yet.
3. Create a new item.
4. Upload `release/lucy-browser-bridge-webstore-v0.2.0.zip`.
5. Fill in the listing fields using the copy above.
6. Set the privacy policy URL to `https://momantic.github.io/Lucy/privacy.html` after the website changes are published.
7. Upload required screenshots and promotional images.
8. Complete the data usage and permissions declarations.
9. Submit for review.

## Important note

Published listing:

https://chromewebstore.google.com/detail/lucy-bridge/annlbnhnlflpofdjlmdmfebcgakhlccn

The Lucy website should point users to this Chrome Web Store listing for one-click extension install. Developer Mode / Load unpacked instructions are no longer the primary public install path.