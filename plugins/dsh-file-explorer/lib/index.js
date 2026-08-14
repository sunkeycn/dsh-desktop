import { URL } from "node:url";
import { homedir } from "node:os";

export const name = "file-explorer";

const HOME = homedir();

const MAX_TEXT_BYTES = 1024 * 1024;
const MAX_BINARY_BYTES = 10 * 1024 * 1024;

const IMAGE_MIME = {
  ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif",
  ".webp": "image/webp", ".svg": "image/svg+xml", ".ico": "image/x-icon", ".bmp": "image/bmp", ".avif": "image/avif",
};

function ext(path) {
  const i = path.lastIndexOf(".");
  return i < 0 ? "" : path.slice(i).toLowerCase();
}

function bytesToBase64(bytes) {
  return Buffer.from(bytes).toString("base64");
}

function send(res, data) {
  res.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
  res.end(JSON.stringify(data));
}

function queryPath(req) {
  const url = new URL(req.url, "http://localhost");
  return url.searchParams.get("path") || "";
}

function allowed(fs, target) {
  const p = fs.processPath(target);
  return p === HOME || p.startsWith(HOME + "/");
}

export function apply(ctx) {
  const fs = ctx.get("fs");
  const webServer = ctx.get("webServer");
  if (fs === undefined || webServer === undefined) return;

  async function listDir(req, res) {
    const path = queryPath(req);
    try {
      const target = await fs.resolve(path);
      if (!allowed(fs, target)) return send(res, { ok: false, path, error: "超出可访问范围（仅限主目录）" });
      const entries = await fs.listDir(target);
      const out = entries.map((e) => ({
        name: e.name,
        type: e.type,
        size: typeof e.size === "number" ? e.size : null,
        path: e.target && e.target.displayPath ? e.target.displayPath : path.replace(/\/+$/, "") + "/" + e.name,
      }));
      send(res, { ok: true, path, entries: out });
    } catch (err) {
      send(res, { ok: false, path, error: err && err.message ? String(err.message) : String(err) });
    }
  }

  async function readFile(req, res) {
    const path = queryPath(req);
    try {
      const target = await fs.resolve(path);
      if (!allowed(fs, target)) return send(res, { ok: false, error: "超出可访问范围（仅限主目录）" });
      const info = await fs.stat(target);
      if (info === undefined) return send(res, { ok: false, error: "文件不存在" });
      if (info.type === "directory") return send(res, { ok: false, error: "这是一个目录" });
      if (info.type !== "file") return send(res, { ok: false, error: "不是普通文件" });
      const size = typeof info.size === "number" ? info.size : null;

      const mime = IMAGE_MIME[ext(path)];
      if (mime !== undefined) {
        if (size !== null && size > MAX_BINARY_BYTES) return send(res, { ok: false, error: "图片过大" });
        try {
          const bytes = await fs.readBytes(target, undefined, MAX_BINARY_BYTES);
          return send(res, { ok: true, kind: "image", mime, base64: bytesToBase64(bytes), size });
        } catch (e) {
          return send(res, { ok: false, error: e && e.message ? String(e.message) : String(e) });
        }
      }

      if (size !== null && size > MAX_TEXT_BYTES) return send(res, { ok: true, kind: "large", size });
      try {
        const content = await fs.readText(target);
        return send(res, { ok: true, kind: "text", content, size });
      } catch (err) {
        const code = err && err.code ? String(err.code) : "";
        if (size !== null && size > MAX_BINARY_BYTES) return send(res, { ok: true, kind: "binary", size });
        if (code === "FS_NOT_TEXT" || code === "FS_TOO_LARGE") {
          try {
            const bytes = await fs.readBytes(target, undefined, MAX_BINARY_BYTES);
            return send(res, { ok: true, kind: "binary", size: bytes.length });
          } catch (e2) {
            return send(res, { ok: false, error: e2 && e2.message ? String(e2.message) : String(e2) });
          }
        }
        throw err;
      }
    } catch (err) {
      send(res, { ok: false, error: err && err.message ? String(err.message) : String(err) });
    }
  }

  async function statPath(req, res) {
    const path = queryPath(req);
    try {
      const target = await fs.resolve(path);
      if (!allowed(fs, target)) return send(res, { ok: true, exists: false, type: null, size: null });
      const info = await fs.stat(target);
      send(res, {
        ok: true,
        exists: info !== undefined,
        type: info ? info.type : null,
        size: info && typeof info.size === "number" ? info.size : null,
      });
    } catch (err) {
      send(res, { ok: true, exists: false, type: null, size: null });
    }
  }

  ctx.effect(() => {
    const d1 = webServer.register({ kind: "exact", path: "/file-explorer/listDir", handler: listDir });
    const d2 = webServer.register({ kind: "exact", path: "/file-explorer/readFile", handler: readFile });
    const d3 = webServer.register({ kind: "exact", path: "/file-explorer/statPath", handler: statPath });
    return () => { d1(); d2(); d3(); };
  });
}
