import assert from "node:assert/strict";
import test from "node:test";
import { __test } from "../plugins/dsh-frp-remote/lib/index.js";

const validConfig = {
  enabled: true,
  serverAddr: "frps.example.com",
  serverPort: 7000,
  tls: true,
  authMethod: "token",
  proxyName: "dsh-web",
  localAddr: "malicious.example:9000",
  remotePort: 13080,
  publicUrl: "https://dsh.example.com/",
};

test("validates and normalizes editable FRP fields", () => {
  const config = __test.validateConfig(validConfig);
  assert.equal(config.localAddr, "127.0.0.1:3080");
  assert.equal(config.authMethod, "token");
  assert.equal(config.publicUrl, "https://dsh.example.com");
});

test("rejects an insecure public URL", () => {
  assert.throws(
    () => __test.validateConfig({ ...validConfig, publicUrl: "http://dsh.example.com" }),
    /HTTPS/,
  );
});

test("renders an environment template without a plaintext token", () => {
  const toml = __test.renderToml(__test.validateConfig(validConfig));
  assert.match(toml, /auth\.token = "\{\{ \.Envs\.FRP_AUTH_TOKEN \}\}"/);
  assert.doesNotMatch(toml, /saved-secret|malicious\.example/);
  assert.match(toml, /localIP = "127\.0\.0\.1"/);
  assert.match(toml, /localPort = 3080/);
});

test("imports legacy TOML and separates the token", () => {
  const legacy = __test.parseLegacyToml(`
serverAddr = "frps.example.com"
serverPort = 7000
auth.method = "token"
auth.token = "legacy-secret"

[[proxies]]
name = "dsh-web"
localIP = "127.0.0.1"
localPort = 3080
remotePort = 8000
`);
  assert.equal(legacy.config.serverAddr, "frps.example.com");
  assert.equal(legacy.config.remotePort, 8000);
  assert.equal(legacy.token, "legacy-secret");
});
