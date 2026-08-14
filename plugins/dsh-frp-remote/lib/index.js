import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";

export const name = "frp-remote";

function resolveFrpc() {
  const candidates = [
    `${homedir()}/.local/bin/frpc`,
    "/opt/homebrew/bin/frpc",
    "/usr/local/bin/frpc",
  ];
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

/**
 * 随 DSH 启动的内网穿透：拉起 frpc 建立远程访问隧道，DSH 停止时关闭。
 * frpc 只转发本机 127.0.0.1:3080 到公网服务器（配置见 ~/.dsh/frp/frpc-dsh.toml）。
 */
export function apply(ctx) {
  const frpc = resolveFrpc();
  if (frpc === null) {
    console.warn("[frp-remote] frpc 二进制未找到，跳过自动建隧道");
    return;
  }
  const configPath = `${homedir()}/.dsh/frp/frpc-dsh.toml`;
  if (!existsSync(configPath)) {
    console.warn(`[frp-remote] 配置文件缺失：${configPath}，跳过`);
    return;
  }
  const child = spawn(frpc, ["-c", configPath], { stdio: ["ignore", "pipe", "pipe"] });
  child.stdout.on("data", (d) => console.log(`[frp-remote] ${String(d).trimEnd()}`));
  child.stderr.on("data", (d) => console.log(`[frp-remote] ${String(d).trimEnd()}`));
  child.on("error", (e) => console.error(`[frp-remote] 启动失败：${e.message}`));
  child.on("exit", (code, signal) => console.log(`[frp-remote] frpc 已退出 code=${code} signal=${signal}`));
  console.log(`[frp-remote] 已启动 frpc pid=${child.pid}`);
  ctx.effect(() => () => {
    console.log("[frp-remote] 停止 frpc");
    try {
      child.kill("SIGTERM");
    } catch {}
  });
}
