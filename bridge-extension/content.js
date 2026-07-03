function bridgeFetch(path, options = {}) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage({type: "bridge_fetch", path, options}, (response) => {
      if (chrome.runtime.lastError) {
        resolve({ok: false, error: chrome.runtime.lastError.message});
        return;
      }
      resolve(response || {ok: false, error: "empty bridge response"});
    });
  });
}

function cleanText(value) {
  return String(value || "")
    .replace(/\u00a0/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function textFromFirst(root, selectors) {
  for (const selector of selectors) {
    const el = root.querySelector(selector);
    const text = cleanText(el && el.innerText);
    if (text) return text;
  }
  return "";
}

function hrefFromFirst(root, selectors) {
  for (const selector of selectors) {
    const el = root.querySelector(selector);
    const href = el && el.href;
    if (href) return href.split("?")[0];
  }
  return "";
}

function looksLikeLinkedInPostText(text) {
  const words = cleanText(text).split(/\s+/).filter(Boolean).length;
  if (words < 8) return false;
  const lower = text.toLowerCase();
  const noisy = [
    "linkedin", "home", "my network", "jobs", "messaging", "notifications",
    "premium", "people also viewed", "promoted", "show more results"
  ];
  return noisy.filter((token) => lower.includes(token)).length < 4;
}

function extractLinkedInPostText(card) {
  const textSelectors = [
    ".update-components-text",
    ".feed-shared-update-v2__description",
    ".feed-shared-text",
    ".feed-shared-inline-show-more-text",
    ".entity-result__summary",
    ".entity-result__content-summary",
    "[data-test-id='main-feed-activity-card'] [dir='ltr']",
    "[dir='ltr']"
  ];
  const pieces = [];
  for (const selector of textSelectors) {
    for (const el of card.querySelectorAll(selector)) {
      const text = cleanText(el.innerText);
      if (looksLikeLinkedInPostText(text) && !pieces.some((p) => p.includes(text) || text.includes(p))) {
        pieces.push(text);
      }
    }
  }
  if (pieces.length) return pieces.slice(0, 3).join("\n\n");

  const rejectedLine = /^(like|comment|repost|send|follow|connect|message|view profile|show more|see more|share|save|copy link|report|more|activate to view larger image)$/i;
  const lines = cleanText(card.innerText)
    .split("\n")
    .map(cleanText)
    .filter(Boolean)
    .filter((line) => !rejectedLine.test(line))
    .filter((line) => !/^\d+\s*( reactions?| comments?| reposts?)$/i.test(line));
  return lines.slice(0, 10).join("\n");
}

function extractLinkedInPosts() {
  if (!/\blinkedin\.com\b/i.test(location.hostname)) return [];

  const selectors = [
    "div.feed-shared-update-v2",
    "[data-urn*='activity']",
    "[data-test-id='main-feed-activity-card']",
    ".reusable-search__result-container",
    ".entity-result"
  ];
  const cards = [];
  for (const selector of selectors) {
    for (const el of document.querySelectorAll(selector)) {
      if (!(el instanceof HTMLElement)) continue;
      if (cards.some((existing) => existing === el || existing.contains(el) || el.contains(existing))) continue;
      if (cleanText(el.innerText).split(/\s+/).length < 12) continue;
      cards.push(el);
    }
  }

  const posts = [];
  const seen = new Set();
  for (const card of cards) {
    const author = textFromFirst(card, [
      ".update-components-actor__title span[aria-hidden='true']",
      ".feed-shared-actor__name",
      ".entity-result__title-text a span[aria-hidden='true']",
      ".entity-result__title-text",
      "a[href*='/in/']"
    ]).split("\n")[0];
    const headline = textFromFirst(card, [
      ".update-components-actor__description",
      ".feed-shared-actor__description",
      ".entity-result__primary-subtitle",
      ".entity-result__secondary-subtitle"
    ]).split("\n")[0];
    const postText = cleanText(extractLinkedInPostText(card));
    if (!looksLikeLinkedInPostText(postText)) continue;

    const key = postText.slice(0, 220).toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    const reactionText = textFromFirst(card, [
      ".social-details-social-counts",
      ".feed-shared-social-counts",
      ".social-details-social-activity"
    ]);
    posts.push({
      rank: posts.length + 1,
      author,
      headline,
      text: postText.slice(0, 3000),
      url: hrefFromFirst(card, ["a[href*='/feed/update/']", "a[href*='activity-']", "a[href*='/posts/']"]),
      engagement: reactionText.slice(0, 500)
    });
    if (posts.length >= 8) break;
  }
  return posts;
}

function formatLinkedInPosts(posts) {
  if (!posts.length) return "";
  return ["LinkedIn top visible posts captured from the current page:", ...posts.map((post) => {
    const lines = [`Post ${post.rank}`];
    if (post.author) lines.push(`Author: ${post.author}`);
    if (post.headline) lines.push(`Headline: ${post.headline}`);
    if (post.url) lines.push(`URL: ${post.url}`);
    if (post.engagement) lines.push(`Engagement text: ${post.engagement}`);
    lines.push("Text:");
    lines.push(post.text);
    return lines.join("\n");
  })].join("\n\n---\n\n");
}

function capturePage() {
  const rawText = document.body ? cleanText(document.body.innerText) : "";
  const linkedinPosts = extractLinkedInPosts();
  const linkedinText = formatLinkedInPosts(linkedinPosts);
  return {
    rawText,
    linkedinPosts,
    text: linkedinText || rawText
  };
}

async function sendPage() {
  const capture = capturePage();
  await bridgeFetch("/page", {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({
      url: location.href,
      title: document.title,
      text: capture.text,
      rawText: capture.rawText,
      linkedinPosts: capture.linkedinPosts
    })
  }).catch(() => {});
}

async function pollCommands() {
  try {
    const data = (await bridgeFetch("/next_command?url=" + encodeURIComponent(location.href))).body || {};
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
