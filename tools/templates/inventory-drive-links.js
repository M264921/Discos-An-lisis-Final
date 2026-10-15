(function (root) {
  "use strict";

  function createDriveLinks({ fetch, candidates, protocol, timeout = 1800 }) {
    let drives = new Set();
    let base = "";
    let pending = null;
    const listeners = new Set();

    async function refresh() {
      if (pending) return pending;
      pending = (async () => {
        let next = new Set();
        let nextBase = "";
        for (const candidate of candidates) {
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), timeout);
          try {
            const response = await fetch(candidate + "/drives", {
              cache: "no-store", credentials: "omit", signal: controller.signal
            });
            if (!response.ok) continue;
            const data = await response.json();
            if (data.service !== "MingoMedia.files" || !Array.isArray(data.drives)) continue;
            next = new Set(data.drives.filter(key => typeof key === "string" && /^[A-Z]$/.test(key)));
            nextBase = candidate;
            break;
          } catch (_) {
            // A disconnected helper leaves the inventory readable, without local links.
          } finally {
            clearTimeout(timer);
          }
        }
        drives = next;
        base = nextBase;
        listeners.forEach(listener => listener());
      })().finally(() => { pending = null; });
      return pending;
    }

    function url(fileUrl, { folder = false } = {}) {
      let parsed;
      try { parsed = new URL(fileUrl); } catch (_) { return ""; }
      if (parsed.protocol !== "file:" || parsed.host) return "";
      const match = parsed.pathname.match(/^\/([A-Za-z]):\/(.*)$/);
      if (!match || !drives.has(match[1].toUpperCase())) return "";
      if (protocol === "file:") return parsed.href;
      // Browsers block file: navigation from HTTP pages; use the local file service.
      // Folder navigation remains local: the service deliberately serves files only.
      if (folder || !match[2] || match[2].endsWith("/")) return "";
      return base + "/files/" + match[1].toUpperCase() + "/" + match[2];
    }

    return { refresh, url, onChange(listener) { listeners.add(listener); } };
  }

  function decorateLink(anchor, state) {
    const remembered = anchor.getAttribute("data-mingo-local-url");
    const href = anchor.getAttribute("href") || "";
    if (!remembered && !/^file:/i.test(href)) return;
    const original = remembered || href;
    if (!remembered) {
      anchor.setAttribute("data-mingo-local-url", original);
      anchor.setAttribute("data-mingo-link-title", anchor.getAttribute("title") || "");
    }
    const availableUrl = state.url(original, { folder: /carpeta/i.test(anchor.getAttribute("data-mingo-link-title") || "") });
    if (availableUrl) {
      if (href !== availableUrl) anchor.setAttribute("href", availableUrl);
      anchor.removeAttribute("data-mingo-unavailable");
      anchor.removeAttribute("aria-disabled");
      anchor.setAttribute("title", anchor.getAttribute("data-mingo-link-title"));
    } else {
      if (href) anchor.removeAttribute("href");
      anchor.setAttribute("data-mingo-unavailable", "true");
      anchor.setAttribute("aria-disabled", "true");
      anchor.setAttribute("title", "Unidad no disponible en este equipo");
    }
  }

  if (typeof module === "object" && module.exports) {
    module.exports = { createDriveLinks, decorateLink };
    return;
  }
  if (!root || !root.document) return;
  if (root.mingoDriveLinks) return;

  const document = root.document;
  const query = new URL(root.location.href).searchParams;
  const configured = query.get("fileServer") || (root.MingoMediaConfig || {}).fileServerBase;
  const candidates = [];
  function addCandidate(value) {
    try {
      const url = new URL(value);
      if (!/^https?:$/.test(url.protocol) || url.username || url.password) return;
      const base = url.href.replace(/\/$/, "");
      if (!candidates.includes(base)) candidates.push(base);
    } catch (_) { /* No endpoint, no local links. */ }
  }
  if (configured) {
    addCandidate(configured);
  } else {
    if (["localhost", "127.0.0.1", "[::1]"].includes(root.location.hostname)) addCandidate(root.location.origin);
    addCandidate("http://127.0.0.1:8765");
  }
  const state = createDriveLinks({ fetch: root.fetch.bind(root), candidates, protocol: root.location.protocol });
  root.mingoDriveLinks = state;
  function update(node) {
    if (node.nodeType !== 1) return;
    if (node.matches("a")) decorateLink(node, state);
    node.querySelectorAll('a[href^="file:"], a[data-mingo-local-url]').forEach(anchor => decorateLink(anchor, state));
  }
  const observer = new MutationObserver(mutations => {
    mutations.forEach(mutation => {
      if (mutation.type === "attributes") decorateLink(mutation.target, state);
      else mutation.addedNodes.forEach(update);
    });
  });
  observer.observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ["href"] });
  const style = document.createElement("style");
  style.textContent = 'a[data-mingo-unavailable]{color:inherit;text-decoration:none;cursor:default}';
  document.head.appendChild(style);
  update(document.documentElement);
  state.onChange(() => update(document.documentElement));
  root.addEventListener("focus", () => state.refresh());
  root.addEventListener("pageshow", () => state.refresh());
  document.addEventListener("visibilitychange", () => { if (!document.hidden) state.refresh(); });
  document.addEventListener("click", event => {
    const anchor = event.target.closest ? event.target.closest("a[data-mingo-unavailable]") : null;
    if (anchor) { event.preventDefault(); event.stopImmediatePropagation(); }
  }, true);
  state.refresh();
})(typeof window === "undefined" ? null : window);
