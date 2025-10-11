import http from "http";
import { URL } from "url";
import fs from "fs";
import path from "path";

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || "0.0.0.0";
const DEVICES_SOURCE = process.env.DLNA_DEVICES || "";
const DEVICES_FILE = process.env.DLNA_DEVICES_FILE || "devices.json";

const devices = loadDevices();
const playbackLog = [];

const server = http.createServer(async (req, res) => {
  const origin = req.headers.origin || "*";
  const requestUrl = new URL(req.url || "/", `http://${req.headers.host}`);

  if (req.method === "OPTIONS") {
    writeCors(res, origin);
    res.writeHead(204);
    res.end();
    return;
  }

  if (requestUrl.pathname === "/healthz") {
    writeCors(res, origin);
    respondJson(res, 200, { ok: true });
    return;
  }

  if (requestUrl.pathname === "/devices") {
    writeCors(res, origin);
    respondJson(res, 200, devices);
    return;
  }

  if (requestUrl.pathname === "/play") {
    writeCors(res, origin);
    await handlePlay(requestUrl, res);
    return;
  }

  writeCors(res, origin);
  respondJson(res, 404, { ok: false, error: "Ruta no encontrada." });
});

server.listen(PORT, HOST, () => {
  console.log(`[dlna-helper] Escuchando en http://${HOST}:${PORT}`);
  if (!devices.length) {
    console.log("[dlna-helper] Sin dispositivos definidos. Exporta DLNA_DEVICES o crea devices.json.");
  } else {
    console.log("[dlna-helper] Dispositivos disponibles:");
    devices.forEach((device) => {
      console.log(`  - ${device.id}: ${device.name} (${device.playUrl})`);
    });
  }
});

function writeCors(res, origin) {
  res.setHeader("Access-Control-Allow-Origin", origin);
  res.setHeader("Access-Control-Allow-Methods", "GET,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

function respondJson(res, statusCode, payload) {
  res.writeHead(statusCode, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(payload));
}

function loadDevices() {
  const list = [];

  if (DEVICES_SOURCE) {
    list.push(...parseDevices(DEVICES_SOURCE));
  }

  const filePath = path.resolve(process.cwd(), DEVICES_FILE);
  if (fs.existsSync(filePath)) {
    try {
      const raw = fs.readFileSync(filePath, "utf-8");
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        parsed.forEach((device) => {
          if (device && device.id && device.playUrl) {
            list.push({
              id: String(device.id),
              name: device.name ? String(device.name) : `DLNA ${device.id}`,
              playUrl: String(device.playUrl)
            });
          }
        });
      }
    } catch (error) {
      console.warn("[dlna-helper] No se pudo leer devices.json:", error.message);
    }
  }

  const unique = new Map();
  list.forEach((device) => {
    if (device.id && device.playUrl) {
      unique.set(device.id, device);
    }
  });

  return Array.from(unique.values());
}

function parseDevices(source) {
  return source.split(/[;,]/).map((entry, index) => {
    const [idPart, namePart, urlPart] = entry.split("|").map((value) => value && value.trim());
    const id = idPart || `dlna-${index + 1}`;
    const playUrl = urlPart || "";
    if (!playUrl) {
      return null;
    }
    return {
      id,
      name: namePart || `DLNA ${id}`,
      playUrl
    };
  }).filter(Boolean);
}

async function handlePlay(requestUrl, res) {
  const targetUrl = requestUrl.searchParams.get("target");
  const deviceId = requestUrl.searchParams.get("deviceId");
  const friendlyName = requestUrl.searchParams.get("name") || targetUrl;

  if (!targetUrl || !deviceId) {
    respondJson(res, 400, { ok: false, error: "Faltan parámetros deviceId o target." });
    return;
  }

  const device = devices.find((entry) => entry.id === deviceId);
  if (!device) {
    respondJson(res, 404, { ok: false, error: "Dispositivo no encontrado." });
    return;
  }

  playbackLog.push({
    device: device.id,
    name: friendlyName,
    target: targetUrl,
    at: new Date().toISOString()
  });

  console.log(`[dlna-helper] Solicitud: ${friendlyName} -> ${device.name}`);
  console.log(`  Destino: ${targetUrl}`);
  console.log(`  Utiliza device.playUrl para integrar con tu stack DLNA.`);

  respondJson(res, 202, {
    ok: true,
    device: device.id,
    queued: friendlyName
  });
}
