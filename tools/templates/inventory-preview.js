  // BEGIN MINGO PREVIEW (generated from tools/templates/inventory-preview.js)
  function openPreview(href, type) {
    if (openPreview.close) openPreview.close();
    const controller = new AbortController();
    const previousFocus = document.activeElement;
    const previousOverflow = document.body.style.overflow;
    const overlay = document.createElement('div');
    overlay.className = 'mingo-preview';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', 'Vista previa del archivo');
    overlay.setAttribute('data-no-intercept', '');
    overlay.style.cssText = 'position:fixed;inset:0;z-index:10000;background:#0f172a;color:#f8fafc;display:flex;flex-direction:column;padding:env(safe-area-inset-top) 0 env(safe-area-inset-bottom);';
    const header = document.createElement('div');
    header.style.cssText = 'display:flex;align-items:center;gap:12px;flex-wrap:wrap;padding:12px 16px;border-bottom:1px solid #475569';
    const title = document.createElement('strong');
    try { title.textContent = decodeURIComponent(new URL(href).pathname.split('/').pop()); }
    catch (_) { title.textContent = 'Archivo'; }
    title.style.cssText = 'flex:1;overflow-wrap:anywhere;min-width:100px';
    const download = document.createElement('a');
    download.textContent = 'Descargar';
    download.href = href;
    download.download = title.textContent;
    download.style.color = '#93c5fd';
    const closeButton = document.createElement('button');
    closeButton.textContent = 'Cerrar';
    closeButton.style.cssText = 'padding:10px 16px;background:#2563eb;color:white;border:0;border-radius:8px;cursor:pointer';
    header.append(title, download, closeButton);
    const body = document.createElement('div');
    body.style.cssText = 'flex:1;min-height:0;overflow:auto;display:grid;place-items:center;padding:16px';
    const status = document.createElement('p');
    status.setAttribute('role', 'status');
    status.textContent = 'Cargando vista previa…';
    body.append(status);
    overlay.append(header, body);
    document.body.append(overlay);
    document.body.style.overflow = 'hidden';
    let media;
    let closed = false;
    function close() {
      if (closed) return;
      closed = true;
      controller.abort();
      if (media) { media.pause(); media.removeAttribute('src'); media.load(); }
      overlay.remove();
      document.removeEventListener('keydown', keydown, true);
      document.body.style.overflow = previousOverflow;
      if (previousFocus && previousFocus.isConnected) previousFocus.focus();
      openPreview.close = null;
    }
    function keydown(event) {
      if (event.key === 'Escape') { event.preventDefault(); event.stopImmediatePropagation(); close(); }
      if (event.key === 'Tab') {
        const controls = Array.from(overlay.querySelectorAll('a[href],button,video,audio,iframe'));
        if (event.shiftKey && document.activeElement === controls[0]) { event.preventDefault(); controls[controls.length - 1].focus(); }
        else if (!event.shiftKey && document.activeElement === controls[controls.length - 1]) { event.preventDefault(); controls[0].focus(); }
      }
    }
    function failure(message) {
      if (closed) return;
      body.replaceChildren(status);
      status.textContent = message;
    }
    openPreview.close = close;
    closeButton.addEventListener('click', close);
    document.addEventListener('keydown', keydown, true);
    closeButton.focus();
    (async () => {
      try {
        // Same-origin requests carry the private gateway's HttpOnly session cookie.
        if (/^https?:$/.test(new URL(href).protocol) && new URL(href).origin === location.origin) {
          const response = await fetch(href, { method: 'HEAD', signal: controller.signal });
          if (!response.ok) {
            if (response.status === 404) throw new Error('El archivo ya no existe en la ruta del inventario o la unidad se ha desconectado.');
            if (response.status === 401) throw new Error('La sesión ha caducado. Recarga la página para entrar de nuevo.');
            throw new Error('No se puede acceder a este archivo (' + response.status + ').');
          }
        }
        if (closed) return;
        if (type === 'text' || type === 'html') {
          const response = await fetch(href, { signal: controller.signal });
          if (!response.ok) throw new Error('No se pudo leer el archivo (' + response.status + ').');
          const limit = 2 * 1024 * 1024;
          if (Number(response.headers.get('Content-Length')) > limit) {
            if (response.body) await response.body.cancel();
            throw new Error('El texto supera 2 MB. Puedes descargarlo para abrirlo completo.');
          }
          const reader = response.body.getReader();
          const chunks = [];
          let size = 0;
          while (true) {
            const { value, done } = await reader.read();
            if (done) break;
            size += value.length;
            if (size > limit) { await reader.cancel(); throw new Error('El texto supera 2 MB. Puedes descargarlo para abrirlo completo.'); }
            chunks.push(value);
          }
          if (closed) return;
          const bytes = new Uint8Array(size);
          let offset = 0;
          chunks.forEach(chunk => { bytes.set(chunk, offset); offset += chunk.length; });
          const pre = document.createElement('pre');
          pre.style.cssText = 'align-self:start;justify-self:stretch;margin:0;white-space:pre-wrap;overflow-wrap:anywhere;font:14px/1.6 monospace';
          pre.textContent = new TextDecoder().decode(bytes);
          body.replaceChildren(pre);
        } else if (type === 'image') {
          const img = document.createElement('img');
          img.alt = title.textContent;
          img.style.cssText = 'max-width:100%;max-height:100%;object-fit:contain';
          img.onload = () => { if (!closed) body.replaceChildren(img); };
          img.onerror = () => failure('No se pudo cargar la imagen. Comprueba que el archivo siga disponible.');
          img.src = href;
        } else if (type === 'pdf') {
          const frame = document.createElement('iframe');
          frame.title = title.textContent;
          frame.style.cssText = 'width:100%;height:100%;min-height:65vh;border:0;background:white';
          frame.src = href;
          body.replaceChildren(frame);
        } else if (type === 'audio' || type === 'video') {
          media = document.createElement(type);
          media.controls = true;
          media.playsInline = true;
          media.preload = 'metadata';
          media.style.cssText = 'max-width:100%;max-height:100%;width:100%';
          media.onerror = () => failure('Este navegador no puede reproducir el archivo. Puedes descargarlo y abrirlo con otra aplicación.');
          media.src = href;
          body.replaceChildren(media);
        } else {
          failure('Este formato no tiene vista previa en el navegador. Pulsa Descargar para abrirlo con una aplicación compatible.');
        }
      } catch (error) {
        if (!closed && error.name !== 'AbortError') failure(error.message || 'No se pudo cargar el archivo.');
      }
    })();
    return true;
  }
  // END MINGO PREVIEW
