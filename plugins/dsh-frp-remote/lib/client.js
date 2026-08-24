window.__ModuleLoader__.load({
  id: "dsh-frp-remote",
  factory: (require) => {
    const module = { exports: {} };
    const exports = module.exports;
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
    const React = require("react");

    const inject = ["slots"];
    const API = "http://127.0.0.1:3081/api";

    const styles = {
      root: { maxWidth: 760, padding: "16px 20px 28px", color: "var(--color-text-primary, inherit)" },
      header: { display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16, flexWrap: "wrap", paddingBottom: 14, borderBottom: "1px solid var(--color-border-secondary, #d9dade)" },
      titleGroup: { display: "flex", alignItems: "center", gap: 10 },
      title: { margin: 0, fontSize: 16, fontWeight: 600 },
      status: { display: "inline-flex", alignItems: "center", gap: 6, color: "var(--color-text-secondary, #6b6e76)", fontSize: 13 },
      dot: (running) => ({ width: 8, height: 8, borderRadius: "50%", background: running ? "#2f8a4b" : "#a7aab2" }),
      section: { padding: "18px 0", borderBottom: "1px solid var(--color-border-secondary, #d9dade)" },
      heading: { margin: "0 0 12px", fontSize: 14, fontWeight: 600 },
      grid2: { display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: 12 },
      grid3: { display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(170px, 1fr))", gap: 12 },
      field: { display: "flex", flexDirection: "column", gap: 6, minWidth: 0, fontSize: 13 },
      input: { width: "100%", minHeight: 36, boxSizing: "border-box", padding: "7px 9px", border: "1px solid var(--color-border-primary, #bfc1c6)", borderRadius: 6, color: "inherit", background: "var(--color-background-primary, #fff)" },
      readonly: { color: "var(--color-text-secondary, #6b6e76)", background: "var(--color-background-secondary, #efeff1)" },
      check: { display: "inline-flex", alignItems: "center", gap: 8, marginTop: 12, fontSize: 13 },
      footer: { display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, flexWrap: "wrap", paddingTop: 18 },
      actions: { display: "flex", gap: 8, flexWrap: "wrap" },
      button: { minHeight: 34, padding: "6px 13px", borderRadius: 6, border: "1px solid var(--color-border-primary, #bfc1c6)", color: "inherit", background: "var(--color-background-primary, #fff)", cursor: "pointer" },
      primary: { color: "#fff", borderColor: "#385bc9", background: "#4669d6" },
      message: { minHeight: 20, marginTop: 12, color: "var(--color-text-secondary, #6b6e76)", fontSize: 13 },
      error: { color: "var(--color-text-warning, #b42318)" },
      warning: { marginTop: 10, color: "var(--color-text-warning, #8a4b12)", fontSize: 13 },
    };

    function RemoteAccessSettings() {
      const [config, setConfig] = React.useState(null);
      const [token, setToken] = React.useState("");
      const [tokenConfigured, setTokenConfigured] = React.useState(false);
      const [status, setStatus] = React.useState({ running: false, lastError: "" });
      const [csrfToken, setCsrfToken] = React.useState("");
      const [message, setMessage] = React.useState("正在读取配置…");
      const [error, setError] = React.useState("");
      const [busy, setBusy] = React.useState(false);
      const [localServiceAvailable, setLocalServiceAvailable] = React.useState(true);

      const request = React.useCallback(async (path, options = {}) => {
        const response = await fetch(`${API}${path}`, {
          ...options,
          headers: {
            "Content-Type": "application/json",
            ...(csrfToken ? { "X-DSH-FRP-CSRF": csrfToken } : {}),
            ...(options.headers || {}),
          },
        });
        const body = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(body.error || `请求失败（${response.status}）`);
        return body;
      }, [csrfToken]);

      const loadState = React.useCallback(async () => {
        try {
          const body = await fetch(`${API}/state`, { cache: "no-store" }).then(async (response) => {
            const data = await response.json().catch(() => ({}));
            if (!response.ok) throw new Error(data.error || "无法读取 FRP 配置");
            return data;
          });
          setConfig(body.config);
          setTokenConfigured(Boolean(body.tokenConfigured));
          setStatus(body.status || { running: false, lastError: "" });
          setCsrfToken(body.csrfToken || "");
          setMessage("");
          setError("");
          setLocalServiceAvailable(true);
        } catch (reason) {
          setLocalServiceAvailable(false);
          setMessage("");
          setError("FRP 配置仅能在运行 DeepSeek Harness 的 Mac 上修改。远程访问不会暴露鉴权信息。");
        }
      }, []);

      React.useEffect(() => {
        loadState();
        const timer = setInterval(() => {
          if (localServiceAvailable) loadState();
        }, 5000);
        return () => clearInterval(timer);
      }, [loadState, localServiceAvailable]);

      function update(name, value) {
        setConfig((current) => ({ ...current, [name]: value }));
      }

      async function save(event) {
        event.preventDefault();
        if (!config || busy) return;
        setBusy(true);
        setError("");
        setMessage("正在保存并重启隧道…");
        try {
          const body = await request("/config", {
            method: "POST",
            body: JSON.stringify({ config, token }),
          });
          setConfig(body.config);
          setToken("");
          setTokenConfigured(Boolean(body.tokenConfigured));
          setStatus(body.status || status);
          setMessage("配置已保存，隧道已按新配置启动。公网域名变化后请重新启动 Harness。 ");
        } catch (reason) {
          setError(reason.message || String(reason));
          setMessage("");
        } finally {
          setBusy(false);
        }
      }

      async function testConnection() {
        if (!config || busy) return;
        setBusy(true);
        setError("");
        setMessage("正在测试 FRP Server…");
        try {
          const body = await request("/test", { method: "POST", body: JSON.stringify({ config }) });
          setMessage(`服务器可达，TCP 连接耗时 ${body.latencyMs} ms。`);
        } catch (reason) {
          setError(reason.message || String(reason));
          setMessage("");
        } finally {
          setBusy(false);
        }
      }

      if (!config) {
        return React.createElement("div", { style: styles.root },
          React.createElement("h2", { style: styles.title }, "远程访问"),
          React.createElement("div", { style: { ...styles.message, ...(error ? styles.error : {}) } }, error || message),
        );
      }

      const connectedText = status.running ? "已连接" : (config.enabled ? "未连接" : "已停用");
      return React.createElement("form", { style: styles.root, onSubmit: save },
        React.createElement("header", { style: styles.header },
          React.createElement("div", { style: styles.titleGroup },
            React.createElement("h2", { style: styles.title }, "远程访问"),
            React.createElement("span", { style: styles.status },
              React.createElement("i", { style: styles.dot(status.running) }),
              connectedText,
            ),
          ),
          React.createElement("label", { style: styles.check },
            React.createElement("input", { type: "checkbox", checked: config.enabled, disabled: busy, onChange: (event) => update("enabled", event.target.checked) }),
            "启用隧道",
          ),
        ),

        React.createElement("section", { style: styles.section },
          React.createElement("h3", { style: styles.heading }, "FRP Server"),
          React.createElement("div", { style: styles.grid2 },
            React.createElement("label", { style: styles.field }, "服务器地址",
              React.createElement("input", { style: styles.input, value: config.serverAddr, disabled: busy, required: true, onChange: (event) => update("serverAddr", event.target.value) }),
            ),
            React.createElement("label", { style: styles.field }, "服务器端口",
              React.createElement("input", { style: styles.input, type: "number", min: 1, max: 65535, value: config.serverPort, disabled: busy, required: true, onChange: (event) => update("serverPort", event.target.value) }),
            ),
          ),
          React.createElement("label", { style: styles.check },
            React.createElement("input", { type: "checkbox", checked: config.tls, disabled: busy, onChange: (event) => update("tls", event.target.checked) }),
            "启用 TLS",
          ),
        ),

        React.createElement("section", { style: styles.section },
          React.createElement("h3", { style: styles.heading }, "鉴权"),
          React.createElement("div", { style: styles.grid2 },
            React.createElement("label", { style: styles.field }, "鉴权方式",
              React.createElement("select", { style: styles.input, value: "token", disabled: true }, React.createElement("option", null, "Token")),
            ),
            React.createElement("label", { style: styles.field }, "Token",
              React.createElement("input", { style: styles.input, type: "password", value: token, disabled: busy, required: config.enabled && !tokenConfigured, placeholder: tokenConfigured ? "已安全保存，留空表示不修改" : "请输入 Token", autoComplete: "new-password", onChange: (event) => setToken(event.target.value) }),
            ),
          ),
        ),

        React.createElement("section", { style: styles.section },
          React.createElement("h3", { style: styles.heading }, "代理"),
          React.createElement("div", { style: styles.grid3 },
            React.createElement("label", { style: styles.field }, "代理名称",
              React.createElement("input", { style: styles.input, value: config.proxyName, disabled: busy, required: true, onChange: (event) => update("proxyName", event.target.value) }),
            ),
            React.createElement("label", { style: styles.field }, "本地服务",
              React.createElement("input", { style: { ...styles.input, ...styles.readonly }, value: "127.0.0.1:3080", readOnly: true }),
            ),
            React.createElement("label", { style: styles.field }, "远端端口",
              React.createElement("input", { style: styles.input, type: "number", min: 1, max: 65535, value: config.remotePort, disabled: busy, required: true, onChange: (event) => update("remotePort", event.target.value) }),
            ),
          ),
        ),

        React.createElement("section", { style: { ...styles.section, borderBottom: 0 } },
          React.createElement("h3", { style: styles.heading }, "公网入口"),
          React.createElement("label", { style: styles.field }, "HTTPS 地址",
            React.createElement("input", { style: styles.input, type: "url", value: config.publicUrl, disabled: busy, placeholder: "https://dsh.example.com", onChange: (event) => update("publicUrl", event.target.value) }),
          ),
          React.createElement("div", { style: styles.warning }, "公网入口必须另外配置 HTTPS 和访问认证；FRP 本身只提供网络隧道。"),
        ),

        React.createElement("footer", { style: styles.footer },
          React.createElement("span", { style: styles.status }, status.running ? `frpc 正在运行 · PID ${status.pid}` : (status.lastError || "frpc 未运行")),
          React.createElement("div", { style: styles.actions },
            React.createElement("button", { type: "button", style: styles.button, disabled: busy, onClick: testConnection }, "测试连接"),
            React.createElement("button", { type: "submit", style: { ...styles.button, ...styles.primary }, disabled: busy }, "保存并重启隧道"),
          ),
        ),
        React.createElement("div", { style: { ...styles.message, ...(error ? styles.error : {}) } }, error || message),
      );
    }

    function apply(ctx) {
      ctx.slots.inject("settings.section", () => ctx.slots.register(
        { name: "settings.section", id: "frp-remote", order: 30, label: "远程访问" },
        () => React.createElement(RemoteAccessSettings),
      ));
    }

    exports.apply = apply;
    exports.inject = inject;
    return module.exports;
  },
});
