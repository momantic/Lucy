chrome.action.onClicked.addListener(async (tab) => {
  if (!tab.id) return;

  chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: () => {
      const pageText = document.body.innerText;

      console.log("📤 Sending page to Lucy Bridge:");
      console.log(pageText);

      // TODO: connect to local Lucy app (future step)
      alert("Lucy Bridge active. Page captured in console.");
    }
  });
});
