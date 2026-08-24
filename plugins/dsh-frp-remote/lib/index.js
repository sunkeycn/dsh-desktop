import { execFile, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync } from "node:fs";
import { chmod, mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import net from "node:net";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export const name = "frp-remote";

const API_HOST = "127.0.0.1";
const API_PORT = 3081;
const KEYCHAIN_SERVICE = "com.deepseek.harness.frp";
const KEYCHAIN_ACCOUNT = "token";
const ALLOWED_ORIGINS = new Set([
  "http://127.0.0.1:3080",
  "http://localhost:3080",
]);

const frpRoot = join(homedir(), ".dsh", "frp");
const configPath = join(frpRoot, "config.json");
const tomlPath = join(frpRoot, "frpc-dsh.toml");

const defaults = {
  enabled: false,
  serverAddr: "",
  serverPort: 7000,
  tls: true,
  authMethod: "token",
  proxyName: "dsh-web",
  localAddr: "127.0.0.1:3080",
  remotePort: 8000,
  publicUrl: "",
};

let frpcChild = null;
let lastError = "";
let startedAt = null;
const csrfToken = randomBytes(24).toString("base64url");

function resolveFrpc() {
  const candidates = [
    join(homedir(), "Library", "Application Support", "DeepSeek Harness", "bin", "frpc"),
    join(homedir(), ".local", "bin", "frpc"),
    "/opt/homebrew/bin/frpc",
    "/usr/local/bin/frpc",
  ];
  return candidates.find((candidate) => existsSync(candidate)) ?? null;
}

function parseLegacyToml(source) {
  const stringValue = (key) => source.match(new RegExp(`^${key.replace(".", "\\.")}\\s*=\\s*["']([^"']*)["']`, "m"))?.[1];
  const numberValue = (key) => Number(source.match(new RegExp(`^${key.replace(".", "\\.")}\\s*=\\s*(\\d+)`, "m"))?.[1]);
  const token = stringValue("auth.token") || stringValue("token") || "";
  return {
    config: {
      ...defaults,
      enabled: true,
      serverAddr: stringValue("serverAddr") || "",
      serverPort: numberValue("serverPort") || defaults.serverPort,
      tls: !/^transport\.tls\.enable\s*=\s*false/m.test(source),
      proxyName: stringValue("name") || defaults.proxyName,
      remotePort: numberValue("remotePort") || defaults.remotePort,
    },
    token,
  };
}

async function loadConfig() {
  try {
    const parsed = JSON.parse(await readFile(configPath, "utf8"));
    return { ...defaults, ...parsed, localAddr: defaults.localAddr, authMethod: "token" };
  } catch {}

  try {
    const legacy = parseLegacyToml(await readFile(tomlPath, "utf8"));
    if (legacy.token && !legacy.token.includes("{{")) await saveToken(legacy.token);
    await persistConfig(legacy.config);
    return legacy.config;
  } catch {
    return { ...defaults };
  }
}

function validateConfig(input) {
  const config = { ...defaults, ...input, localAddr: defaults.localAddr, authMethod: "token" };
  config.enabled = Boolean(config.enabled);
  config.tls = Boolean(config.tls);
  config.serverAddr = String(config.serverAddr ?? "").trim();
  config.proxyName = String(config.proxyName ?? "").trim();
  config.publicUrl = String(config.publicUrl ?? "").trim();
  config.serverPort = Number(config.serverPort);
  config.remotePort = Number(config.remotePort);
  if (!config.serverAddr || config.serverAddr.length > 253 || /[\s/:]/.test(config.serverAddr)) {
    throw new Error("FRP Server 地址无效");
  }
  if (!Number.isInteger(config.serverPort) || config.serverPort < 1 || config.serverPort > 65535) {
    throw new Error("服务器端口必须在 1 到 65535 之间");
  }
  if (!config.proxyName || !/^[A-Za-z0-9_.-]{1,64}$/.test(config.proxyName)) {
    throw new Error("代理名称只能包含字母、数字、点、下划线和连字符");
  }
  if (!Number.isInteger(config.remotePort) || config.remotePort < 1 || config.remotePort > 65535) {
    throw new Error("远端端口必须在 1 到 65535 之间");
  }
  if (config.publicUrl) {
    let url;
    try { url = new URL(config.publicUrl); } catch { throw new Error("公网入口地址无效"); }
    if (url.protocol !== "https:" || !url.hostname) throw new Error("公网入口必须是 HTTPS 地址");
    config.publicUrl = url.toString().replace(/\/$/, "");
  }
  return config;
}

function tomlEscape(value) {
  return String(value).replaceAll("\\", "\\\\").replaceAll('"', '\\"');
}

function renderToml(config) {
  return `serverAddr = "${tomlEscape(config.serverAddr)}"
serverPort = ${config.serverPort}
auth.method = "token"
auth.token = "{{ .Envs.FRP_AUTH_TOKEN }}"
transport.tls.enable = ${config.tls}

[[proxies]]
name = "${tomlEscape(config.proxyName)}"
type = "tcp"
localIP = "127.0.0.1"
localPort = 3080
remotePort = ${config.remotePort}
`;
}

async function atomicWrite(path, contents, mode = 0o600) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporary = `${path}.tmp-${process.pid}`;
  await writeFile(temporary, contents, { mode });
  await rename(temporary, path);
  await chmod(path, mode);
}

async function persistConfig(config) {
  await atomicWrite(configPath, `${JSON.stringify(config, null, 2)}\n`);
  await atomicWrite(tomlPath, renderToml(config));
}

function execSecurity(arguments_) {
  return new Promise((resolve, reject) => {
    execFile("/usr/bin/security", arguments_, { encoding: "utf8" }, (error, stdout) => {
      if (error) reject(error);
      else resolve(String(stdout).trim());
    });
  });
}

