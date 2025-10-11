(function(window){
  "use strict";

  if (!window.MingoMediaConfig || typeof window.MingoMediaConfig !== "object") {
    window.MingoMediaConfig = {};
  }

  const cfg = window.MingoMediaConfig;

  if (!cfg.access || typeof cfg.access !== "object") {
    cfg.access = {};
  }

  if (!cfg.view || typeof cfg.view !== "object") {
    cfg.view = {};
  }

  cfg.access = Object.assign({
    enabled: false,
    requireEmail: true,
    requirePin: false,
    allowedEmails: [],
    allowedDomains: [],
    users: [],
    message: "Introduce tu correo para continuar.",
    rememberSession: true,
    version: "v1"
  }, cfg.access);

  cfg.view = Object.assign({
    storagePrefix: "mingomedia.inventory.view",
    defaultUser: "public"
  }, cfg.view);

})(window);
