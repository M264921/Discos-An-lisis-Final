(function(){
  "use strict";

  const scripts = [
    "./assets/js/mingomedia-config.js",
    "./assets/js/inventory-state.js",
    "./assets/js/inventory-app.js"
  ];

  function loadSequential(list) {
    if (!list.length) {
      return;
    }
    const src = list.shift();
    const script = document.createElement("script");
    script.src = src;
    script.async = false;
    script.defer = false;
    script.onload = function() {
      loadSequential(list);
    };
    script.onerror = function(error) {
      console.error("No se pudo cargar", src, error);
      loadSequential(list);
    };
    document.head.appendChild(script);
  }

  loadSequential(scripts.slice());
})();
