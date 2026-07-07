const BRIDGE_BASE = "http://127.0.0.1:8765";

async function sendActivePageToLucy(tab) {
  if (!tab || !tab.id || !tab.url || !/^https?:/i.test(tab.url)) {
    return;
  }

  try {
    await chrome.scripting.executeScript({
      target: {tabId: tab.id},
      files: ["content.js"]
    });

    chrome.tabs.sendMessage(tab.id, {type: "lucy_capture_page"}, (response) => {
      const failed = chrome.runtime.lastError || !response || response.ok === false;
      chrome.action.setBadgeText({tabId: tab.id, text: failed ? "!" : "✓"});
      chrome.action.setBadgeBackgroundColor({tabId: tab.id, color: failed ? "#ff5c7a" : "#00d4ff"});
      setTimeout(() => chrome.action.setBadgeText({tabId: tab.id, text: ""}), 1600);
    });
  } catch {
    chrome.action.setBadgeText({tabId: tab.id, text: "!"});
    chrome.action.setBadgeBackgroundColor({tabId: tab.id, color: "#ff5c7a"});
    setTimeout(() => chrome.action.setBadgeText({tabId: tab.id, text: ""}), 1600);
  }
}

chrome.action.onClicked.addListener((tab) => {
  sendActivePageToLucy(tab).catch(() => {});
});

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