async function loadToken() {
  try {
    return await execSecurity(["find-generic-password", "-w", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT]);
  } catch {
    return "";
  }
}

async function saveToken(token) {
  if (!token) return;
  await execSecurity(["add-generic-password", "-U", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-w", token]);
}

function stopFrpc() {
  if (!frpcChild) return;
  try { frpcChild.kill("SIGTERM"); } catch {}
  frpcChild = null;
  startedAt = null;
}

async function startFrpc(config) {
  stopFrpc();
  lastError = "";
  if (!config.enabled) return;
  const frpc = resolveFrpc();
  if (!frpc) {
    lastError = "frpc 二进制未找到";
    return;
  }
  const token = await loadToken();
  if (!token) {
    lastError = "尚未配置 Token";
    return;
  }
  frpcChild = spawn(frpc, ["-c", tomlPath], {
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, FRP_AUTH_TOKEN: token },
  });
  startedAt = new Date().toISOString();
  frpcChild.stdout.on("data", (data) => console.log(`[frp-remote] ${String(data).trimEnd()}`));
  frpcChild.stderr.on("data", (data) => {
    const line = String(data).trimEnd();
    if (line) lastError = line.slice(-500);
    console.log(`[frp-remote] ${line}`);
  });
  frpcChild.on("error", (error) => {
    lastError = error.message;
    frpcChild = null;
    startedAt = null;
  });
  frpcChild.on("exit", (code, signal) => {
    if (code && code !== 0) lastError = `frpc 已退出（code=${code}）`;
    console.log(`[frp-remote] frpc 已退出 code=${code} signal=${signal}`);
    frpcChild = null;
    startedAt = null;
  });
  console.log(`[frp-remote] 已启动 frpc pid=${frpcChild.pid}`);
}

function statusPayload(config, tokenConfigured) {
  return {
    config,
    tokenConfigured,
    csrfToken,
    status: {
      running: frpcChild !== null,
      pid: frpcChild?.pid ?? null,
      startedAt,
      lastError,
      frpcPath: resolveFrpc(),
    },
  };
}

function sendJson(response, status, payload, origin) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": origin,
    "Vary": "Origin",
  });
  response.end(JSON.stringify(payload));
}

async function readJson(request) {
  let body = "";
  for await (const chunk of request) {
    body += chunk;
    if (body.length > 65536) throw new Error("请求内容过大");
  }
  return body ? JSON.parse(body) : {};
}

function testServer(config) {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const socket = net.createConnection({ host: config.serverAddr, port: config.serverPort });
    socket.setTimeout(5000);
    socket.once("connect", () => {
      const latencyMs = Date.now() - started;
      socket.destroy();
      resolve(latencyMs);
    });
    socket.once("timeout", () => socket.destroy(new Error("连接超时")));
    socket.once("error", reject);
  });
}

async function handleRequest(request, response) {
  const origin = String(request.headers.origin ?? "");
  if (!ALLOWED_ORIGINS.has(origin)) {
    response.writeHead(403, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
    response.end(JSON.stringify({ error: "只允许从本机 DSH 页面管理 FRP" }));
    return;
  }
  if (request.method === "OPTIONS") {
    response.writeHead(204, {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Methods": "GET, POST",
      "Access-Control-Allow-Headers": "Content-Type, X-DSH-FRP-CSRF",
      "Access-Control-Max-Age": "600",
      "Vary": "Origin",
    });
    response.end();
    return;
  }
  try {
    const url = new URL(request.url ?? "/", `http://${API_HOST}:${API_PORT}`);
    if (request.method === "GET" && url.pathname === "/api/state") {
      const config = await loadConfig();
      sendJson(response, 200, statusPayload(config, Boolean(await loadToken())), origin);
      return;
    }
    if (request.method === "POST" && request.headers["x-dsh-frp-csrf"] !== csrfToken) {
      sendJson(response, 403, { error: "管理会话已失效，请刷新页面" }, origin);
      return;
    }
    if (request.method === "POST" && url.pathname === "/api/config") {
      const body = await readJson(request);
      const config = validateConfig(body.config);
      const token = String(body.token ?? "").trim();
      if (token) await saveToken(token);
      if (config.enabled && !(token || await loadToken())) throw new Error("启用隧道前必须填写 Token");
      await persistConfig(config);
      await startFrpc(config);
      sendJson(response, 200, statusPayload(config, Boolean(await loadToken())), origin);
      return;
    }
    if (request.method === "POST" && url.pathname === "/api/test") {
      const body = await readJson(request);
      const config = validateConfig(body.config);
      const latencyMs = await testServer(config);
      sendJson(response, 200, { ok: true, latencyMs }, origin);
      return;
    }
    sendJson(response, 404, { error: "Not found" }, origin);
  } catch (error) {
    sendJson(response, 400, { error: error instanceof Error ? error.message : String(error) }, origin);
  }
}

export async function apply(ctx) {
  const initialConfig = await loadConfig();
  await persistConfig(initialConfig);
  await startFrpc(initialConfig);

  const server = createServer((request, response) => {
    handleRequest(request, response).catch((error) => {
      response.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
      response.end(JSON.stringify({ error: error.message }));
    });
  });
  server.on("error", (error) => {
    lastError = `配置服务启动失败：${error.message}`;
    console.error(`[frp-remote] ${lastError}`);
  });
  server.listen(API_PORT, API_HOST, () => {
    console.log(`[frp-remote] 本机配置服务监听 http://${API_HOST}:${API_PORT}`);
  });

  ctx.effect(() => () => {
    stopFrpc();
    server.close();
  });
}

export const __test = { parseLegacyToml, renderToml, validateConfig };
