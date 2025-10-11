(function(window, document){
  "use strict";

  const globalConfig = window.MingoMediaConfig || {};
  const viewConfig = globalConfig.view || {};
  const accessConfig = globalConfig.access || {};
  const SESSION_KEY = "mingomedia.access.session";

  const columns = {
    sha: { id: "sha", label: "SHA", type: "text", className: "muted wrap", get: row => row.sha || "", filterPlaceholder: "Filtrar hash", csv: row => row.sha || "" },
    tipo: { id: "tipo", label: "Tipo", type: "text", get: row => row.tipo || "", filterPlaceholder: "Filtrar tipo" },
    nombre: { id: "nombre", label: "Nombre", type: "text", get: row => row.nombre || "", render: row => cellFileLink(row), filterPlaceholder: "Filtrar nombre", csv: row => row.nombre || "" },
    ruta: { id: "ruta", label: "Ruta/Carpeta", type: "text", get: row => row.ruta || "", render: row => cellFolderLink(row), filterPlaceholder: "Filtrar ruta", csv: row => row.ruta || "" },
    unidad: { id: "unidad", label: "Unidad", type: "text", get: row => row.unidad || "", filterPlaceholder: "Filtrar unidad" },
    tamano: { id: "tamano", label: "Tama&ntilde;o", type: "number", className: "col-size", get: row => Number(row.tamano || 0), render: row => escapeHtml(human(row.tamano)), filterPlaceholder: ">=, <=, =", csv: row => Number(row.tamano || 0) },
    fecha: { id: "fecha", label: "Fecha", type: "date", className: "col-date", get: row => row.fecha || "", render: row => escapeHtml(formatDate(row.fecha)), filterPlaceholder: "YYYY-MM-DD", csv: row => row.fecha || "" }
  };

  const defaultOrder = ["sha", "tipo", "nombre", "ruta", "unidad", "tamano", "fecha"];
  const defaultWidths = { sha: 240, tipo: 120, nombre: 260, ruta: 320, unidad: 90, tamano: 130, fecha: 160 };

  const store = window.createMingoInventoryStore({
    allColumns: Object.keys(columns),
    defaultOrder,
    defaultWidths,
    storagePrefix: viewConfig.storagePrefix || "mingomedia.inventory.view",
    defaultUserKey: viewConfig.defaultUser || "public",
    initialPageSize: 50
  });

  window.mingoInventory = store;

  const elements = {
    err: document.getElementById("err"),
    tableShell: document.getElementById("tableShell"),
    headerRow: document.getElementById("headerRow"),
    filterRow: document.getElementById("filterRow"),
    tbody: document.querySelector("#tbl tbody"),
    q: document.getElementById("q"),
    chips: document.getElementById("unitChips"),
    count: document.getElementById("count"),
    size: document.getElementById("size"),
    pageSize: document.getElementById("pageSize"),
    prev: document.getElementById("prevPage"),
    next: document.getElementById("nextPage"),
    pageInfo: document.getElementById("pageInfo"),
    download: document.getElementById("downloadBtn"),
    resetCols: document.getElementById("resetColumns"),
    unitSummary: document.getElementById("unitSummary"),
    extSummary: document.getElementById("extSummary"),
    pathSummary: document.getElementById("pathSummary"),
    selectionIndicator: document.getElementById("selectionIndicator"),
    selectionCount: document.getElementById("selectionCount"),
    hideSelected: document.getElementById("hideSelectedBtn"),
    accessGate: document.getElementById("accessGate"),
    accessMessage: document.getElementById("accessMessage"),
    accessForm: document.getElementById("accessForm"),
    accessEmail: document.getElementById("accessEmail"),
    accessPin: document.getElementById("accessPin"),
    accessPinLabel: document.getElementById("accessPinLabel"),
    accessError: document.getElementById("accessError"),
    accessSubmit: document.getElementById("accessSubmit"),
    viewBtn: document.getElementById("viewManagerBtn"),
    viewPanel: document.getElementById("viewPanel"),
    viewColumnList: document.getElementById("columnToggleList"),
    viewClose: document.getElementById("closeViewPanel"),
    viewReset: document.getElementById("resetViewBtn"),
    viewHiddenMessage: document.getElementById("hiddenRowsMessage"),
    hiddenRowsList: document.getElementById("hiddenRowsList"),
    showHiddenRows: document.getElementById("showHiddenRowsBtn"),
    hiddenRowsBanner: document.getElementById("hiddenRowsBanner"),
    hiddenRowsCount: document.getElementById("hiddenRowsCount"),
    hiddenRowsShow: document.getElementById("hiddenRowsShowBtn")
  };

  const baseNode = document.getElementById("INV_B64");
  let DATA = [];
  const rowLookup = new Map();
  let selectAllCheckbox = null;
  let dragSource = null;
  let renderPending = false;
  let lastRenderedRowIds = [];
  let viewPanelOpen = false;
  let viewPanelOutsideHandler = null;
  let dragSelectionState = null;

  ensureInventoryLoader();

  document.addEventListener("DOMContentLoaded", () => {
    setupStoreListeners();
    buildHeaders();
    ensureAccess(accessConfig).then(session => {
      const fallbackUser = viewConfig.defaultUser || "public";
      const userKey = session && session.userKey ? session.userKey : (session && session.email ? session.email : null);
      store.setUser(userKey || fallbackUser);
      loadInventory().catch(showErr);
    }).catch(showErr);
    wireUi();
  });

  function ensureInventoryLoader() {
    if (typeof window.loadInventorySafe === "function") {
      return;
    }
    window.loadInventorySafe = async function loadInventorySafe() {
      const embedded = await loadFromEmbedded();
      if (embedded && embedded.length) {
        return embedded;
      }
      return await loadFromFile();
    };
  }

  async function loadFromEmbedded() {
    if (!baseNode) {
      return null;
    }
    const raw = (baseNode.textContent || "").trim();
    if (!raw) {
      return null;
    }
    try {
      const decoded = decodeBase64(raw);
      if (Array.isArray(decoded) && decoded.length) {
        return decoded;
      }
      if (decoded && typeof decoded === "object" && Array.isArray(decoded.data)) {
        return decoded.data;
      }
      return Array.isArray(decoded) ? decoded : [];
    } catch (error) {
      console.warn("Error leyendo inventario embebido", error);
      return null;
    }
  }

  async function loadFromFile() {
    const src = baseNode ? baseNode.getAttribute("data-src") : null;
    const candidates = [];
    if (src) {
      candidates.push(src);
    }
    candidates.push("data/inventory.json", "data/inventory.min.json", "data/inventory.json.gz");

    let lastError = null;
    for (const url of candidates) {
      if (!url) { continue; }
      try {
        const data = await fetchJson(url);
        return Array.isArray(data) ? data : (data && Array.isArray(data.data) ? data.data : []);
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError) {
      throw lastError;
    }
    throw new Error("No se pudo cargar el inventario");
  }

  async function fetchJson(url) {
    if (!url) {
      throw new Error("URL de inventario no definida");
    }
    const protocol = (window.location && window.location.protocol) || "";
    if (!protocol.startsWith("http") && url.startsWith("data/")) {
      throw new Error("No se puede hacer fetch sin servidor HTTP");
    }
    const res = await fetch(url, { cache: "no-store" });
    if (!res.ok) {
      throw new Error("No se pudo cargar " + url + " (" + res.status + ")");
    }
    if (url.endsWith(".gz")) {
      try {
        return await res.json();
      } catch (_) {
        if (window.pako && typeof window.pako.ungzip === "function") {
          const buf = await res.arrayBuffer();
          const text = window.pako.ungzip(new Uint8Array(buf), { to: "string" });
          return JSON.parse(text);
        }
        throw new Error("El archivo " + url + " está comprimido y no se pudo descomprimir.");
      }
    }
    return await res.json();
  }

  function decodeBase64(raw) {
    const bin = window.atob(raw);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) {
      bytes[i] = bin.charCodeAt(i);
    }
    const txt = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
    return JSON.parse(txt);
  }

  async function loadInventory() {
    try {
      const raw = await window.loadInventorySafe();
      DATA = normalizeData(raw);
      DATA.forEach(rememberRow);
      requestRender();
    } catch (error) {
      showErr(error);
    }
  }

  function normalizeData(source) {
    return (Array.isArray(source) ? source : []).map(row => ({
      sha: row.sha || "",
      tipo: row.tipo || row.type || "",
      nombre: row.nombre || row.name || "",
      ruta: row.ruta || row.dir || row.path || "",
      unidad: (row.unidad || row.drive || "").toString().trim(),
      tamano: Number((row.tamano ?? row.size ?? row.length) || 0),
      fecha: row.fecha || row.date || row.lastWriteTime || ""
    }));
  }

  function rememberRow(row) {
    const id = getRowId(row);
    if (id) {
      rowLookup.set(id, row);
    }
  }

  function showErr(err) {
    const msg = err && err.message ? err.message : String(err);
    if (elements.err) {
      elements.err.textContent = "[!] " + msg;
      elements.err.style.display = "block";
    }
    console.error(msg);
  }
  function setupStoreListeners() {
    store.on("columns:order", () => {
      buildHeaders();
    });
    store.on("columns:hidden", () => {
      buildHeaders();
    });
    store.on("view:hydrate", () => {
      buildHeaders();
      syncFilterInputs();
    });
    store.on("filters:change", () => {
      syncFilterInputs();
    });
    store.on("change", () => {
      requestRender();
    });
  }

  function requestRender() {
    if (renderPending) {
      return;
    }
    renderPending = true;
    window.requestAnimationFrame(() => {
      renderPending = false;
      render();
    });
  }

  function buildHeaders() {
    if (!elements.headerRow || !elements.filterRow) {
      return;
    }
    const snapshot = store.getState();
    const hidden = new Set(snapshot.hiddenColumns || []);

    elements.headerRow.innerHTML = "";
    elements.filterRow.innerHTML = "";

    const selectorHeader = document.createElement("th");
    selectorHeader.className = "selector-header";
    const selectorCheckbox = document.createElement("input");
    selectorCheckbox.type = "checkbox";
    selectorCheckbox.addEventListener("change", event => {
      handleSelectAll(event.target.checked);
    });
    selectorHeader.appendChild(selectorCheckbox);
    selectAllCheckbox = selectorCheckbox;
    elements.headerRow.appendChild(selectorHeader);

    const selectorFilter = document.createElement("th");
    selectorFilter.className = "selector-header";
    elements.filterRow.appendChild(selectorFilter);

    snapshot.order.forEach(colId => {
      if (hidden.has(colId)) {
        return;
      }
      const col = columns[colId];
      if (!col) {
        return;
      }
      const th = document.createElement("th");
      th.dataset.col = colId;
      th.draggable = true;
      const width = snapshot.widths[colId] || defaultWidths[colId] || 150;
      th.style.width = width + "px";
      const wrapper = document.createElement("div");
      wrapper.className = "th-content";
      const label = document.createElement("span");
      label.className = "th-label";
      label.innerHTML = col.label;
      wrapper.appendChild(label);
      th.appendChild(wrapper);
      const handle = document.createElement("span");
      handle.className = "resize-handle";
      th.appendChild(handle);

      handle.addEventListener("pointerdown", event => {
        event.preventDefault();
        event.stopPropagation();
        const startX = event.clientX;
        const startWidth = th.getBoundingClientRect().width;
        function onMove(moveEvent) {
          const delta = moveEvent.clientX - startX;
          const newWidth = Math.max(80, startWidth + delta);
          th.style.width = newWidth + "px";
        }
        function onUp(moveEvent) {
          window.removeEventListener("pointermove", onMove);
          window.removeEventListener("pointerup", onUp);
          const delta = moveEvent.clientX - startX;
          const newWidth = Math.max(80, startWidth + delta);
          store.setColumnWidth(colId, newWidth);
        }
        window.addEventListener("pointermove", onMove);
        window.addEventListener("pointerup", onUp, { once: true });
      });

      th.addEventListener("dragstart", event => {
        dragSource = colId;
        th.classList.add("drag-source");
        if (elements.tableShell) {
          elements.tableShell.classList.add("drag-active");
        }
        try {
          event.dataTransfer.effectAllowed = "move";
          event.dataTransfer.setData("text/plain", colId);
        } catch (_) {
          /* ignore */
        }
      });
      th.addEventListener("dragend", () => {
        dragSource = null;
        th.classList.remove("drag-source");
        if (elements.tableShell) {
          elements.tableShell.classList.remove("drag-active");
        }
        Array.from(elements.headerRow.children).forEach(node => node.classList.remove("drop-target"));
      });
      th.addEventListener("dragover", event => {
        event.preventDefault();
        if (!dragSource || dragSource === colId) {
          return;
        }
        th.classList.add("drop-target");
      });
      th.addEventListener("dragleave", () => {
        th.classList.remove("drop-target");
      });
      th.addEventListener("drop", event => {
        event.preventDefault();
        th.classList.remove("drop-target");
        if (!dragSource || dragSource === colId) {
          return;
        }
        const current = store.getState().order.slice();
        const fromIdx = current.indexOf(dragSource);
        const toIdx = current.indexOf(colId);
        if (fromIdx === -1 || toIdx === -1) {
          return;
        }
        current.splice(fromIdx, 1);
        current.splice(toIdx, 0, dragSource);
        store.setColumnOrder(current);
      });

      elements.headerRow.appendChild(th);

      const filterCell = document.createElement("th");
      let placeholder = "Filtrar";
      if (col.type === "number") {
        placeholder = ">=, <=, =";
      } else if (col.type === "date") {
        placeholder = "YYYY-MM-DD";
      } else if (col.filterPlaceholder) {
        placeholder = col.filterPlaceholder;
      }
      const input = document.createElement("input");
      input.setAttribute("data-col", colId);
      input.placeholder = placeholder;
      input.value = snapshot.filters[colId] || "";
      input.addEventListener("input", ev => {
        store.setFilter(colId, ev.target.value);
      });
      filterCell.appendChild(input);
      elements.filterRow.appendChild(filterCell);
    });

    syncSelectAllCheckbox(snapshot);
  }

  function syncFilterInputs() {
    const snapshot = store.getState();
    if (!elements.filterRow) {
      return;
    }
    const inputs = elements.filterRow.querySelectorAll("input[data-col]");
    inputs.forEach(input => {
      const colId = input.getAttribute("data-col");
      input.value = snapshot.filters[colId] || "";
    });
  }

  function wireUi() {
    if (elements.q) {
      elements.q.addEventListener("input", event => {
        store.setSearch(event.target.value);
      });
    }
    if (elements.pageSize) {
      elements.pageSize.addEventListener("change", event => {
        store.setPageSize(Number(event.target.value));
      });
    }
    if (elements.prev) {
      elements.prev.addEventListener("click", () => {
        const state = store.getState();
        if (state.page > 1) {
          store.setPage(state.page - 1);
        }
      });
    }
    if (elements.next) {
      elements.next.addEventListener("click", () => {
        const state = store.getState();
        store.setPage(state.page + 1);
      });
    }
    if (elements.download) {
      elements.download.addEventListener("click", () => {
        const snapshot = store.getState();
        downloadCsv(applyFilters(snapshot, false), snapshot);
      });
    }
    if (elements.resetCols) {
      elements.resetCols.addEventListener("click", () => {
        store.resetColumns();
      });
    }
    if (elements.hideSelected) {
      elements.hideSelected.addEventListener("click", () => {
        hideSelectedRows();
      });
    }
    if (elements.viewBtn) {
      elements.viewBtn.addEventListener("click", toggleViewPanel);
    }
    if (elements.viewClose) {
      elements.viewClose.addEventListener("click", () => {
        closeViewPanel();
      });
    }
    if (elements.viewReset) {
      elements.viewReset.addEventListener("click", () => {
        store.resetView();
      });
    }
    if (elements.showHiddenRows) {
      elements.showHiddenRows.addEventListener("click", () => {
        showAllHiddenRows();
      });
    }
    if (elements.hiddenRowsShow) {
      elements.hiddenRowsShow.addEventListener("click", () => {
        showAllHiddenRows();
      });
    }
    if (elements.tableShell) {
      elements.tableShell.addEventListener("pointerdown", handleTablePointerDown);
    }
  }
  function ensureAccess(config) {
    return new Promise((resolve) => {
      if (!elements.accessGate || !elements.accessForm) {
        resolve({ email: null });
        return;
      }
      if (!config || config.enabled === false) {
        elements.accessGate.hidden = true;
        resolve({ email: null });
        return;
      }

      const existing = loadSession(config);
      if (existing) {
        elements.accessGate.hidden = true;
        resolve(existing);
        return;
      }

      if (elements.accessMessage) {
        elements.accessMessage.textContent = config.message || "Introduce tu correo para continuar.";
      }
      setupAccessForm(config, resolve);
    });
  }

  function setupAccessForm(config, resolve) {
    elements.accessGate.hidden = false;
    if (elements.accessError) {
      elements.accessError.hidden = true;
      elements.accessError.textContent = "";
    }

    const requireEmail = config.requireEmail !== false;
    if (elements.accessEmail) {
      if (requireEmail) {
        elements.accessEmail.setAttribute("required", "required");
      } else {
        elements.accessEmail.removeAttribute("required");
      }
    }

    updatePinField(config, elements.accessEmail ? elements.accessEmail.value : "");

    const onInput = () => {
      updatePinField(config, elements.accessEmail ? elements.accessEmail.value : "");
      if (elements.accessError) {
        elements.accessError.hidden = true;
      }
    };

    if (elements.accessEmail) {
      elements.accessEmail.addEventListener("input", onInput);
    }

    const submitHandler = event => {
      event.preventDefault();
      if (elements.accessEmail) {
        elements.accessEmail.removeEventListener("input", onInput);
      }
      const emailRaw = elements.accessEmail ? String(elements.accessEmail.value || "").trim() : "";
      const pinRaw = elements.accessPin ? String(elements.accessPin.value || "").trim() : "";
      const validation = validateCredentials(config, emailRaw, pinRaw);
      if (!validation.ok) {
        if (elements.accessError) {
          elements.accessError.hidden = false;
          elements.accessError.textContent = validation.message;
        }
        if (validation.focus === "email" && elements.accessEmail) {
          elements.accessEmail.focus();
        } else if (validation.focus === "pin" && elements.accessPin) {
          elements.accessPin.focus();
        }
        elements.accessForm.addEventListener("submit", submitHandler, { once: true });
        if (elements.accessEmail) {
          elements.accessEmail.addEventListener("input", onInput);
        }
        return;
      }

      const session = { email: validation.email || null, userKey: validation.userKey || null };
      if (config.rememberSession !== false) {
        saveSession(config, session.email);
      }
      elements.accessGate.hidden = true;
      resolve(session);
    };

    elements.accessForm.addEventListener("submit", submitHandler, { once: true });
  }

  function loadSession(config) {
    try {
      const raw = window.localStorage.getItem(SESSION_KEY);
      if (!raw) {
        return null;
      }
      const saved = JSON.parse(raw);
      if (!saved || typeof saved !== "object") {
        return null;
      }
      if (config.version && saved.version !== config.version) {
        return null;
      }
      const email = saved.email ? String(saved.email).trim() : "";
      if (!email || !validateEmail(email)) {
        return null;
      }
      if (!emailAllowed(config, email)) {
        return null;
      }
      return { email, userKey: normalizeUser(email), remembered: true };
    } catch (error) {
      console.warn("No se pudo recuperar la sesión", error);
      return null;
    }
  }

  function saveSession(config, email) {
    const payload = { email: email || "", version: config.version || null };
    try {
      window.localStorage.setItem(SESSION_KEY, JSON.stringify(payload));
    } catch (error) {
      console.warn("No se pudo almacenar la sesión", error);
    }
  }

  function updatePinField(config, email) {
    const requirement = pinRequirement(config, email);
    if (!elements.accessPinLabel) {
      return;
    }
    const shouldShow = requirement.required || Boolean(requirement.expectedPin);
    elements.accessPinLabel.hidden = !shouldShow;
    if (!elements.accessPin) {
      return;
    }
    elements.accessPin.value = "";
    if (requirement.required) {
      elements.accessPin.setAttribute("required", "required");
    } else {
      elements.accessPin.removeAttribute("required");
    }
  }

  function validateCredentials(config, email, pin) {
    const requireEmail = config.requireEmail !== false;
    if (requireEmail && !email) {
      return { ok: false, message: "El correo es obligatorio", focus: "email" };
    }
    if (email && !validateEmail(email)) {
      return { ok: false, message: "Formato de correo no válido", focus: "email" };
    }
    if (email && !emailAllowed(config, email)) {
      return { ok: false, message: "Correo no autorizado", focus: "email" };
    }

    const requirement = pinRequirement(config, email);
    if (requirement.required && !pin) {
      return { ok: false, message: "Introduce el PIN", focus: "pin" };
    }
    if (requirement.expectedPin) {
      if (!pin) {
        return { ok: false, message: "Introduce el PIN", focus: "pin" };
      }
      if (pin !== requirement.expectedPin) {
        return { ok: false, message: "PIN incorrecto", focus: "pin" };
      }
    }

    return { ok: true, email: email || null, userKey: email ? normalizeUser(email) : null };
  }

  function pinRequirement(config, email) {
    const normalizedEmail = email ? email.toLowerCase().trim() : "";
    const users = Array.isArray(config.users) ? config.users : [];
    const userEntry = users.find(user => user && typeof user === "object" && user.email && String(user.email).toLowerCase().trim() === normalizedEmail);
    const userPin = userEntry && userEntry.pin !== undefined && userEntry.pin !== null ? String(userEntry.pin).trim() : "";
    const globalPin = config.pin !== undefined && config.pin !== null ? String(config.pin).trim() : "";
    const requirePin = config.requirePin === true;
    if (userPin) {
      return { required: true, expectedPin: userPin };
    }
    if (requirePin && globalPin) {
      return { required: true, expectedPin: globalPin };
    }
    if (requirePin) {
      return { required: true, expectedPin: "" };
    }
    if (globalPin) {
      return { required: false, expectedPin: globalPin };
    }
    return { required: false, expectedPin: "" };
  }

  function emailAllowed(config, email) {
    const normalized = email ? email.toLowerCase().trim() : "";
    const allowedEmails = Array.isArray(config.allowedEmails) ? config.allowedEmails.map(e => String(e).toLowerCase().trim()) : [];
    const allowedDomains = Array.isArray(config.allowedDomains) ? config.allowedDomains.map(e => String(e).toLowerCase().trim()) : [];
    const users = Array.isArray(config.users) ? config.users : [];
    if (!allowedEmails.length && !allowedDomains.length && !users.length) {
      return true;
    }
    if (allowedEmails.includes(normalized)) {
      return true;
    }
    if (users.some(user => user && user.email && String(user.email).toLowerCase().trim() === normalized)) {
      return true;
    }
    if (allowedDomains.length) {
      const domain = normalized.split("@")[1] || "";
      if (domain && allowedDomains.includes(domain)) {
        return true;
      }
    }
    return false;
  }

  function validateEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  }

  function normalizeUser(email) {
    return email ? email.trim().toLowerCase().replace(/[^a-z0-9_.@-]+/g, "_") : null;
  }
  function handleSelectAll(checked) {
    if (!lastRenderedRowIds.length) {
      if (!checked) {
        store.clearSelection();
      }
      return;
    }
    if (checked) {
      store.updateSelection({ add: lastRenderedRowIds });
    } else {
      store.updateSelection({ remove: lastRenderedRowIds });
    }
  }

  function hideSelectedRows() {
    const snapshot = store.getState();
    const selected = Array.isArray(snapshot.selectedRows) ? snapshot.selectedRows.filter(Boolean) : [];
    if (!selected.length) {
      return;
    }
    hideRows(selected);
    store.clearSelection();
  }

  function hideRows(rowIds) {
    const list = Array.isArray(rowIds) ? rowIds.map(id => String(id)).filter(Boolean) : [];
    if (!list.length) {
      return;
    }
    const snapshot = store.getState();
    const hidden = new Set((snapshot.hiddenRows || []).map(id => String(id)));
    let changed = false;
    list.forEach(id => {
      if (!hidden.has(id)) {
        hidden.add(id);
        changed = true;
      }
    });
    if (changed) {
      store.setHiddenRows(Array.from(hidden));
    }
    store.updateSelection({ remove: list });
  }

  function showAllHiddenRows() {
    const snapshot = store.getState();
    if (Array.isArray(snapshot.hiddenRows) && snapshot.hiddenRows.length) {
      store.setHiddenRows([]);
    }
  }

  function renderHiddenRowsBanner(snapshot) {
    if (!elements.hiddenRowsBanner) {
      return;
    }
    const hiddenRows = Array.isArray(snapshot.hiddenRows) ? snapshot.hiddenRows.filter(Boolean) : [];
    if (hiddenRows.length) {
      elements.hiddenRowsBanner.hidden = false;
      if (elements.hiddenRowsCount) {
        elements.hiddenRowsCount.textContent = hiddenRows.length.toLocaleString("es-ES");
      }
    } else {
      elements.hiddenRowsBanner.hidden = true;
    }
    if (elements.hiddenRowsShow) {
      elements.hiddenRowsShow.disabled = hiddenRows.length === 0;
    }
    if (elements.showHiddenRows) {
      elements.showHiddenRows.disabled = hiddenRows.length === 0;
    }
  }

  function renderViewControls(snapshot) {
    if (elements.viewColumnList) {
      const hidden = new Set((snapshot.hiddenColumns || []).map(id => String(id)));
      const rendered = new Set();
      const combined = Array.isArray(snapshot.order) ? snapshot.order.slice() : [];
      Object.keys(columns).forEach(colId => {
        if (!combined.includes(colId)) {
          combined.push(colId);
        }
      });
      elements.viewColumnList.innerHTML = "";
      combined.forEach(colId => {
        if (!columns[colId] || rendered.has(colId)) {
          return;
        }
        rendered.add(colId);
        const li = document.createElement("li");
        const label = document.createElement("label");
        const checkbox = document.createElement("input");
        checkbox.type = "checkbox";
        checkbox.checked = !hidden.has(colId);
        checkbox.addEventListener("change", event => {
          if (event.target.checked) {
            store.showColumn(colId);
          } else {
            store.hideColumn(colId);
          }
        });
        const text = document.createElement("span");
        text.textContent = columns[colId].label || colId;
        label.appendChild(checkbox);
        label.appendChild(text);
        li.appendChild(label);
        elements.viewColumnList.appendChild(li);
      });
    }

    const hiddenRows = Array.isArray(snapshot.hiddenRows) ? snapshot.hiddenRows.filter(Boolean) : [];
    if (elements.viewHiddenMessage) {
      elements.viewHiddenMessage.textContent = hiddenRows.length ? `${hiddenRows.length.toLocaleString("es-ES")} filas ocultas.` : "No hay filas ocultas.";
    }
    if (elements.showHiddenRows) {
      elements.showHiddenRows.disabled = hiddenRows.length === 0;
    }
    if (elements.hiddenRowsList) {
      elements.hiddenRowsList.innerHTML = "";
      if (hiddenRows.length) {
        const maxRows = 8;
        hiddenRows.slice(0, maxRows).forEach(rowId => {
          const row = rowLookup.get(rowId);
          const li = document.createElement("li");
          const label = document.createElement("span");
          label.className = "hidden-row-label";
          label.textContent = row && (row.nombre || row.ruta) ? `${row.nombre || row.ruta}` : rowId;
          li.appendChild(label);
          const showBtn = document.createElement("button");
          showBtn.type = "button";
          showBtn.className = "link-button";
          showBtn.textContent = "Mostrar";
          showBtn.addEventListener("click", () => {
            const current = new Set((store.getState().hiddenRows || []).map(id => String(id)));
            if (current.delete(rowId)) {
              store.setHiddenRows(Array.from(current));
            }
          });
          li.appendChild(showBtn);
          elements.hiddenRowsList.appendChild(li);
        });
        if (hiddenRows.length > maxRows) {
          const remaining = hiddenRows.length - maxRows;
          const more = document.createElement("li");
          more.className = "muted";
          more.textContent = `… y ${remaining.toLocaleString("es-ES")} más`;
          elements.hiddenRowsList.appendChild(more);
        }
      }
    }
  }

  function toggleViewPanel() {
    if (!elements.viewPanel) {
      return;
    }
    if (viewPanelOpen) {
      closeViewPanel();
    } else {
      openViewPanel();
    }
  }

  function openViewPanel() {
    if (!elements.viewPanel) {
      return;
    }
    viewPanelOpen = true;
    elements.viewPanel.hidden = false;
    if (elements.viewBtn) {
      elements.viewBtn.setAttribute("aria-expanded", "true");
    }
    renderViewControls(store.getState());
    if (!viewPanelOutsideHandler) {
      viewPanelOutsideHandler = event => {
        if (!elements.viewPanel.contains(event.target) && (!elements.viewBtn || !elements.viewBtn.contains(event.target))) {
          closeViewPanel();
        }
      };
      document.addEventListener("mousedown", viewPanelOutsideHandler);
      document.addEventListener("touchstart", viewPanelOutsideHandler);
    }
    window.addEventListener("keydown", handleViewPanelKeydown);
  }

  function closeViewPanel() {
    if (!elements.viewPanel) {
      return;
    }
    if (!viewPanelOpen) {
      return;
    }
    viewPanelOpen = false;
    elements.viewPanel.hidden = true;
    if (elements.viewBtn) {
      elements.viewBtn.setAttribute("aria-expanded", "false");
    }
    if (viewPanelOutsideHandler) {
      document.removeEventListener("mousedown", viewPanelOutsideHandler);
      document.removeEventListener("touchstart", viewPanelOutsideHandler);
      viewPanelOutsideHandler = null;
    }
    window.removeEventListener("keydown", handleViewPanelKeydown);
  }

  function handleViewPanelKeydown(event) {
    if (event.key === "Escape") {
      closeViewPanel();
    }
  }

  function handleTablePointerDown(event) {
    if (event.button !== 0) {
      return;
    }
    if (!elements.tableShell || !elements.tbody) {
      return;
    }
    if (!elements.tableShell.contains(event.target)) {
      return;
    }
    if (event.target.closest("input, button, select, textarea, label")) {
      return;
    }
    if (event.target.closest(".resize-handle") || event.target.closest(".row-resize-handle") || event.target.closest(".row-selector-wrap")) {
      return;
    }
    if (!event.target.closest("tbody")) {
      return;
    }
    const snapshot = store.getState();
    dragSelectionState = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      mode: event.altKey ? "remove" : ((event.ctrlKey || event.metaKey || event.shiftKey) ? "add" : "replace"),
      started: false,
      overlay: null,
      rows: Array.from(elements.tbody.querySelectorAll("tr"), tr => ({ tr, id: tr.getAttribute("data-row-id") })),
      baseOrder: Array.isArray(snapshot.selectionOrder) ? snapshot.selectionOrder.slice() : Array.from(snapshot.selectedRows || []),
      current: [],
      currentSet: new Set()
    };
    window.addEventListener("pointermove", handleTablePointerMove);
    window.addEventListener("pointerup", handleTablePointerUp);
  }

  function handleTablePointerMove(event) {
    if (!dragSelectionState) {
      return;
    }
    const dx = Math.abs(event.clientX - dragSelectionState.startX);
    const dy = Math.abs(event.clientY - dragSelectionState.startY);
    if (!dragSelectionState.started) {
      if (dx < 5 && dy < 5) {
        return;
      }
      dragSelectionState.started = true;
      dragSelectionState.overlay = document.createElement("div");
      dragSelectionState.overlay.className = "selection-rect";
      dragSelectionState.overlay.style.left = "0px";
      dragSelectionState.overlay.style.top = "0px";
      dragSelectionState.overlay.style.width = "0px";
      dragSelectionState.overlay.style.height = "0px";
      elements.tableShell.appendChild(dragSelectionState.overlay);
      if (elements.tableShell.setPointerCapture && dragSelectionState.pointerId !== undefined) {
        try {
          elements.tableShell.setPointerCapture(dragSelectionState.pointerId);
        } catch (_) {
          /* ignore */
        }
      }
    }
    if (!dragSelectionState.started) {
      return;
    }
    event.preventDefault();
    const bounds = elements.tableShell.getBoundingClientRect();
    const leftBound = Math.min(Math.max(Math.min(dragSelectionState.startX, event.clientX), bounds.left), bounds.right);
    const rightBound = Math.min(Math.max(Math.max(dragSelectionState.startX, event.clientX), bounds.left), bounds.right);
    const topBound = Math.min(Math.max(Math.min(dragSelectionState.startY, event.clientY), bounds.top), bounds.bottom);
    const bottomBound = Math.min(Math.max(Math.max(dragSelectionState.startY, event.clientY), bounds.top), bounds.bottom);
    const relLeft = leftBound - bounds.left;
    const relTop = topBound - bounds.top;
    const relWidth = Math.max(0, rightBound - leftBound);
    const relHeight = Math.max(0, bottomBound - topBound);
    if (dragSelectionState.overlay) {
      dragSelectionState.overlay.style.left = relLeft + "px";
      dragSelectionState.overlay.style.top = relTop + "px";
      dragSelectionState.overlay.style.width = relWidth + "px";
      dragSelectionState.overlay.style.height = relHeight + "px";
    }
    const selectedIds = [];
    const selectedSet = new Set();
    dragSelectionState.rows.forEach(info => {
      if (!info || !info.tr || !info.id) {
        return;
      }
      const rect = info.tr.getBoundingClientRect();
      const intersects = rect.bottom >= topBound && rect.top <= bottomBound && rect.right >= leftBound && rect.left <= rightBound;
      if (intersects) {
        if (!selectedSet.has(info.id)) {
          selectedIds.push(info.id);
          selectedSet.add(info.id);
        }
        info.tr.classList.add("row-drag-select");
      } else {
        info.tr.classList.remove("row-drag-select");
      }
    });
    dragSelectionState.current = selectedIds;
    dragSelectionState.currentSet = selectedSet;
  }

  function handleTablePointerUp() {
    if (!dragSelectionState) {
      return;
    }
    window.removeEventListener("pointermove", handleTablePointerMove);
    window.removeEventListener("pointerup", handleTablePointerUp);
    if (elements.tableShell.releasePointerCapture && dragSelectionState.pointerId !== undefined) {
      try {
        elements.tableShell.releasePointerCapture(dragSelectionState.pointerId);
      } catch (_) {
        /* ignore */
      }
    }
    if (!dragSelectionState.started) {
      dragSelectionState = null;
      return;
    }
    if (dragSelectionState.overlay && dragSelectionState.overlay.parentNode) {
      dragSelectionState.overlay.parentNode.removeChild(dragSelectionState.overlay);
    }
    dragSelectionState.rows.forEach(info => {
      if (info && info.tr) {
        info.tr.classList.remove("row-drag-select");
      }
    });
    const currentIds = dragSelectionState.current || [];
    if (dragSelectionState.mode === "remove") {
      if (currentIds.length) {
        const removeSet = new Set(currentIds);
        const nextOrder = dragSelectionState.baseOrder.filter(id => !removeSet.has(id));
        store.setSelectedRows(nextOrder);
      }
      dragSelectionState = null;
      return;
    }
    if (dragSelectionState.mode === "add") {
      const nextOrder = dragSelectionState.baseOrder.slice();
      const seen = new Set(nextOrder);
      dragSelectionState.rows.forEach(info => {
        if (!info || !info.id) {
          return;
        }
        if (dragSelectionState.currentSet && dragSelectionState.currentSet.has(info.id) && !seen.has(info.id)) {
          seen.add(info.id);
          nextOrder.push(info.id);
        }
      });
      store.setSelectedRows(nextOrder);
      dragSelectionState = null;
      return;
    }
    const next = [];
    const seen = new Set();
    dragSelectionState.rows.forEach(info => {
      if (!info || !info.id) {
        return;
      }
      if (dragSelectionState.currentSet && dragSelectionState.currentSet.has(info.id) && !seen.has(info.id)) {
        seen.add(info.id);
        next.push(info.id);
      }
    });
    store.setSelectedRows(next);
    dragSelectionState = null;
  }

  function startRowResize(event, rowElement, rowId) {
    if (!rowElement || !rowId) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    const startY = event.clientY;
    const startHeight = rowElement.getBoundingClientRect().height;
    function onMove(moveEvent) {
      const delta = moveEvent.clientY - startY;
      const newHeight = Math.max(24, startHeight + delta);
      rowElement.style.height = newHeight + "px";
    }
    function onUp(upEvent) {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      const delta = upEvent.clientY - startY;
      const newHeight = Math.max(24, Math.round(startHeight + delta));
      if (newHeight <= 24) {
        store.setRowHeight(rowId, 24);
      } else {
        store.setRowHeight(rowId, newHeight);
      }
    }
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp, { once: true });
  }

  function render() {
    const snapshot = store.getState();
    const filteredWithoutUnit = applyFilters(snapshot, true);
    const filtered = applyFilters(snapshot, false);
    const bytes = computeBytes(filtered);
    renderChips(filteredWithoutUnit, snapshot);
    renderInsights(filtered);
    const pageInfo = getCurrentSlice(filtered, snapshot);
    lastRenderedRowIds = pageInfo.rows.map(getRowId);
    renderTableBody(pageInfo.rows, snapshot);
    renderSummary(filtered.length, bytes, snapshot, pageInfo);
    syncSelectAllCheckbox(snapshot);
    if (elements.download) {
      elements.download.disabled = filtered.length === 0;
    }
    renderHiddenRowsBanner(snapshot);
    renderViewControls(snapshot);
  }

  function applyFilters(snapshot, skipUnit) {
    const searchTerm = (snapshot.search || "").toLowerCase();
    const hasSearch = searchTerm.length > 0;
    const filters = snapshot.filters || {};
    const hiddenRows = new Set(snapshot.hiddenRows || []);
    return DATA.filter(row => {
      const rowId = getRowId(row);
      if (hiddenRows.has(rowId)) {
        return false;
      }
      if (!skipUnit && snapshot.activeUnit && row.unidad !== snapshot.activeUnit) {
        return false;
      }
      if (hasSearch) {
        const hay = (row.nombre + " " + row.ruta + " " + row.sha + " " + row.tipo + " " + row.unidad).toLowerCase();
        if (!hay.includes(searchTerm)) {
          return false;
        }
      }
      for (const key in filters) {
        if (!Object.prototype.hasOwnProperty.call(filters, key)) {
          continue;
        }
        const raw = filters[key];
        if (!raw) {
          continue;
        }
        if (key === "tamano") {
          const match = raw.match(/^\s*(>=|<=|=)\s*(\d+)\s*$/);
          const current = Number(row.tamano || 0);
          if (match) {
            const op = match[1];
            const val = Number(match[2]);
            if (op === ">=" && !(current >= val)) { return false; }
            if (op === "<=" && !(current <= val)) { return false; }
            if (op === "=" && current !== val) { return false; }
          } else {
            if (human(current).toLowerCase().indexOf(raw.toLowerCase()) === -1) {
              return false;
            }
          }
        } else if (key === "fecha") {
          if (!(row.fecha || "").toLowerCase().startsWith(raw.toLowerCase())) {
            return false;
          }
        } else {
          const compare = (row[key] || "").toString().toLowerCase();
          if (!compare.includes(raw.toLowerCase())) {
            return false;
          }
        }
      }
      return true;
    });
  }

  function renderChips(rows, snapshot) {
    if (!elements.chips) {
      return;
    }
    elements.chips.innerHTML = "";
    const counts = new Map();
    rows.forEach(row => {
      if (!row.unidad) {
        return;
      }
      counts.set(row.unidad, (counts.get(row.unidad) || 0) + 1);
    });
    const allBtn = document.createElement("button");
    allBtn.textContent = "Todas (" + rows.length + ")";
    allBtn.className = "chip-all";
    allBtn.dataset.active = snapshot.activeUnit === "" ? "true" : "false";
    allBtn.addEventListener("click", () => {
      store.setActiveUnit("");
    });
    elements.chips.appendChild(allBtn);
    const entries = Array.from(counts.entries());
    if (snapshot.activeUnit && !counts.has(snapshot.activeUnit)) {
      entries.push([snapshot.activeUnit, 0]);
    }
    entries.sort((a, b) => a[0].localeCompare(b[0], undefined, { numeric: true, sensitivity: "base" })).forEach(entry => {
      const btn = document.createElement("button");
      btn.textContent = entry[0] + " (" + entry[1] + ")";
      btn.dataset.unit = entry[0];
      btn.dataset.active = snapshot.activeUnit === entry[0] ? "true" : "false";
      btn.addEventListener("click", () => {
        store.setActiveUnit(snapshot.activeUnit === entry[0] ? "" : entry[0]);
      });
      elements.chips.appendChild(btn);
    });
  }

  function renderTableBody(rows, snapshot) {
    if (!elements.tbody) {
      return;
    }
    elements.tbody.innerHTML = "";
    const hiddenCols = new Set(snapshot.hiddenColumns || []);
    const selected = new Set(snapshot.selectedRows || []);
    const fragment = document.createDocumentFragment();

    rows.forEach(row => {
      const tr = document.createElement("tr");
      const rowId = getRowId(row);
      if (rowId) {
        tr.dataset.rowId = rowId;
      }
      if (selected.has(rowId)) {
        tr.classList.add("row-selected");
      }
      if (snapshot.rowHeights && snapshot.rowHeights[rowId]) {
        tr.style.height = snapshot.rowHeights[rowId] + "px";
      } else {
        tr.style.height = "";
      }

      const selectorCell = document.createElement("td");
      selectorCell.className = "row-selector-cell";
      const selectorWrap = document.createElement("div");
      selectorWrap.className = "row-selector-wrap";
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.checked = selected.has(rowId);
      checkbox.addEventListener("change", event => {
        event.stopPropagation();
        store.toggleRowSelection(rowId, event.target.checked);
      });
      selectorWrap.appendChild(checkbox);
      const hideBtn = document.createElement("button");
      hideBtn.type = "button";
      hideBtn.className = "row-hide-btn";
      hideBtn.title = "Ocultar fila";
      hideBtn.setAttribute("aria-label", "Ocultar fila");
      hideBtn.textContent = "✕";
      hideBtn.addEventListener("click", event => {
        event.stopPropagation();
        hideRows([rowId]);
      });
      selectorWrap.appendChild(hideBtn);
      selectorCell.appendChild(selectorWrap);
      const resizeHandle = document.createElement("span");
      resizeHandle.className = "row-resize-handle";
      resizeHandle.title = "Arrastra para ajustar la altura";
      resizeHandle.addEventListener("pointerdown", event => {
        startRowResize(event, tr, rowId);
      });
      resizeHandle.addEventListener("dblclick", event => {
        event.stopPropagation();
        tr.style.height = "";
        store.setRowHeight(rowId, null);
      });
      selectorCell.appendChild(resizeHandle);
      tr.appendChild(selectorCell);

      tr.addEventListener("click", event => {
        if (event.target && event.target.closest("a")) {
          return;
        }
        store.toggleRowSelection(rowId);
      });

      snapshot.order.forEach(colId => {
        if (hiddenCols.has(colId)) {
          return;
        }
        const col = columns[colId];
        if (!col) {
          return;
        }
        const td = document.createElement("td");
        if (col.className) {
          td.className = col.className;
        }
        if (col.render) {
          td.innerHTML = col.render(row);
        } else if (col.get) {
          td.textContent = col.get(row);
        } else {
          td.textContent = row[colId] || "";
        }
        tr.appendChild(td);
      });

      fragment.appendChild(tr);
    });

    elements.tbody.appendChild(fragment);
  }

  function renderSummary(totalRows, totalBytes, snapshot, pageInfo) {
    if (elements.count) {
      elements.count.textContent = totalRows.toLocaleString("es-ES");
    }
    if (elements.size) {
      elements.size.textContent = human(totalBytes);
    }
    const perPage = snapshot.pageSize;
    const totalPages = pageInfo.totalPages;
    const currentPage = pageInfo.page;
    if (elements.pageInfo) {
      if (totalRows === 0) {
        elements.pageInfo.textContent = "Sin resultados";
      } else {
        const start = perPage === 0 ? 1 : ((currentPage - 1) * perPage) + 1;
        const end = perPage === 0 ? totalRows : Math.min(totalRows, currentPage * perPage);
        elements.pageInfo.textContent = `Mostrando ${start.toLocaleString("es-ES")} - ${end.toLocaleString("es-ES")} de ${totalRows.toLocaleString("es-ES")}`;
      }
    }
    if (elements.prev) {
      elements.prev.disabled = currentPage <= 1;
    }
    if (elements.next) {
      elements.next.disabled = currentPage >= totalPages;
    }
    if (elements.selectionIndicator && elements.selectionCount) {
      const selectedCount = (snapshot.selectedRows || []).length;
      if (selectedCount > 0) {
        elements.selectionIndicator.hidden = false;
        elements.selectionCount.textContent = selectedCount.toLocaleString("es-ES");
      } else {
        elements.selectionIndicator.hidden = true;
      }
      if (elements.hideSelected) {
        elements.hideSelected.disabled = selectedCount === 0;
      }
    }
  }

  function renderInsights(rows) {
    if (!elements.unitSummary || !elements.extSummary || !elements.pathSummary) {
      return;
    }
    const empty = "<li class=\"muted\">Sin datos</li>";
    elements.unitSummary.innerHTML = empty;
    elements.extSummary.innerHTML = empty;
    elements.pathSummary.innerHTML = empty;
    if (!rows.length) {
      return;
    }

    const byUnit = new Map();
    const byExt = new Map();
    const byPath = new Map();

    rows.forEach(row => {
      const unit = (row.unidad || "(sin unidad)").toString();
      const unitStats = byUnit.get(unit) || { count: 0, size: 0 };
      unitStats.count += 1;
      unitStats.size += Number(row.tamano || 0);
      byUnit.set(unit, unitStats);

      const name = row.nombre || "";
      const ext = name.includes(".") ? name.split(".").pop().toLowerCase() : "(sin extensión)";
      const extStats = byExt.get(ext) || { count: 0 };
      extStats.count += 1;
      byExt.set(ext, extStats);

      const path = (row.ruta || "(sin ruta)").toString();
      const pathStats = byPath.get(path) || { count: 0 };
      pathStats.count += 1;
      byPath.set(path, pathStats);
    });

    elements.unitSummary.innerHTML = Array.from(byUnit.entries()).sort((a, b) => b[1].count - a[1].count || b[1].size - a[1].size).slice(0, 6).map(entry => {
      return "<li>" + escapeHtml(entry[0]) + ": " + entry[1].count.toLocaleString("es-ES") + " archivos (" + escapeHtml(human(entry[1].size)) + ")</li>";
    }).join("") || empty;

    elements.extSummary.innerHTML = Array.from(byExt.entries()).sort((a, b) => b[1].count - a[1].count).slice(0, 6).map(entry => {
      return "<li>" + escapeHtml(entry[0]) + ": " + entry[1].count.toLocaleString("es-ES") + " archivos</li>";
    }).join("") || empty;

    elements.pathSummary.innerHTML = Array.from(byPath.entries()).sort((a, b) => b[1].count - a[1].count).slice(0, 6).map(entry => {
      return "<li>" + escapeHtml(entry[0]) + ": " + entry[1].count.toLocaleString("es-ES") + " archivos</li>";
    }).join("") || empty;
  }

  function computeBytes(rows) {
    return rows.reduce((sum, row) => sum + Number(row.tamano || 0), 0);
  }

  function getCurrentSlice(rows, snapshot) {
    const perPage = snapshot.pageSize;
    if (perPage === 0) {
      return { rows: rows.slice(), page: 1, totalPages: 1 };
    }
    const totalPages = Math.max(1, Math.ceil(rows.length / perPage));
    const safePage = Math.min(snapshot.page, totalPages);
    if (safePage !== snapshot.page) {
      store.setPage(safePage);
    }
    const start = (safePage - 1) * perPage;
    return { rows: rows.slice(start, start + perPage), page: safePage, totalPages };
  }

  function syncSelectAllCheckbox(snapshot) {
    if (!selectAllCheckbox) {
      return;
    }
    if (!lastRenderedRowIds.length) {
      selectAllCheckbox.checked = false;
      selectAllCheckbox.indeterminate = false;
      return;
    }
    const selected = new Set(snapshot.selectedRows || []);
    const onPage = lastRenderedRowIds.filter(id => selected.has(id));
    selectAllCheckbox.checked = onPage.length === lastRenderedRowIds.length && onPage.length > 0;
    selectAllCheckbox.indeterminate = onPage.length > 0 && onPage.length < lastRenderedRowIds.length;
  }
  function getRowId(row) {
    if (!row) {
      return "";
    }
    if (row.sha) {
      return String(row.sha);
    }
    const ruta = (row.ruta || "").toString();
    const nombre = (row.nombre || "").toString();
    const size = Number(row.tamano || 0);
    return `${ruta}::${nombre}::${size}`;
  }

  function joinWinPath(dir, name) {
    if (!dir) {
      return name || "";
    }
    if (!name) {
      return dir;
    }
    const sep = (dir.endsWith("\\") || dir.endsWith("/")) ? "" : "\\";
    return dir + sep + name;
  }

  function toFileUrl(path) {
    if (!path) {
      return "";
    }
    let normalized = path.replace(/\\/g, "/").replace(/^\.\/+/, "");
    const driveMatch = normalized.match(/^([A-Za-z]):\/?(.*)$/);
    let prefix = "file:///";
    let rest = normalized;
    if (driveMatch) {
      prefix += driveMatch[1].toUpperCase() + ":/";
      rest = driveMatch[2];
    }
    const encoded = rest.split("/").filter(Boolean).map(part => encodeURIComponent(part)).join("/");
    return prefix + encoded;
  }

  function cellFileLink(row) {
    const full = joinWinPath(row.ruta, row.nombre);
    const url = toFileUrl(full);
    const label = escapeHtml(row.nombre || "");
    if (!url) {
      return label;
    }
    return `<a class="cell-link" href="${url}" title="Abrir archivo" target="_blank" rel="noopener">${label}</a>`;
  }

  function cellFolderLink(row) {
    const url = toFileUrl(row.ruta || "");
    const label = escapeHtml(row.ruta || "");
    if (!url) {
      return label;
    }
    return `<a class="cell-link" href="${url}" title="Abrir carpeta" target="_blank" rel="noopener">${label}</a>`;
  }

  function human(bytes) {
    if (!bytes || Number.isNaN(bytes)) {
      return "0 B";
    }
    const units = ["B", "KB", "MB", "GB", "TB", "PB"];
    let value = Number(bytes);
    let idx = 0;
    while (value >= 1024 && idx < units.length - 1) {
      value /= 1024;
      idx += 1;
    }
    return value.toFixed(idx === 0 ? 0 : 1) + " " + units[idx];
  }

  function formatDate(value) {
    return value ? value.replace("T", " ").replace("Z", "") : "";
  }

  function escapeHtml(text) {
    return (text ?? "").toString().replace(/[&<>\"]/g, ch => {
      switch (ch) {
        case "&": return "&amp;";
        case "<": return "&lt;";
        case ">": return "&gt;";
        case '"': return "&quot;";
        default: return ch;
      }
    });
  }

  function downloadCsv(rows, snapshot) {
    if (!rows.length) {
      return;
    }
    const hidden = new Set(snapshot.hiddenColumns || []);
    const visibleOrder = snapshot.order.filter(colId => !hidden.has(colId));
    const headers = visibleOrder.map(colId => (columns[colId] ? columns[colId].label.replace(/&ntilde;/g, "ñ").replace(/<[^>]+>/g, "") : colId));
    const lines = [headers.join(";")];
    rows.forEach(row => {
      const values = visibleOrder.map(colId => {
        const col = columns[colId];
        const raw = col && col.csv ? col.csv(row) : (col && col.get ? col.get(row) : row[colId]);
        const text = (raw ?? "").toString().replace(/"/g, '""');
        return '"' + text + '"';
      });
      lines.push(values.join(";"));
    });
    const blob = new Blob([lines.join("\r\n")], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "inventario_filtrado.csv";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    window.setTimeout(() => URL.revokeObjectURL(url), 200);
  }

})(window, document);
