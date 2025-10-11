(() => {

  "use strict";



  // --- Config ---

  const preferenceStorageKey = "inventory.openWithPreference";

  const dlnaEndpointStorageKey = "inventory.dlnaEndpoint";

  const defaultDlnaEndpoints = ["http://127.0.0.1:8787", "http://localhost:8787"];

  const KNOWN = {

    video: [".mp4", ".webm", ".mkv", ".mov", ".m3u8"],

    audio: [".mp3", ".aac", ".m4a", ".flac", ".wav", ".ogg"],

    image: [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".avif"],

    pdf: [".pdf"],

    text: [".txt", ".md", ".log", ".csv", ".json", ".xml", ".yaml", ".yml"],

    html: [".html", ".htm"]

  };



  const currentUrl = new URL(window.location.href);

  const DLNA_WS = currentUrl.searchParams.get("dlnaHelper") || window.DLNA_HELPER_WS || "";

  const DLNA_API = currentUrl.searchParams.get("dlnaApi") || window.DLNA_HELPER_HTTP || "";



  // --- Header: Remote Playback picker global ---

  const remotePlaybackSupported = (() => {

    if (typeof document === "undefined" || typeof HTMLMediaElement === "undefined") {

      return false;

    }

    try {

      const probe = document.createElement("video");

      const globalRemote = "remote" in HTMLMediaElement.prototype;

      const elementRemote = probe && "remote" in probe;

      return Boolean(globalRemote || elementRemote);

    } catch (_) {

      return false;

    }

  })();



  const globalSelect = document.getElementById("globalPlayerSelect");

  const modal = document.getElementById("openWithModal");

  const modalDialog = modal ? modal.querySelector(".ow-dialog") : null;

  const owFileName = document.getElementById("owFileName");

  const owButtons = modal ? modal.querySelectorAll(".ow-actions button[data-action]") : [];

  const airplayBtn = document.getElementById("airplayBtn");

  let modalMessage = modal ? modal.querySelector(".ow-message") : null;

  if (window.WebKitPlaybackTargetAvailabilityEvent && airplayBtn) {

    const tempVideo = document.createElement("video");

    tempVideo.addEventListener("webkitplaybacktargetavailabilitychanged", (event) => {

      if (!event || !event.target) {

        return;

      }

      airplayBtn.hidden = event.availability !== "available";

    });

    airplayBtn.addEventListener("click", () => {

      try {

        tempVideo.webkitShowPlaybackTargetPicker();

      } catch (error) {

        console.warn("AirPlay picker failed", error);

      }

    });

  } else if (airplayBtn) {

    airplayBtn.hidden = true;

  }



  if (!globalSelect || !modal || !modalDialog || !owFileName) {

    return;

  }



  const browserPickerOption = globalSelect.querySelector('option[value="browser-picker"]');

  if (browserPickerOption && !globalSupportsRemotePlayback()) {

    browserPickerOption.disabled = true;

    browserPickerOption.hidden = true;

  }



  const state = {

    current: null,

    currentHref: "",

    currentType: null,

    preference: "auto",

    dlnaDevices: [],

    dlnaEndpoint: null,

    remoteProbe: null,

    dlnaWs: DLNA_WS || ""

  };



  const overlayStack = [];



  initialisePreference();

  wireUi();

  createRemoteProbe();

  discoverDlnaDevices();

  setupDlnaWebSocket();

  function registerOverlay(element, onClose) {

    if (!element) {

      return function () {

        /* noop */

      };

    }

    let closed = false;

    function closeOverlay() {

      if (closed) {

        return;

      }

      closed = true;

      const index = overlayStack.indexOf(closeOverlay);

      if (index >= 0) {

        overlayStack.splice(index, 1);

      }

      if (typeof onClose === "function") {

        try {

          onClose();

        } catch (_) {

          /* ignore */

        }

      }

    }

    overlayStack.push(closeOverlay);

    return closeOverlay;

  }

  function initialisePreference() {

    let storedPreference = null;

    try {

      storedPreference = window.localStorage.getItem(preferenceStorageKey);

    } catch (_) {

      storedPreference = null;

    }



    if (storedPreference && isValidPreference(storedPreference)) {

      state.preference = storedPreference;

    }



    if (state.preference === "browser-picker" && !globalSupportsRemotePlayback()) {

      state.preference = "auto";

    }



    globalSelect.value = state.preference;



    globalSelect.addEventListener("change", async function (event) {

      const next = event.target.value;

      state.preference = isValidPreference(next) ? next : "auto";

      try {

        window.localStorage.setItem(preferenceStorageKey, state.preference);

      } catch (_) {

        /* ignore */

      }

      if (state.preference === "browser-picker") {

        await ensureRemotePickerPrimed();

      }

      await updateDlnaButton();

    });

  }



  function isValidPreference(value) {

    if (!value) {

      return false;

    }

    if (value === "auto" || value === "local" || value === "choose") {

      return true;

    }

    if (value === "browser-picker") {

      return globalSupportsRemotePlayback();

    }

    return value.startsWith("dlna:");

  }



  function wireUi() {

    // --- Nota: si quieres excluir zonas (p.ej. nav), añade data-no-intercept a contenedores ---

    // <nav data-no-intercept>...</nav>

    document.addEventListener('click', (e) => {
      const blocker = e.target instanceof Element ? e.target.closest('[data-no-intercept]') : null;
      if (blocker) {
        return;
      }
      handleDocumentClick(e);
    }, true);



    modal.addEventListener("click", function (event) {

      if (!(event.target instanceof Element)) {

        return;

      }

      const closer = event.target.closest("[data-ow-close]");

      if (closer) {

        closeModal();

      }

    });



    document.addEventListener("keydown", function (event) {

      if (event.key === "Escape") {

        if (!modal.hidden) {

          closeModal();

        } else if (overlayStack.length > 0) {

          const closeOverlay = overlayStack[overlayStack.length - 1];

          if (typeof closeOverlay === "function") {

            closeOverlay();

          }

        }

      }

    });



    owButtons.forEach(function (button) {

      button.addEventListener("click", async function (event) {

        const action = event.currentTarget.dataset.action;

        if (!action || !state.currentHref) {

          return;

        }

        try {

          switch (action) {

            case "new-tab":

              window.open(state.currentHref, "_blank", "noopener");

              hideModal();

              return;

            case "download":

              const tempLink = document.createElement("a");

              tempLink.href = state.currentHref;

              tempLink.download = "";

              document.body.appendChild(tempLink);

              tempLink.click();

              tempLink.remove();

              hideModal();

              return;

            case "open-local":

              const openedLocally = openLocal(state.currentHref, state.currentType);

              if (openedLocally) {

                hideModal();

              } else {

                showMessage("No se pudo abrir en este navegador.");

              }

              return;

            case "browser-picker":

              if (!isMedia(state.currentType) || !globalSupportsRemotePlayback()) {

                return;

              }

              const success = await launchBrowserPicker({ href: state.currentHref, type: state.currentType });

              if (success) {

                hideModal();

              } else {

                showMessage("No se pudo iniciar la reproduccion remota.");

              }

              return;

            case "dlna":

              await handleDlnaAction();

              return;

            default:

              await executeAction(action);

              break;

          }

        } catch (error) {

          console.warn("Accion del modal fallo:", error);

          showMessage("No se pudo completar la accion solicitada.");

        }

      });

    });



    if (airplayBtn) {

      airplayBtn.addEventListener("click", function () {

        if (!state.remoteProbe) {

          return;

        }

        try {

          if (typeof state.remoteProbe.webkitShowPlaybackTargetPicker === "function") {

            state.remoteProbe.webkitShowPlaybackTargetPicker();

          } else if (state.remoteProbe.remote && typeof state.remoteProbe.remote.prompt === "function") {

            state.remoteProbe.remote.prompt().catch(function () {

              /* ignore */

            });

          }

        } catch (error) {

          console.warn("AirPlay prompt failed", error);

        }

      });

    }

  }



  function handleDocumentClick(event) {

    if (!event || event.defaultPrevented) {

      return;

    }



    const anchor = event.target instanceof Element ? event.target.closest("a[href]") : null;

    if (!anchor) {

      return;

    }



    if (anchor.closest(".ow-modal")) {

      return;

    }



    if (anchor.hasAttribute("download") || anchor.getAttribute("target") === "_blank") {

      return;

    }



    const href = anchor.getAttribute("href");

    if (!href) {

      return;

    }



    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button === 1) {

      return;

    }



    const url = resolveUrl(href);

    if (!url || !shouldIntercept(url)) {

      return;

    }



    const context = buildContext(anchor, url);

    if (!context) {

      return;

    }



    const mode = state.preference || "auto";

    if (mode === "choose") {

      event.preventDefault();

      showModal(context);

      return;

    }



    if (mode === "auto" || mode === "local") {

      event.preventDefault();

      openLocal(context.href, context.type);

      return;

    }



    if (mode === "browser-picker") {

      event.preventDefault();

      if (context.type && isMedia(context.type) && globalSupportsRemotePlayback()) {

        launchBrowserPicker(context).then(function (success) {

          if (!success) {

            openLocal(context.href, context.type);

          }

        });

      } else {

        openLocal(context.href, context.type);

      }

      return;

    }



    if (typeof mode === "string" && mode.startsWith("dlna:")) {

      event.preventDefault();

      if (DLNA_API && context.type && isMedia(context.type)) {

        const controlURL = getSelectedHeaderDlnaControlUrl();

        if (controlURL) {

          fetch(`${DLNA_API}/play`, {

            method: "POST",

            headers: {

              "Content-Type": "application/json"

            },

            body: JSON.stringify({

              controlURL,

              mediaUrl: context.href,

              position: 0

            })

          }).then(function (response) {

            if (!response.ok) {

              throw new Error("DLNA helper respondio con error");

            }

            return response;

          }).catch(function (error) {

            console.error("DLNA /play fallo", error);

            openLocal(context.href, context.type);

          });

          return;

        }

      }

      openLocal(context.href, context.type);

      return;

    }



    event.preventDefault();

    showModal(context);

  }



  function resolveUrl(href) {

    try {

      return new URL(href, window.location.href);

    } catch (_) {

      return null;

    }

  }



  function shouldIntercept(url) {

    if (!url) {

      return false;

    }

    const sameOrigin = window.location.origin === "null" || url.origin === window.location.origin;

    if (!sameOrigin) {

      return false;

    }

    return Boolean(typeOf(url.href));

  }



  function buildContext(anchor, url) {

    const pathname = url.pathname || "";

    const baseName = pathname.split("/").pop();

    const anchorText = anchor && anchor.textContent ? anchor.textContent : "";

    const fileName = decodeURIComponent(baseName || anchorText || "");

    const resourceType = typeOf(url.href);

    if (!resourceType) {

      return null;

    }

    const extension = extOf(url.href).replace(/^\./, "");

    return {

      anchor,

      href: url.href,

      name: fileName || "(archivo)",

      extension,

      type: resourceType

    };

  }



  function extOf(href) {

    try {

      const pathname = new URL(href, window.location.href).pathname.toLowerCase();

      const index = pathname.lastIndexOf(".");

      return index >= 0 ? pathname.slice(index) : "";

    } catch (_) {

      return "";

    }

  }



  function typeOf(href) {

    const ext = extOf(href);

    if (!ext) {

      return null;

    }

    for (const [t, list] of Object.entries(KNOWN)) {

      if (list.includes(ext)) {

        return t;

      }

    }

    return null;

  }



  function updateModal(context) {

    hideMessage();

    const displayName = context.name || context.href;

    owFileName.textContent = displayName;

    modalDialog.setAttribute("aria-labelledby", "owDialogTitle");

    modalDialog.setAttribute("data-file-type", context.type);

    state.currentHref = context.href;

    state.currentType = context.type;

    toggleButtons();

    updateDlnaButton();

  }



  function openModal() {

    modal.hidden = false;

    modal.setAttribute("aria-hidden", "false");

    if (document && document.body) {

      document.body.classList.add("ow-no-scroll");

    }

    window.setTimeout(function () {

      const first = modal.querySelector(".ow-actions button:not([hidden]):not(:disabled)");

      if (first) {

        first.focus();

      }

    }, 0);

  }



  function closeModal() {

    modal.hidden = true;

    modal.setAttribute("aria-hidden", "true");

    if (document && document.body) {

      document.body.classList.remove("ow-no-scroll");

    }

    hideMessage();

    state.current = null;

    state.currentHref = "";

    state.currentType = null;

  }



  function hideModal() {

    closeModal();

  }



  function showModal(target, displayName) {

    let context = null;

    if (typeof target === "string") {

      const url = resolveUrl(target);

      if (!url || !shouldIntercept(url)) {

        return false;

      }

      context = buildContext(null, url);

      if (!context) {

        return false;

      }

      if (displayName) {

        context.name = displayName;

      }

      if (!context.name) {

        const parts = context.href.split("/");

        context.name = parts.pop() || context.href;

      }

    } else if (target && typeof target === "object" && target.href) {

      context = target;

    }



    if (!context) {

      return false;

    }



    state.current = context;

    updateModal(context);

    openModal();

    return true;

  }



  function toggleButtons() {

    if (!owButtons || !owButtons.length) {

      return;

    }

    const btnLocal = modal.querySelector('button[data-action="open-local"]');

    const btnPicker = modal.querySelector('button[data-action="browser-picker"]');

    const btnDlna = modal.querySelector('button[data-action="dlna"]');

    const btnAirPlay = airplayBtn;



    if (btnLocal) {

      btnLocal.disabled = false;

    }



    if (btnPicker) {

      const supportsRemote = state.currentType && isMedia(state.currentType) && globalSupportsRemotePlayback();

      btnPicker.disabled = !supportsRemote;

      btnPicker.hidden = !supportsRemote;

    }



    if (btnDlna) {

      const dlnaOk = Boolean(DLNA_API) && Boolean(DLNA_WS) && state.dlnaDevices.length > 0 && state.currentType && isMedia(state.currentType);

      btnDlna.hidden = !dlnaOk;

      btnDlna.disabled = !dlnaOk;

    }



    if (btnAirPlay) {

      btnAirPlay.hidden = !globalSupportsRemotePlayback();

    }

  }



  function isMedia(type) {

    return type === "video" || type === "audio";

  }



  function openLocal(href, type) {

    if (!href) {

      return false;

    }

    const abs = new URL(href, location.href).href;

    const effectiveType = type || typeOf(abs);

    if (effectiveType === "image") {

      window.open(abs, "_blank", "noopener");

      return true;

    }

    if (effectiveType === "pdf" || effectiveType === "html") {

      // Simple lightbox mediante nueva pestaÃ±a para PDF/HTML

      window.open(abs, "_blank", "noopener");

      return true;

    }

    if (effectiveType === "text") {

      fetch(abs)

        .then(function (res) {

          if (!res.ok) { throw new Error("No se pudo cargar el texto"); }

          return res.text();

        })

        .then(function (content) {

          const wrap = document.createElement("div");

          wrap.style.position = "fixed";

          wrap.style.inset = "0";

          wrap.style.background = "#0b0b0d";

          wrap.style.color = "#e5e7eb";

          wrap.style.display = "grid";

          wrap.style.gridTemplateRows = "auto 1fr";

          wrap.style.zIndex = 9999;



          const escapeHtml = function (textValue) {

            return textValue.replace(/[&<>"']/g, function (ch) {

              switch (ch) {

                case "&": return "&amp;";

                case "<": return "&lt;";

                case ">": return "&gt;";

                case "\"": return "&quot;";

                case "'": return "&#39;";

                default: return ch;

              }

            });

          };



          wrap.innerHTML = [

            '<div style="padding:.6rem 1rem;border-bottom:1px solid #222;display:flex;justify-content:space-between;align-items:center">',

            "<strong>" + escapeHtml(abs.split('/').pop() || "(texto)") + "</strong>",

            '<div style="display:flex;gap:8px">',

            '<button id="owTxtClose" style="padding:6px 12px;border:1px solid #475569;border-radius:8px;background:#1e293b;color:#f8fafc;cursor:pointer">Cerrar</button>',

            '<button id="owTxtDL" style="padding:6px 12px;border:1px solid #2563eb;border-radius:8px;background:#2563eb;color:#fff;cursor:pointer">Descargar</button>',

            "</div>",

            "</div>",

            '<pre style="margin:0;overflow:auto;padding:1rem;white-space:pre-wrap;font-family:Consolas,\'Courier New\',monospace;font-size:0.95rem;line-height:1.4">' + escapeHtml(content) + "</pre>"

          ].join("");



          document.body.appendChild(wrap);



          const closeButton = wrap.querySelector("#owTxtClose");

          const downloadButton = wrap.querySelector("#owTxtDL");



          const close = registerOverlay(wrap, function () {

            wrap.remove();

          });

          if (closeButton) {

            closeButton.addEventListener("click", close);

          }

          wrap.addEventListener("click", function (event) {

            if (event.target === wrap) { close(); }

          });

          if (downloadButton) {

            downloadButton.addEventListener("click", function () {

              const link = document.createElement("a");

              link.href = abs;

              link.download = "";

              document.body.appendChild(link);

              link.click();

              link.remove();

            });

          }

        })

        .catch(function () {

          window.open(abs, "_blank", "noopener");

        });

      return true;

    }

    if (effectiveType === "video" || effectiveType === "audio") {

      const wrap = document.createElement("div");

      wrap.style.position = "fixed";

      wrap.style.inset = "0";

      wrap.style.background = "rgba(0,0,0,.85)";

      wrap.style.display = "grid";

      wrap.style.placeItems = "center";

      wrap.style.zIndex = 9999;



      const media = document.createElement(effectiveType === "video" ? "video" : "audio");

      media.src = abs;

      media.controls = true;

      media.autoplay = true;

      media.style.maxWidth = "90vw";

      media.style.maxHeight = "80vh";



      const closeButton = document.createElement("button");

      closeButton.textContent = "Cerrar";

      closeButton.style.marginTop = "10px";



      const panel = document.createElement("div");

      panel.style.display = "grid";

      panel.style.placeItems = "center";

      panel.append(media, closeButton);



      wrap.append(panel);

      document.body.appendChild(wrap);

      const close = registerOverlay(wrap, function () {

        try {

          if (typeof media.pause === "function") {

            media.pause();

          }

        } catch (_) {

          /* ignore */

        }

        try {

          media.removeAttribute("src");

          if (typeof media.load === "function") {

            media.load();

          }

        } catch (_) {

          /* ignore */

        }

        wrap.remove();

      });

      closeButton.addEventListener("click", close);

      wrap.addEventListener("click", function (event) {

        if (event.target === wrap) { close(); }

      });

      return true;

    }

    window.open(abs, "_blank", "noopener");

    return true;

  }



  async function handleDlnaAction() {

    if (!DLNA_API || !DLNA_WS || !isMedia(state.currentType)) {

      showMessage("Requiere DLNA helper activo y contenido multimedia.");

      return;

    }

    if (state.dlnaDevices.length === 0) {

      showMessage("No hay dispositivos DLNA disponibles.");

      return;

    }

    const selectedOption = getSelectedHeaderDlnaOption();

    const controlUrl = selectedOption ? selectedOption.dataset.controlUrl || "" : "";

    if (!controlUrl) {

      showMessage("Selecciona un destino DLNA en el selector global.");

      return;

    }

    try {

      const response = await fetch(`${DLNA_API}/play`, {

        method: "POST",

        headers: {

          "Content-Type": "application/json"

        },

        body: JSON.stringify({

          controlURL: controlUrl,

          mediaUrl: new URL(state.currentHref, window.location.href).href,

          position: 0

        })

      });

      if (!response.ok) {

        throw new Error("DLNA helper respondio con error");

      }

      hideModal();

    } catch (error) {

      console.error("DLNA /play fallo", error);

      showMessage("No se pudo enviar al dispositivo DLNA.");

    }

  }



  async function ensureRemotePickerPrimed() {

    if (!globalSupportsRemotePlayback()) {

      return false;

    }

    try {

      const tempVideo = document.createElement("video");

      if (tempVideo.remote && typeof tempVideo.remote.prompt === "function") {

        await tempVideo.remote.prompt();

        return true;

      }

    } catch (error) {

      console.warn("Remote playback prompt failed", error);

    }

    return false;

  }



  function globalSupportsRemotePlayback() {

    return remotePlaybackSupported;

  }



  function ensureModalMessage() {

    if (modalMessage && modalMessage.isConnected) {

      return modalMessage;

    }



    if (!modalDialog) {

      return null;

    }



    const existing = modalDialog.querySelector(".ow-message");

    if (existing) {

      modalMessage = existing;

      return modalMessage;

    }



    const node = document.createElement("div");

    node.className = "ow-message";

    node.hidden = true;



    const actions = modalDialog.querySelector(".ow-actions");

    if (actions && actions.parentNode === modalDialog) {

      modalDialog.insertBefore(node, actions);

    } else {

      modalDialog.appendChild(node);

    }

    modalMessage = node;

    return modalMessage;

  }



  function showMessage(text) {

    const node = ensureModalMessage();

    if (!node) {

      return;

    }

    node.textContent = text;

    node.hidden = false;

  }



  function hideMessage() {

    if (modalMessage && modalMessage.isConnected) {

      modalMessage.hidden = true;

      modalMessage.textContent = "";

    }

  }



  function executeAction(action, fromPreference) {

    const context = state.current;

    if (!context) {

      return Promise.resolve(false);

    }



    switch (action) {

      case "open-local":

      case "local": {

        const opened = openLocal(context.href, context.type);

        if (opened && !fromPreference) {

          closeModal();

        }

        return Promise.resolve(Boolean(opened));

      }

      case "browser-picker":

        return launchBrowserPicker(context).then(function (done) {

          if (done && !fromPreference) {

            closeModal();

          }

          return done;

        });

      case "new-tab":

        window.open(context.href, "_blank", "noopener");

        if (!fromPreference) {

          closeModal();

        }

        return Promise.resolve(true);

      case "download":

        triggerDownload(context);

        if (!fromPreference) {

          closeModal();

        }

        return Promise.resolve(true);

      default:

        if (action.startsWith("dlna:")) {

          return sendToDlna(action.substring(5), context, fromPreference);

        }

        if (action === "dlna") {

          return sendToDlna(null, context, fromPreference);

        }

        return Promise.resolve(false);

    }

  }



  async function launchBrowserPicker(context) {

    const type = context.type;

    if (type !== "audio" && type !== "video") {

      return false;

    }

    const element = document.createElement(type === "video" ? "video" : "audio");

    element.src = context.href;

    element.playsInline = true;

    element.muted = true;

    try {

      if (element.remote && typeof element.remote.prompt === "function") {

        await element.remote.prompt();

        return true;

      }

      if (typeof element.webkitShowPlaybackTargetPicker === "function") {

        element.webkitShowPlaybackTargetPicker();

        return true;

      }

    } catch (error) {

      console.warn("Remote playback prompt failed", error);

    }

    return false;

  }



  function triggerDownload(context) {

    const link = document.createElement("a");

    link.href = context.href;

    link.download = context.name;

    document.body.appendChild(link);

    link.click();

    document.body.removeChild(link);

  }



  function createRemoteProbe() {

    const probe = document.createElement("video");

    probe.playsInline = true;

    probe.muted = true;

    probe.style.display = "none";

    document.body.appendChild(probe);

    state.remoteProbe = probe;



    if (airplayBtn) {

      const hasAirPlay = typeof probe.webkitShowPlaybackTargetPicker === "function";

      const hasRemote = probe.remote && typeof probe.remote.prompt === "function";

      const shouldReveal = globalSupportsRemotePlayback() && (hasAirPlay || hasRemote);

      airplayBtn.hidden = !shouldReveal;

    }

  }



  function discoverDlnaDevices() {

    const preferredEndpoint = DLNA_API || readDlnaEndpointFromMeta() || readStoredDlnaEndpoint();

    const endpoints = [];

    if (preferredEndpoint) {

      endpoints.push(preferredEndpoint);

    }

    defaultDlnaEndpoints.forEach(function (endpoint) {

      if (!endpoints.includes(endpoint)) {

        endpoints.push(endpoint);

      }

    });



    fetchSequential(endpoints, fetchDlnaDevices).then(function (result) {

      if (!result) {

        return;

      }

      const { endpoint, devices } = result;

      state.dlnaDevices = devices;

      state.dlnaEndpoint = endpoint;

      try {

        window.localStorage.setItem(dlnaEndpointStorageKey, endpoint);

      } catch (_) {

        /* ignore */

      }

      populateDlnaOptions(devices);

      updateDlnaButton();

    });

  }



  function setupDlnaWebSocket() {

    if (!DLNA_WS || typeof WebSocket === "undefined") {

      return;

    }

    let socket;

    try {

      socket = new WebSocket(DLNA_WS);

    } catch (error) {

      console.warn("No se pudo conectar a DLNA_WS:", error);

      return;

    }



    socket.onmessage = function (event) {

      if (!event || !event.data) {

        return;

      }

      try {

        const payload = JSON.parse(event.data);

        if (Array.isArray(payload)) {

          payload.forEach(addDlnaToHeader);

          updateDlnaButton();

        } else if (payload && payload.type === "devices" && Array.isArray(payload.devices)) {

          payload.devices.forEach(addDlnaToHeader);

          updateDlnaButton();

        } else if (payload && payload.type === "device-online" && payload.device) {

          addDlnaToHeader(payload.device);

          updateDlnaButton();

        }

      } catch (error) {

        console.warn("DLNA_WS mensaje invalido:", error);

      }

    };



    socket.onerror = function (event) {

      console.warn("DLNA_WS error:", event);

    };

  }



  function readDlnaEndpointFromMeta() {

    const meta = document.querySelector('meta[name="inventory:dlnaEndpoint"]');

    return meta ? meta.getAttribute("content") : "";

  }



  function readStoredDlnaEndpoint() {

    try {

      return window.localStorage.getItem(dlnaEndpointStorageKey) || "";

    } catch (_) {

      return "";

    }

  }



  function fetchSequential(items, factory) {

    let index = 0;

    function next() {

      if (index >= items.length) {

        return Promise.resolve(null);

      }

      const item = items[index++];

      return factory(item).catch(function () {

        return next();

      });

    }

    return next();

  }



  function fetchDlnaDevices(endpoint) {

    if (!endpoint) {

      return Promise.reject(new Error("No endpoint"));

    }

    const cleanEndpoint = endpoint.replace(/\/+$/, "");

    return fetch(cleanEndpoint + "/devices", { method: "GET" })

      .then(function (response) {

        if (!response.ok) {

          throw new Error("DLNA helper no disponible");

        }

        return response.json();

      })

      .then(function (payload) {

        if (!Array.isArray(payload) || payload.length === 0) {

          throw new Error("Sin dispositivos DLNA");

        }

        const devices = payload

          .map(function (item, index) {

            return {

              id: item.id || "dlna-" + index,

              name: item.name || "DLNA " + (index + 1),

              endpoint: cleanEndpoint

            };

          });

        return { endpoint: cleanEndpoint, devices };

      });

  }



  function populateDlnaOptions(devices) {

    if (!globalSelect) {

      return;

    }

    Array.from(globalSelect.querySelectorAll("option")).forEach(function (option) {

      if (option.value && option.value.startsWith("dlna:")) {

        option.remove();

      }

    });

    devices.forEach(addDlnaToHeader);

  }



  // --- DLNA discovery (opcional) para inyectar en <select> global ---

  function addDlnaToHeader(device) {

    if (!globalSelect || !device || !device.id) {

      return null;

    }

    const value = "dlna:" + device.id;

    const label = "DLNA: " + (device.friendlyName || device.name || device.id);

    const existing = Array.from(globalSelect.options).find(function (option) {

      return option.value === value;

    });

    const baseEndpoint = device.endpoint ? device.endpoint.replace(/\/+$/, "") : "";

    const controlUrl = device.controlURL || device.controlUrl || (baseEndpoint ? baseEndpoint + "/play?deviceId=" + encodeURIComponent(device.id) : "");

    if (existing) {

      existing.textContent = label;

      existing.dataset.controlUrl = controlUrl;

      existing.dataset.deviceId = device.id;

      existing.disabled = false;

      existing.hidden = false;

      return existing;

    }

    const option = document.createElement("option");

    option.value = value;

    option.textContent = label;

    option.dataset.controlUrl = controlUrl;

    option.dataset.deviceId = device.id;

    globalSelect.appendChild(option);

    return option;

  }



  function getSelectedHeaderDlnaControlUrl() {

    const selected = getSelectedHeaderDlnaOption();

    return selected ? (selected.dataset.controlUrl || null) : null;

  }



  function getSelectedHeaderDlnaOption() {

    if (!globalSelect) {

      return null;

    }

    const opt = globalSelect.selectedOptions && globalSelect.selectedOptions.length ? globalSelect.selectedOptions[0] : globalSelect.options[globalSelect.selectedIndex];

    if (!opt || !opt.value || !opt.value.startsWith("dlna:")) {

      return null;

    }

    return opt;

  }



  function updateDlnaButton() {

    const dlnaButton = modal.querySelector('button[data-action="dlna"]');

    if (!dlnaButton) {

      return;

    }

    const hasDevices = state.dlnaDevices.length > 0;

    dlnaButton.hidden = !hasDevices;

    if (hasDevices) {

      const device = resolveDlnaDevice(null);

      dlnaButton.textContent = "DLNA de la red" + (device ? " (" + device.name + ")" : "");

    }

  }



  function resolveDlnaDevice(optionalId) {

    if (!state.dlnaDevices.length) {

      return null;

    }

    if (optionalId) {

      return state.dlnaDevices.find(function (device) {

        return device.id === optionalId;

      }) || state.dlnaDevices[0];

    }

    const selection = state.preference.startsWith("dlna:") ? state.preference.substring(5) : null;

    if (selection) {

      return state.dlnaDevices.find(function (device) {

        return device.id === selection;

      }) || state.dlnaDevices[0];

    }

    return state.dlnaDevices[0];

  }



  function sendToDlna(optionalId, context, fromPreference) {

    const device = resolveDlnaDevice(optionalId);

    if (!device) {

      showMessage("No se encontro un dispositivo DLNA disponible.");

      return Promise.resolve(false);

    }



    const url = new URL(device.endpoint + "/play");

    url.searchParams.set("deviceId", device.id);

    url.searchParams.set("name", context.name);

    url.searchParams.set("target", context.href);



    window.open(url.toString(), "_blank", "noopener");

    if (!fromPreference) {

      closeModal();

    }

    return Promise.resolve(true);

  }



  if (typeof window !== "undefined") {

    window.MontanaPicker = Object.assign(window.MontanaPicker || {}, {

      showModal: showModal

    });

  }

})();







