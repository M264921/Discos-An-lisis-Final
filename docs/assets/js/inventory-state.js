(function(window){
  "use strict";

  const FALLBACK_PREFIX = "mingomedia.inventory.view";
  const FALLBACK_WIDTH = 150;
  const FALLBACK_MIN_WIDTH = 80;

  function normalizeUserKey(value, fallback) {
    if (value === undefined || value === null) {
      return fallback || "public";
    }
    let text = String(value).trim();
    if (!text) {
      return fallback || "public";
    }
    text = text.toLowerCase();
    return text.replace(/[^a-z0-9_.@-]+/g, "_");
  }

  function sanitizeOrder(order, available) {
    const allowed = Array.isArray(available) && available.length ? available : [];
    const result = [];
    const seen = new Set();
    const source = Array.isArray(order) ? order : [];

    source.forEach(function(item){
      const id = item === undefined || item === null ? "" : String(item).trim();
      if (!id) { return; }
      if (allowed.length && !allowed.includes(id)) { return; }
      if (seen.has(id)) { return; }
      seen.add(id);
      result.push(id);
    });

    const fallbackSource = allowed.length ? allowed : source;
    fallbackSource.forEach(function(item){
      const id = item === undefined || item === null ? "" : String(item).trim();
      if (!id || seen.has(id)) { return; }
      seen.add(id);
      result.push(id);
    });

    return result;
  }

  function sanitizeWidths(widths, available, defaults, minWidth) {
    const result = {};
    const list = Array.isArray(available) && available.length ? available : Object.keys(widths || {});
    const base = defaults && typeof defaults === "object" ? defaults : {};
    const floor = typeof minWidth === "number" && minWidth > 0 ? minWidth : FALLBACK_MIN_WIDTH;

    list.forEach(function(column){
      const key = column === undefined || column === null ? "" : String(column).trim();
      if (!key) { return; }
      const candidate = widths && Object.prototype.hasOwnProperty.call(widths, key) ? widths[key] : undefined;
      const defaultWidth = base && Object.prototype.hasOwnProperty.call(base, key) ? base[key] : FALLBACK_WIDTH;
      let value = Number(candidate);
      if (!Number.isFinite(value) || value <= 0) {
        value = Number(defaultWidth);
      }
      if (!Number.isFinite(value) || value <= 0) {
        value = FALLBACK_WIDTH;
      }
      result[key] = Math.max(floor, Math.round(value));
    });

    return result;
  }

  function sanitizeRowHeights(input) {
    const result = {};
    if (!input || typeof input !== "object") {
      return result;
    }
    Object.keys(input).forEach(function(key){
      const value = Number(input[key]);
      if (Number.isFinite(value) && value > 0) {
        result[String(key)] = value;
      }
    });
    return result;
  }

  function createMingoInventoryStore(options) {
    const opts = options && typeof options === "object" ? options : {};
    const allColumns = Array.isArray(opts.allColumns) ? opts.allColumns.filter(Boolean).map(function(col){return String(col);}) : [];
    const defaultOrder = sanitizeOrder(Array.isArray(opts.defaultOrder) ? opts.defaultOrder : allColumns, allColumns);
    const minColumnWidth = typeof opts.minColumnWidth === "number" && opts.minColumnWidth > 0 ? opts.minColumnWidth : FALLBACK_MIN_WIDTH;
    const defaultWidths = sanitizeWidths(opts.defaultWidths || {}, allColumns.length ? allColumns : defaultOrder, opts.defaultWidths || {}, minColumnWidth);
    const storagePrefix = typeof opts.storagePrefix === "string" && opts.storagePrefix.trim() ? opts.storagePrefix.trim() : FALLBACK_PREFIX;
    const defaultUserKey = normalizeUserKey(opts.defaultUserKey || opts.defaultUser || "public", "public");

    const availableColumns = (allColumns.length ? allColumns.slice() : defaultOrder.slice()).map(function(col){return String(col);});

    const state = {
      order: defaultOrder.slice(),
      widths: Object.assign({}, defaultWidths),
      hiddenColumns: new Set(Array.isArray(opts.hiddenColumns) ? opts.hiddenColumns.map(function(col){return String(col);}) : []),
      hiddenRows: new Set(Array.isArray(opts.hiddenRows) ? opts.hiddenRows.map(function(id){return String(id);}) : []),
      rowHeights: sanitizeRowHeights(opts.rowHeights),
      selectedRows: new Set(Array.isArray(opts.selectedRows) ? opts.selectedRows.map(function(id){return String(id);}) : []),
      selectionOrder: Array.isArray(opts.selectionOrder) ? opts.selectionOrder.map(function(id){return String(id);}) : [],
      filters: Object.assign({}, opts.initialFilters || {}),
      search: opts.initialSearch ? String(opts.initialSearch) : "",
      pageSize: typeof opts.initialPageSize === "number" && opts.initialPageSize >= 0 ? Math.floor(opts.initialPageSize) : 50,
      page: typeof opts.initialPage === "number" && opts.initialPage > 0 ? Math.floor(opts.initialPage) : 1,
      activeUnit: opts.initialActiveUnit ? String(opts.initialActiveUnit) : "",
      defaultOrder: defaultOrder.slice(),
      defaultWidths: Object.assign({}, defaultWidths)
    };

    const defaults = {
      hiddenColumns: new Set(state.hiddenColumns),
      hiddenRows: new Set(state.hiddenRows),
      rowHeights: Object.assign({}, state.rowHeights),
      filters: Object.assign({}, state.filters),
      search: state.search,
      pageSize: state.pageSize,
      page: state.page,
      activeUnit: state.activeUnit
    };

    if (!state.selectionOrder.length && state.selectedRows.size) {
      state.selectionOrder = Array.from(state.selectedRows);
    }

    let userKey = normalizeUserKey(opts.initialUserKey || opts.initialUser || defaultUserKey, defaultUserKey);
    const listeners = new Map();

    function getStorageKey() {
      if (!userKey) {
        return null;
      }
      return storagePrefix + ":" + userKey;
    }

    function snapshot() {
      return {
        order: state.order.slice(),
        widths: Object.assign({}, state.widths),
        hiddenColumns: Array.from(state.hiddenColumns),
        filters: Object.assign({}, state.filters),
        search: state.search,
        pageSize: state.pageSize,
        page: state.page,
        activeUnit: state.activeUnit,
        hiddenRows: Array.from(state.hiddenRows),
        rowHeights: Object.assign({}, state.rowHeights),
        selectedRows: Array.from(state.selectedRows),
        selectionOrder: state.selectionOrder.slice(),
        userKey: userKey
      };
    }

    function emit(event, detail) {
      const handlers = listeners.get(event);
      if (!handlers || !handlers.size) {
        return;
      }
      handlers.forEach(function(handler){
        try {
          handler(detail, snapshot());
        } catch (error) {
          console.error("Inventory store listener error", error);
        }
      });
    }

    function emitChange() {
      emit("change", snapshot());
    }

    function persistView() {
      const key = getStorageKey();
      if (!key) {
        return false;
      }
      const payload = {
        order: state.order.slice(),
        widths: Object.assign({}, state.widths),
        hiddenColumns: Array.from(state.hiddenColumns),
        hiddenRows: Array.from(state.hiddenRows),
        rowHeights: Object.assign({}, state.rowHeights),
        selectedRows: Array.from(state.selectedRows),
        selectionOrder: state.selectionOrder.slice()
      };
      try {
        window.localStorage.setItem(key, JSON.stringify(payload));
        return true;
      } catch (error) {
        console.warn("No se pudo guardar la vista", error);
        return false;
      }
    }

    function applyViewSnapshot(saved) {
      if (!saved || typeof saved !== "object") {
        return;
      }
      if (Array.isArray(saved.order) && saved.order.length) {
        state.order = sanitizeOrder(saved.order, availableColumns);
      } else {
        state.order = state.defaultOrder.slice();
      }
      if (saved.widths && typeof saved.widths === "object") {
        const merged = Object.assign({}, state.defaultWidths, saved.widths);
        state.widths = sanitizeWidths(merged, availableColumns, state.defaultWidths, minColumnWidth);
      } else {
        state.widths = sanitizeWidths(state.defaultWidths, availableColumns, state.defaultWidths, minColumnWidth);
      }
      state.hiddenColumns = new Set(Array.isArray(saved.hiddenColumns) ? saved.hiddenColumns.filter(function(col){return availableColumns.includes(col);}).map(function(col){return String(col);}) : []);
      state.hiddenRows = new Set(Array.isArray(saved.hiddenRows) ? saved.hiddenRows.map(function(id){return String(id);}) : []);
      state.rowHeights = sanitizeRowHeights(saved.rowHeights);
      const selected = Array.isArray(saved.selectedRows) ? saved.selectedRows.map(function(id){return String(id);}) : [];
      state.selectedRows = new Set(selected);
      state.selectionOrder = Array.isArray(saved.selectionOrder) && saved.selectionOrder.length ? saved.selectionOrder.map(function(id){return String(id);}) : selected.slice();
    }

    function loadFromStorageInternal(triggerEvents) {
      const key = getStorageKey();
      if (!key) {
        return false;
      }
      let raw = null;
      try {
        raw = window.localStorage.getItem(key);
      } catch (error) {
        console.warn("No se pudo leer la vista", error);
        return false;
      }
      if (!raw) {
        return false;
      }
      try {
        const saved = JSON.parse(raw);
        applyViewSnapshot(saved);
        if (triggerEvents) {
          emit("view:hydrate", snapshot());
          emitChange();
        }
        return true;
      } catch (error) {
        console.warn("Vista almacenada corrupta", error);
        return false;
      }
    }

    function ensureSelectionOrder() {
      if (!state.selectionOrder.length && state.selectedRows.size) {
        state.selectionOrder = Array.from(state.selectedRows);
      } else if (state.selectionOrder.length) {
        const valid = new Set(state.selectedRows);
        state.selectionOrder = state.selectionOrder.filter(function(id){return valid.has(id);});
        if (state.selectionOrder.length < state.selectedRows.size) {
          state.selectedRows.forEach(function(id){
            if (!state.selectionOrder.includes(id)) {
              state.selectionOrder.push(id);
            }
          });
        }
      }
    }

    const api = {
      getState: snapshot,
      on: function(event, handler){
        if (!event || typeof handler !== "function") {
          return function(){};
        }
        const key = String(event);
        const handlers = listeners.get(key) || new Set();
        handlers.add(handler);
        listeners.set(key, handlers);
        return function(){
          handlers.delete(handler);
          if (!handlers.size) {
            listeners.delete(key);
          }
        };
      },
      off: function(event, handler){
        if (!event) { return; }
        const handlers = listeners.get(String(event));
        if (!handlers) { return; }
        if (typeof handler === "function") {
          handlers.delete(handler);
        }
        if (!handler || !handlers.size) {
          listeners.delete(String(event));
        }
      },
      setUser: function(next){
        const normalized = normalizeUserKey(next, defaultUserKey);
        const changed = normalized !== userKey;
        userKey = normalized;
        const hydrated = loadFromStorageInternal(true);
        emit("user:change", { userKey: userKey });
        if (!hydrated && changed) {
          emitChange();
        }
      },
      getUser: function(){
        return userKey;
      },
      resetColumns: function(){
        state.order = state.defaultOrder.slice();
        state.widths = sanitizeWidths(state.defaultWidths, availableColumns, state.defaultWidths, minColumnWidth);
        state.hiddenColumns = new Set();
        persistView();
        emit("columns:order", { order: state.order.slice() });
        emit("columns:hidden", { hidden: [] });
        emit("columns:width", { widths: Object.assign({}, state.widths) });
        emitChange();
      },
      resetView: function(){
        state.order = state.defaultOrder.slice();
        state.widths = sanitizeWidths(state.defaultWidths, availableColumns, state.defaultWidths, minColumnWidth);
        state.hiddenColumns = new Set(defaults.hiddenColumns);
        state.hiddenRows = new Set(defaults.hiddenRows);
        state.rowHeights = sanitizeRowHeights(defaults.rowHeights);
        state.filters = Object.assign({}, defaults.filters);
        state.search = defaults.search;
        state.pageSize = defaults.pageSize;
        state.page = defaults.page;
        state.activeUnit = defaults.activeUnit;
        state.selectedRows.clear();
        state.selectionOrder = [];
        persistView();
        emit("columns:order", { order: state.order.slice() });
        emit("columns:hidden", { hidden: Array.from(state.hiddenColumns) });
        emit("columns:width", { widths: Object.assign({}, state.widths) });
        emit("rows:hidden", { hidden: Array.from(state.hiddenRows) });
        emit("rows:height", { heights: Object.assign({}, state.rowHeights) });
        emit("filters:change", { filters: Object.assign({}, state.filters), search: state.search, page: state.page, activeUnit: state.activeUnit });
        emit("page:change", { pageSize: state.pageSize, page: state.page });
        emit("selection:change", { selected: [], order: [] });
        emitChange();
      },
      setColumnOrder: function(order){
        const next = sanitizeOrder(order, availableColumns);
        if (next.join("|") === state.order.join("|")) {
          return;
        }
        state.order = next;
        persistView();
        emit("columns:order", { order: state.order.slice() });
        emitChange();
      },
      setColumnWidth: function(columnId, width){
        const key = columnId === undefined || columnId === null ? "" : String(columnId).trim();
        if (!key) { return; }
        const value = Math.max(minColumnWidth, Math.round(Number(width)) || 0);
        if (state.widths[key] === value) {
          return;
        }
        state.widths[key] = value;
        persistView();
        emit("columns:width", { columnId: key, width: value, widths: Object.assign({}, state.widths) });
        emitChange();
      },
      setHiddenColumns: function(columns){
        const next = new Set();
        (Array.isArray(columns) ? columns : []).forEach(function(col){
          const key = col === undefined || col === null ? "" : String(col).trim();
          if (key && availableColumns.includes(key)) {
            next.add(key);
          }
        });
        const current = Array.from(state.hiddenColumns);
        const nextList = Array.from(next);
        if (current.length === nextList.length && current.every(function(col, idx){return col === nextList[idx];})) {
          return;
        }
        state.hiddenColumns = next;
        persistView();
        emit("columns:hidden", { hidden: nextList.slice() });
        emitChange();
      },
      hideColumn: function(columnId){
        const key = columnId === undefined || columnId === null ? "" : String(columnId).trim();
        if (!key || !availableColumns.includes(key) || state.hiddenColumns.has(key)) {
          return;
        }
        state.hiddenColumns.add(key);
        persistView();
        emit("columns:hidden", { hidden: Array.from(state.hiddenColumns) });
        emitChange();
      },
      showColumn: function(columnId){
        const key = columnId === undefined || columnId === null ? "" : String(columnId).trim();
        if (!key || !state.hiddenColumns.has(key)) {
          return;
        }
        state.hiddenColumns.delete(key);
        persistView();
        emit("columns:hidden", { hidden: Array.from(state.hiddenColumns) });
        emitChange();
      },
      setHiddenRows: function(rowIds){
        const next = new Set();
        (Array.isArray(rowIds) ? rowIds : []).forEach(function(id){
          const key = id === undefined || id === null ? "" : String(id);
          if (key) {
            next.add(key);
          }
        });
        const current = Array.from(state.hiddenRows);
        const nextList = Array.from(next);
        if (current.length === nextList.length && current.every(function(id, idx){return id === nextList[idx];})) {
          return;
        }
        state.hiddenRows = next;
        persistView();
        emit("rows:hidden", { hidden: nextList.slice() });
        emitChange();
      },
      toggleRowHidden: function(rowId){
        const key = rowId === undefined || rowId === null ? "" : String(rowId);
        if (!key) { return; }
        if (state.hiddenRows.has(key)) {
          state.hiddenRows.delete(key);
        } else {
          state.hiddenRows.add(key);
        }
        persistView();
        emit("rows:hidden", { hidden: Array.from(state.hiddenRows) });
        emitChange();
      },
      setRowHeight: function(rowId, height){
        const key = rowId === undefined || rowId === null ? "" : String(rowId);
        if (!key) { return; }
        const value = Number(height);
        if (!Number.isFinite(value) || value <= 0) {
          if (Object.prototype.hasOwnProperty.call(state.rowHeights, key)) {
            delete state.rowHeights[key];
            persistView();
            emit("rows:height", { rowId: key, height: null, heights: Object.assign({}, state.rowHeights) });
            emitChange();
          }
          return;
        }
        if (state.rowHeights[key] === value) {
          return;
        }
        state.rowHeights[key] = value;
        persistView();
        emit("rows:height", { rowId: key, height: value, heights: Object.assign({}, state.rowHeights) });
        emitChange();
      },
      setSearch: function(value){
        const next = value ? String(value).trim() : "";
        if (state.search === next) { return; }
        state.search = next;
        state.page = 1;
        emit("filters:change", { filters: Object.assign({}, state.filters), search: state.search, page: state.page, activeUnit: state.activeUnit });
        emitChange();
      },
      setFilter: function(columnId, value){
        const key = columnId === undefined || columnId === null ? "" : String(columnId).trim();
        if (!key) { return; }
        const next = value ? String(value).trim() : "";
        const current = Object.prototype.hasOwnProperty.call(state.filters, key) ? state.filters[key] : "";
        if (current === next) { return; }
        if (next) {
          state.filters[key] = next;
        } else {
          delete state.filters[key];
        }
        state.page = 1;
        emit("filters:change", { filters: Object.assign({}, state.filters), search: state.search, page: state.page, activeUnit: state.activeUnit });
        emitChange();
      },
      setFilters: function(filters){
        const next = {};
        if (filters && typeof filters === "object") {
          Object.keys(filters).forEach(function(key){
            const value = filters[key];
            if (value !== undefined && value !== null && String(value).trim()) {
              next[String(key)] = String(value).trim();
            }
          });
        }
        const currentKeys = Object.keys(state.filters);
        const nextKeys = Object.keys(next);
        if (currentKeys.length === nextKeys.length && currentKeys.every(function(key){ return state.filters[key] === next[key]; })) {
          return;
        }
        state.filters = next;
        state.page = 1;
        emit("filters:change", { filters: Object.assign({}, state.filters), search: state.search, page: state.page, activeUnit: state.activeUnit });
        emitChange();
      },
      clearFilters: function(){
        if (!Object.keys(state.filters).length && !state.search && !state.activeUnit) {
          return;
        }
        state.filters = {};
        state.search = "";
        state.activeUnit = "";
        state.page = 1;
        emit("filters:change", { filters: {}, search: "", page: state.page, activeUnit: "" });
        emitChange();
      },
      setPageSize: function(size){
        const value = typeof size === "number" ? Math.max(0, Math.floor(size)) : 0;
        if (state.pageSize === value) { return; }
        state.pageSize = value;
        state.page = 1;
        emit("page:change", { pageSize: state.pageSize, page: state.page });
        emitChange();
      },
      setPage: function(page){
        const value = typeof page === "number" ? Math.max(1, Math.floor(page)) : 1;
        if (state.page === value) { return; }
        state.page = value;
        emit("page:change", { pageSize: state.pageSize, page: state.page });
        emitChange();
      },
      setActiveUnit: function(unit){
        const value = unit ? String(unit).trim() : "";
        if (state.activeUnit === value) { return; }
        state.activeUnit = value;
        state.page = 1;
        emit("filters:change", { filters: Object.assign({}, state.filters), search: state.search, page: state.page, activeUnit: state.activeUnit });
        emitChange();
      },
      updateSelection: function(options){
        const optsSel = options && typeof options === "object" ? options : {};
        const add = Array.isArray(optsSel.add) ? optsSel.add.map(function(id){return String(id);}) : [];
        const remove = Array.isArray(optsSel.remove) ? new Set(optsSel.remove.map(function(id){return String(id);})): new Set();
        let changed = false;
        add.forEach(function(id){
          if (!id || remove.has(id)) { return; }
          if (!state.selectedRows.has(id)) {
            state.selectedRows.add(id);
            state.selectionOrder.push(id);
            changed = true;
          }
        });
        if (remove.size) {
          state.selectionOrder = state.selectionOrder.filter(function(id){
            if (!remove.has(id)) { return true; }
            if (state.selectedRows.has(id)) {
              state.selectedRows.delete(id);
              changed = true;
            }
            return false;
          });
          remove.forEach(function(id){
            if (state.selectedRows.delete(id)) {
              changed = true;
            }
          });
        }
        ensureSelectionOrder();
        if (changed) {
          persistView();
          emit("selection:change", { selected: Array.from(state.selectedRows), order: state.selectionOrder.slice() });
          emitChange();
        }
      },
      toggleRowSelection: function(rowId, forced){
        const key = rowId === undefined || rowId === null ? "" : String(rowId);
        if (!key) { return; }
        const has = state.selectedRows.has(key);
        const shouldSelect = typeof forced === "boolean" ? forced : !has;
        if (shouldSelect && !has) {
          state.selectedRows.add(key);
          if (!state.selectionOrder.includes(key)) {
            state.selectionOrder.push(key);
          }
        } else if (!shouldSelect && has) {
          state.selectedRows.delete(key);
          state.selectionOrder = state.selectionOrder.filter(function(id){return id !== key;});
        } else {
          return;
        }
        ensureSelectionOrder();
        persistView();
        emit("selection:change", { selected: Array.from(state.selectedRows), order: state.selectionOrder.slice(), rowId: key });
        emitChange();
      },
      setSelectedRows: function(rowIds){
        const next = new Set();
        (Array.isArray(rowIds) ? rowIds : []).forEach(function(id){
          const key = id === undefined || id === null ? "" : String(id);
          if (key) {
            next.add(key);
          }
        });
        const current = Array.from(state.selectedRows);
        const nextList = Array.from(next);
        if (current.length === nextList.length && current.every(function(id, idx){return id === nextList[idx];})) {
          return;
        }
        state.selectedRows = next;
        state.selectionOrder = nextList.slice();
        ensureSelectionOrder();
        persistView();
        emit("selection:change", { selected: Array.from(state.selectedRows), order: state.selectionOrder.slice() });
        emitChange();
      },
      clearSelection: function(){
        if (!state.selectedRows.size && !state.selectionOrder.length) {
          return;
        }
        state.selectedRows.clear();
        state.selectionOrder = [];
        persistView();
        emit("selection:change", { selected: [], order: [] });
        emitChange();
      },
      getSelection: function(){
        return { selected: Array.from(state.selectedRows), order: state.selectionOrder.slice() };
      },
      persist: function(){
        persistView();
      },
      loadFromStorage: function(){
        loadFromStorageInternal(true);
      }
    };

    loadFromStorageInternal(false);

    return api;
  }

  window.createMingoInventoryStore = createMingoInventoryStore;
})(window);
