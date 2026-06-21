async function sendPage() {
  const text = document.body ? document.body.innerText : "";
  await fetch("http://127.0.0.1:8765/page", {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({
      url: location.href,
      title: document.title,
      text
    })
  }).catch(() => {});
}

async function pollCommands() {
  try {
    const res = await fetch("http://127.0.0.1:8765/next_command");
    const data = await res.json();
    const cmd = data.command;
    if (!cmd) return;

    if (cmd.type === "read_page") {
      await sendPage();
    }

    if (cmd.type === "click_text") {
      const target = (cmd.text || "").toLowerCase();
      const els = [...document.querySelectorAll("button,a,span,div")];
      const el = els.find(e => (e.innerText || "").toLowerCase().includes(target));
      if (el) el.click();
      await sendPage();
    }

    if (cmd.type === "type_text") {
      const active = document.activeElement;
      if (active) {
        active.focus();
        active.value = cmd.text || "";
        active.dispatchEvent(new Event("input", {bubbles: true}));
      }
      await sendPage();
    }
  } catch {}
}

sendPage();
setInterval(sendPage, 3000);
setInterval(pollCommands, 1000);
