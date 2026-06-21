chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === "complete") {
    chrome.scripting.executeScript({
      target: {tabId},
      files: ["content.js"]
    }).catch(() => {});
  }
});
