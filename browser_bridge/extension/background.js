chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === "complete") {
    chrome.scripting.executeScript({
      target: {tabId},
      files: ["content.js"]
    }).catch(() => {});
  }
});

const BRIDGE_BASE = "http://127.0.0.1:8765";

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== "bridge_fetch") return false;

  const path = message.path || "/";
  const options = message.options || {};
  fetch(BRIDGE_BASE + path, options)
    .then(async (response) => {
      const text = await response.text();
      let body;
      try {
        body = JSON.parse(text);
      } catch {
        body = text;
      }
      sendResponse({ok: response.ok, status: response.status, body});
    })
    .catch((error) => {
      sendResponse({ok: false, error: String(error)});
    });

  return true;
});
