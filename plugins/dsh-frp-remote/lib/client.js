window.__ModuleLoader__.load({
	id: "dsh-frp-remote",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
		let React = require("react");

		const inject = ["slots"];

		const st = {
			container: { padding: "16px", maxWidth: "620px" },
			h2: { marginTop: 0, fontSize: "16px" },
			box: { background: "#f0f6ff", border: "1px solid #cfe2ff", borderRadius: "8px", padding: "12px", marginBottom: "16px", fontSize: "13px", lineHeight: "1.7" },
			code: { display: "block", background: "#1f2937", color: "#e5e7eb", padding: "8px 10px", borderRadius: "6px", fontFamily: "monospace", fontSize: "12px", whiteSpace: "pre-wrap", wordBreak: "break-all", margin: "8px 0" },
			strong: { fontWeight: "600" },
		};

		function apply(ctx) {
			ctx.slots.inject("settings.section", () => ctx.slots.register(
				{ name: "settings.section", id: "frp-remote", order: 30, label: "远程访问" },
				() => React.createElement("div", { style: st.container },
					React.createElement("h2", { style: st.h2 }, "远程访问（frp 内网穿透）"),
					React.createElement("div", { style: st.box },
						React.createElement("div", null, "✅ 隧道随 DSH 自动建立，无需手动操作；DSH 关闭时自动断开。"),
						React.createElement("div", { style: { marginTop: "6px" } }, "手机访问地址：", React.createElement("strong", { style: st.strong }, "https://dsh.sunkey.wang")),
						React.createElement("div", null, "用户名：", React.createElement("code", null, "dsh"), "（口令为部署时设置的，勿外泄）"),
					),
					React.createElement("div", { style: st.box },
						React.createElement("div", { style: st.strong }, "服务器配置变了怎么更新？"),
						React.createElement("div", { style: { marginTop: "6px" } }, "① 在服务器上重新生成配置串："),
						React.createElement("code", { style: st.code }, "ssh -i ~/.ssh/sub2api_ecs_ed25519 root@39.107.86.211 frp-conn"),
						React.createElement("div", null, "② 本地隧道配置在 ", React.createElement("code", null, "~/.dsh/frp/frpc-dsh.toml"), "，改完重启 DSH 生效。"),
					),
				),
			));
		}

		exports.apply = apply;
		exports.inject = inject;
		return module.exports;
	}
});
