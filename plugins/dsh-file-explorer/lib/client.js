window.__ModuleLoader__.load({
  id: "dsh-file-explorer",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
    const React = require("react");

    const CSS =
      ".dshfx-scroll{overflow:auto}" +
      ".dshfx-scroll::-webkit-scrollbar{width:9px;height:9px}" +
      ".dshfx-scroll::-webkit-scrollbar-thumb{background:var(--dsw-alias-border-l2,#333);border-radius:5px}" +
      ".dshfx-node{display:flex;align-items:center;gap:6px;padding:3px 6px;border-radius:6px;cursor:pointer;white-space:nowrap;overflow:hidden;user-select:none;line-height:20px}" +
      ".dshfx-node:hover{background:var(--dsw-alias-bg-layer-2,#26272c)}" +
      ".dshfx-btn{display:inline-flex;align-items:center;justify-content:center;cursor:pointer;border:1px solid transparent;border-radius:6px;background:transparent;color:var(--dsw-alias-label-secondary,#b8b8b8);padding:4px 8px;font:inherit;font-size:12px}" +
      ".dshfx-btn:hover{background:var(--dsw-alias-bg-layer-2,#26272c);color:var(--dsw-alias-label-primary,#e6e6e6)}" +
      ".dshfx-iconbtn{cursor:pointer;width:28px;height:28px;color:var(--dsw-alias-label-secondary);background:transparent;border:none;border-radius:50%;flex:none;justify-content:center;align-items:center;padding:0;display:inline-flex}" +
      ".dshfx-iconbtn:hover{background:var(--dsw-alias-interactive-bg-hover);color:var(--dsw-alias-label-primary)}" +
      ".dshfx-tabs{display:flex;align-items:stretch;gap:2px;overflow-x:auto;flex:none;border-bottom:1px solid var(--dsw-alias-border-l1,#2a2b2f)}" +
      ".dshfx-tabs::-webkit-scrollbar{height:4px}" +
      ".dshfx-tab{display:inline-flex;align-items:center;gap:6px;max-width:180px;padding:7px 10px;border:none;border-bottom:2px solid transparent;background:transparent;color:var(--dsw-alias-label-secondary,#b8b8b8);font:inherit;font-size:12px;cursor:pointer;white-space:nowrap}" +
      ".dshfx-tab:hover{background:var(--dsw-alias-bg-layer-2,#26272c);color:var(--dsw-alias-label-primary,#e6e6e6)}" +
      ".dshfx-tab[data-active=true]{color:var(--dsw-alias-label-primary,#fff);border-bottom-color:var(--dsw-alias-brand-primary,#5b8def)}" +
      ".dshfx-tab-x{margin-left:2px;opacity:.6;border-radius:4px;padding:0 3px}" +
      ".dshfx-tab-x:hover{opacity:1;background:var(--dsw-alias-bg-layer-2,#333)}" +
      ".dshfx-pre{margin:0;padding:10px 12px;font:12px/1.6 var(--ds-font-family-code,ui-monospace,SFMono-Regular,Menlo,monospace);color:var(--dsw-alias-label-primary,#e6e6e6);white-space:pre;overflow-x:auto;overflow-y:hidden;min-width:100%;box-sizing:border-box}" +
      ".dshfx-pre code{font:inherit;color:inherit}";

    function fmtSize(n) {
      if (n == null) return "";
      if (n < 1024) return n + " B";
      if (n < 1048576) return (n / 1024).toFixed(1) + " KB";
      return (n / 1048576).toFixed(1) + " MB";
    }
    function sortEntries(entries) {
      const arr = Array.isArray(entries) ? entries.slice() : [];
      const dirs = arr.filter((e) => e.type === "directory");
      const files = arr.filter((e) => e.type !== "directory");
      const cmp = (a, b) => String(a.name).localeCompare(String(b.name), undefined, { numeric: true, sensitivity: "base" });
      dirs.sort(cmp); files.sort(cmp);
      return dirs.concat(files);
    }
    function parentOf(path) {
      const s = String(path).replace(/\/+$/, "");
      if (s === "" || s === "/") return null;
      const i = s.lastIndexOf("/");
      if (i <= 0) return "/";
      return s.slice(0, i);
    }
    function basename(path) {
      const s = String(path).replace(/\/+$/, "");
      const i = s.lastIndexOf("/");
      return i < 0 ? s : s.slice(i + 1);
    }
    function api(method, params) {
      const qs = Object.keys(params || {}).map((k) => encodeURIComponent(k) + "=" + encodeURIComponent(String(params[k]))).join("&");
      return fetch("/file-explorer/" + method + (qs ? "?" + qs : "")).then((r) => r.json());
    }

    const KW = {
      js: "const let var function return if else for while do switch case break continue new this class extends super import export from default async await try catch finally throw typeof instanceof in of delete void yield static get set null undefined true false".split(" "),
      ts: "const let var function return if else for while do switch case break continue new this class extends super import export from default async await try catch finally throw typeof instanceof in of delete void yield static get set null undefined true false type interface enum implements namespace declare readonly abstract as satisfies keyof infer is never unknown any string number boolean object symbol bigint".split(" "),
      py: "def return if elif else for while class import from as try except finally raise with lambda global nonlocal pass break continue yield async await del assert not and or in is None True False self".split(" "),
      java: "public private protected class interface enum extends implements package import static final void int long double float boolean char byte short new return if else for while do switch case break continue throw try catch finally this super null true false abstract synchronized volatile transient instanceof".split(" "),
      go: "package import func var const type struct interface map chan go defer return if else for range switch case break continue fallthrough select default nil true false".split(" "),
      rust: "fn let mut const struct enum impl trait use mod pub crate super self return if else match for while loop in break continue async await move ref dyn box Some None Ok Err true false".split(" "),
      ruby: "def end class module if elsif else unless while until for do return yield begin rescue ensure raise require self nil true false".split(" "),
      c: "int char float double void long short unsigned signed struct union enum typedef static extern const volatile register return if else for while do switch case break continue sizeof goto".split(" "),
      cpp: "int char float double void long short unsigned signed struct union enum typedef static extern const volatile register return if else for while do switch case break continue sizeof goto class public private protected namespace template typename using new delete this virtual override friend inline operator try catch throw bool auto nullptr true false".split(" "),
      cs: "using namespace class interface struct enum public private protected internal static readonly const void int long double float bool char string var new return if else for foreach while do switch case break continue throw try catch finally this base null true false async await".split(" "),
      kotlin: "fun val var class interface object package import return if else for while when in is as try catch finally throw this super null true false data sealed enum companion override suspend".split(" "),
      swift: "func let var class struct enum protocol extension import return if else for while switch case break continue guard defer try catch throw self super nil true false init deinit override mutating".split(" "),
      sh: "if then else elif fi for while do done case esac in function echo return exit export local source set unset shift read".split(" "),
      sql: "select from where insert into values update set delete create table drop alter index view as and or not null join left right inner outer on group by order having limit distinct union all case when then else end count sum avg min max".split(" "),
    };
    const LANG_CFG = {
      js: { block: true, line: "//", kw: KW.js }, jsx: { block: true, line: "//", kw: KW.js },
      ts: { block: true, line: "//", kw: KW.ts }, tsx: { block: true, line: "//", kw: KW.ts },
      py: { block: false, line: "#", kw: KW.py }, java: { block: true, line: "//", kw: KW.java },
      go: { block: true, line: "//", kw: KW.go }, rust: { block: true, line: "//", kw: KW.rust },
      ruby: { block: false, line: "#", kw: KW.ruby }, c: { block: true, line: "//", kw: KW.c },
      cpp: { block: true, line: "//", kw: KW.cpp }, cs: { block: true, line: "//", kw: KW.cs },
      kotlin: { block: true, line: "//", kw: KW.kotlin }, swift: { block: true, line: "//", kw: KW.swift },
      sh: { block: false, line: "#", kw: KW.sh }, sql: { block: true, line: "--", kw: KW.sql },
      json: { block: false, line: null, kw: [] }, yaml: { block: false, line: "#", kw: [] },
      toml: { block: false, line: "#", kw: [] }, css: { block: true, line: null, kw: [] },
      html: { block: true, line: null, kw: [] }, xml: { block: true, line: null, kw: [] },
      md: { block: true, line: null, kw: [] }, txt: { block: false, line: null, kw: [] },
    };
    function langFor(path) {
      const s = String(path).toLowerCase();
      const i = s.lastIndexOf(".");
      if (i < 0) return "txt";
      const ext = s.slice(i + 1);
      const map = {
        js: "js", jsx: "jsx", mjs: "js", cjs: "js", ts: "ts", tsx: "tsx", mts: "ts", cts: "ts",
        py: "py", pyw: "py", java: "java", go: "go", rs: "rust", rb: "ruby",
        c: "c", h: "c", cpp: "cpp", cc: "cpp", cxx: "cpp", hpp: "cpp", hxx: "cpp", cs: "cs",
        kt: "kotlin", kts: "kotlin", swift: "swift", json: "json", yaml: "yaml", yml: "yaml", toml: "toml",
        html: "html", htm: "html", xml: "xml", vue: "html", svelte: "html", css: "css", scss: "css", less: "css",
        md: "md", markdown: "md", sh: "sh", bash: "sh", zsh: "sh", fish: "sh", sql: "sql",
      };
      return map[ext] || "txt";
    }
    const DARK_TOKENS = {
      comment: { color: "#6a9955", fontStyle: "italic" }, string: { color: "#ce9178" },
      number: { color: "#b5cea8" }, keyword: { color: "#569cd6" }, function: { color: "#dcdcaa" },
      type: { color: "#4ec9b0" }, constant: { color: "#4fc1ff" },
    };
    const LIGHT_TOKENS = {
      comment: { color: "#008000", fontStyle: "italic" }, string: { color: "#a31515" },
      number: { color: "#098658" }, keyword: { color: "#0000ff" }, function: { color: "#795e26" },
      type: { color: "#267f99" }, constant: { color: "#0070c1" },
    };
    function buildRegex(lang) {
      const cfg = LANG_CFG[lang] || LANG_CFG.txt;
      const parts = [];
      if (cfg.block) parts.push("(?<cmtb>\\/\\*[\\s\\S]*?\\*\\/|<!--[\\s\\S]*?-->)");
      if (cfg.line === "#") parts.push("(?<cmtl>#[^\\n]*)");
      else if (cfg.line === "//") parts.push("(?<cmtl>\\/\\/[^\\n]*)");
      else if (cfg.line === "--") parts.push("(?<cmtl>--[^\\n]*)");
      parts.push("(?<str>`(?:\\\\.|[^`\\\\])*`|\"(?:\\\\.|[^\"\\\\\\n])*\"|\\'(?:\\\\.|[^\\'\\\\\\n])*\\')");
      parts.push("(?<num>\\b(?:0[xXbBoO][0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b)");
      if (cfg.kw && cfg.kw.length) parts.push("(?<kw>\\b(?:" + cfg.kw.join("|") + ")\\b)");
      parts.push("(?<fn>[A-Za-z_$][\\w$]*)(?=\\s*\\()");
      parts.push("(?<type>\\b[A-Z][\\w$]*\\b)");
      parts.push("(?<const>\\b[A-Z_][A-Z0-9_]{2,}\\b)");
      parts.push("(?<id>[A-Za-z_$][\\w$]*)");
      return new RegExp(parts.join("|"), "g");
    }
    function tokenize(code, lang) {
      const re = buildRegex(lang);
      const tokens = [];
      let last = 0;
      let m;
      while ((m = re.exec(code)) !== null) {
        if (m.index > last) tokens.push({ type: "plain", text: code.slice(last, m.index) });
        const g = m.groups || {};
        let type = "plain";
        if (g.cmtb || g.cmtl) type = "comment";
        else if (g.str) type = "string";
        else if (g.num) type = "number";
        else if (g.kw) type = "keyword";
        else if (g.fn) type = "function";
        else if (g.type) type = "type";
        else if (g.const) type = "constant";
        else if (g.id) type = "identifier";
        tokens.push({ type, text: m[0] });
        last = m.index + m[0].length;
        if (m[0].length === 0) re.lastIndex++;
      }
      if (last < code.length) tokens.push({ type: "plain", text: code.slice(last) });
      return tokens;
    }
    function renderCode(code, lang, scheme) {
      if (code.length > 200000) return code;
      const STYLE = scheme === "light" ? LIGHT_TOKENS : DARK_TOKENS;
      const tokens = tokenize(code, lang);
      const children = [];
      let buf = "";
      function flush() { if (buf) { children.push(buf); buf = ""; } }
      tokens.forEach((t) => {
        const st = STYLE[t.type];
        if (st && st.color) { flush(); children.push(React.createElement("span", { key: children.length, style: st }, t.text)); }
        else buf += t.text;
      });
      flush();
      return children;
    }

    function ScrollArea(props) {
      const elState = React.useState(null);
      const el = elState[0];
      React.useEffect(() => {
        if (el === null) return undefined;
        function onWheel(e) {
          if (!e || e.deltaY === 0) return;
          const canUp = el.scrollTop > 0;
          const canDown = el.scrollTop + el.clientHeight < el.scrollHeight - 1;
          if ((e.deltaY < 0 && canUp) || (e.deltaY > 0 && canDown)) {
            if (e.preventDefault) e.preventDefault();
            el.scrollTop += e.deltaY;
          }
        }
        el.addEventListener("wheel", onWheel, { passive: false });
        return () => { el.removeEventListener("wheel", onWheel); };
      }, [el]);
      return React.createElement("div", { ref: elState[1], className: props.className, style: props.style }, props.children);
    }

    const TREE = "tree";

    function apply(ctx) {
      const slots = ctx.slots;
      const workspaces = ctx.get("workspaces");
      const layout = ctx.layout;

      ctx.effect(() => {
        if (typeof document === "undefined") return undefined;
        const tag = document.createElement("style");
        tag.setAttribute("data-plugin-css", "dsh-file-explorer");
        tag.textContent = CSS;
        document.head.appendChild(tag);
        return () => { tag.remove(); };
      });

      const listeners = new Set();
      const state = { open: false, previewPath: null };
      function notify() { listeners.forEach((l) => { try { l(); } catch (e) {} }); }
      function openColumn() { if (layout && typeof layout.openDetails === "function") layout.openDetails(); }
      function closeColumn() { if (layout && typeof layout.closeDetails === "function") layout.closeDetails(); }

      const store = {
        toggle() { if (state.open) { state.open = false; closeColumn(); } else { state.open = true; openColumn(); } notify(); },
        preview(path) { state.open = true; state.previewPath = path; openColumn(); notify(); },
        subscribe(l) { listeners.add(l); return () => { listeners.delete(l); }; },
      };
      function useStore() {
        const version = React.useState(0);
        React.useEffect(() => store.subscribe(() => version[1]((v) => v + 1)), []);
        return state;
      }

      function useColorScheme() {
        const theme = ctx.get("theme");
        const schemeState = React.useState(() => {
          if (theme && theme.getTheme) { try { return theme.getTheme().active.colorScheme; } catch (e) {} }
          return "dark";
        });
        React.useEffect(() => {
          if (!theme) return undefined;
          return ctx.on("theme/change", (snap) => { if (snap && snap.active) schemeState[1](snap.active.colorScheme); });
        }, []);
        return schemeState[0];
      }

      if (workspaces !== undefined && typeof workspaces.openPath === "function") {
        ctx.effect(() => {
          const original = workspaces.openPath.bind(workspaces);
          workspaces.openPath = function (path) {
            const p = String(path == null ? "" : path);
            api("statPath", { path: p }).then((r) => {
              if (r && r.ok === true && r.exists === true && r.type === "file") {
                store.preview(p);
              } else {
                original(p).catch(() => {});
              }
            }).catch(() => { original(p).catch(() => {}); });
            return Promise.resolve();
          };
          return () => { workspaces.openPath = original; };
        });
      }

      function Panel(props) {
        const useWorkspaces = props.useWorkspaces;
        const snap = useStore();
        const scheme = useColorScheme();
        const ws = typeof useWorkspaces === "function" ? useWorkspaces((s) => s) : null;

        const rootState = React.useState(null);
        const root = rootState[0];
        const setRoot = rootState[1];
        const cacheState = React.useState({});
        const cache = cacheState[0];
        const setCache = cacheState[1];
        const tabsState = React.useState([]);
        const tabs = tabsState[0];
        const setTabs = tabsState[1];
        const activeState = React.useState(TREE);
        const active = activeState[0];
        const setActive = activeState[1];
        const pcState = React.useState({});
        const pcache = pcState[0];
        const setPcache = pcState[1];
        const lastState = React.useState(null);
        const lastOpenPath = lastState[0];
        const setLastOpenPath = lastState[1];

        function loadDir(path) {
          setCache((c) => {
            const node = c[path];
            if (node && (node.loading || node.entries !== undefined)) return c;
            return Object.assign({}, c, { [path]: Object.assign({}, node, { loading: true }) });
          });
          api("listDir", { path }).then((r) => {
            const entries = (r && r.ok === true && Array.isArray(r.entries)) ? r.entries : [];
            setCache((c) => {
              const node = c[path];
              return Object.assign({}, c, { [path]: Object.assign({}, node, { loading: false, entries }) });
            });
          }).catch(() => {
            setCache((c) => {
              const node = c[path];
              return Object.assign({}, c, { [path]: Object.assign({}, node, { loading: false, entries: [], error: true }) });
            });
          });
        }

        function toggleDir(path) {
          const node = cache[path];
          const expanded = node ? node.expanded === true : false;
          setCache((c) => {
            const n = c[path];
            return Object.assign({}, c, { [path]: Object.assign({}, n, { expanded: !expanded }) });
          });
          if (!expanded && (!node || node.entries === undefined)) loadDir(path);
        }

        function loadFile(path) {
          setPcache((c) => {
            if (c[path] && (c[path].loading || c[path].data !== undefined)) return c;
            return Object.assign({}, c, { [path]: { loading: true } });
          });
          api("readFile", { path }).then((r) => {
            setPcache((c) => Object.assign({}, c, { [path]: { loading: false, data: r } }));
          }).catch(() => {
            setPcache((c) => Object.assign({}, c, { [path]: { loading: false, data: { ok: false, error: "读取失败" } } }));
          });
        }

        function openFile(path) {
          setTabs((arr) => (arr.indexOf(path) >= 0 ? arr : arr.concat([path])));
          setActive(path);
          if (!pcache[path]) loadFile(path);
        }

        function closeTab(path) {
          const next = tabs.filter((p) => p !== path);
          setTabs(next);
          if (active === path) setActive(next.length ? next[next.length - 1] : TREE);
        }

        function goUp() {
          const parent = parentOf(root);
          if (parent !== null) setRoot(parent);
        }
        function reload() { setCache({}); loadDir(root); }

        React.useEffect(() => {
          if (root !== null) return;
          if (ws) {
            const items = ws.items || [];
            const recent = items.find((w) => w.workspaceId === ws.recentWorkspaceId);
            if (recent && recent.path) { setRoot(recent.path); return; }
            if (items.length && items[0].path) { setRoot(items[0].path); return; }
          }
          if (workspaces !== undefined && typeof workspaces.listDirectory === "function") {
            workspaces.listDirectory().then((listing) => { if (listing && listing.home) setRoot(listing.home); }).catch(() => {});
          }
        }, [ws]);

        React.useEffect(() => {
          if (root === null) return;
          setCache({});
          loadDir(root);
        }, [root]);

        React.useEffect(() => {
          const p = snap.previewPath;
          if (p === null || p === lastOpenPath) return;
          setLastOpenPath(p);
          openFile(p);
          const parent = parentOf(p);
          if (parent !== null && root !== parent) setRoot(parent);
        }, [snap.previewPath]);

        function renderChildren(path, depth) {
          const node = cache[path];
          if (node === undefined) return null;
          if (node.loading === true && node.entries === undefined) {
            return React.createElement("div", { style: { padding: "4px 8px", color: "var(--dsw-alias-label-secondary,#999)", fontSize: 12 } }, "加载中…");
          }
          if (node.error) {
            return React.createElement("div", { style: { padding: "4px 8px", color: "var(--dsw-alias-state-error-primary,#e06c6c)", fontSize: 12 } }, "无法读取目录");
          }
          const entries = sortEntries(node.entries || []);
          if (entries.length === 0) {
            return React.createElement("div", { style: { padding: "4px 8px", color: "var(--dsw-alias-label-secondary,#999)", fontSize: 12 } }, "(空)");
          }
          return entries.map((entry) => {
            const childPath = entry.path;
            const isDir = entry.type === "directory";
            const childNode = cache[childPath];
            const expanded = childNode ? childNode.expanded === true : false;
            const row = React.createElement(
              "div",
              {
                key: childPath,
                className: "dshfx-node",
                style: { paddingLeft: 8 + depth * 14, color: "var(--dsw-alias-label-secondary,#bbb)" },
                onClick: () => { if (isDir) toggleDir(childPath); else openFile(childPath); },
                title: childPath,
              },
              React.createElement("span", { style: { width: 12, flex: "none", color: "var(--dsw-alias-label-secondary,#888)" } }, isDir ? (expanded ? "▾" : "▸") : ""),
              React.createElement("span", { style: { flex: "none", fontSize: 12 } }, isDir ? "📁" : "📄"),
              React.createElement("span", { style: { flex: "1 1 auto", overflow: "hidden", textOverflow: "ellipsis" } }, entry.name),
              entry.type !== "directory" && entry.size != null ? React.createElement("span", { style: { flex: "none", fontSize: 10, color: "var(--dsw-alias-label-secondary,#777)" } }, fmtSize(entry.size)) : null
            );
            if (!isDir || !expanded) return row;
            return React.createElement("div", { key: childPath }, row, renderChildren(childPath, depth + 1));
          });
        }

        function renderPreview(path) {
          const p = pcache[path];
          if (p === undefined) return null;
          if (p.loading) {
            return React.createElement("div", { style: { padding: 12, color: "var(--dsw-alias-label-secondary,#999)", fontSize: 12 } }, "加载中…");
          }
          const d = p.data;
          if (!d || d.ok !== true) {
            return React.createElement("div", { style: { padding: 12, color: "var(--dsw-alias-state-error-primary,#e06c6c)", fontSize: 12 } }, d && d.error ? d.error : "无法读取");
          }
          if (d.kind === "text") {
            return React.createElement("pre", { className: "dshfx-pre" },
              React.createElement("code", null, renderCode(d.content, langFor(path), scheme))
            );
          }
          if (d.kind === "image") {
            return React.createElement("img", { src: "data:" + d.mime + ";base64," + d.base64, alt: "", style: { maxWidth: "100%", display: "block", margin: "0 auto", padding: 8 } });
          }
          if (d.kind === "large") {
            return React.createElement("div", { style: { padding: 12, color: "var(--dsw-alias-label-secondary,#999)", fontSize: 12 } }, "文件较大（" + fmtSize(d.size) + "），暂不在线预览。");
          }
          if (d.kind === "binary") {
            return React.createElement("div", { style: { padding: 12, color: "var(--dsw-alias-label-secondary,#999)", fontSize: 12 } }, "二进制文件（" + fmtSize(d.size) + "），暂不支持预览。");
          }
          return null;
        }

        function tabEl(path, key) {
          const isTree = key === TREE;
          const name = isTree ? "文件" : basename(path);
          const isActive = active === key;
          const title = isTree ? "文件树" : path;
          return React.createElement("button", {
            key,
            type: "button",
            className: "dshfx-tab",
            "data-active": isActive,
            title,
            onClick: () => { setActive(key); },
          },
            React.createElement("span", { style: { overflow: "hidden", textOverflow: "ellipsis" } }, (isTree ? "📁 " : "") + name),
            !isTree ? React.createElement("span", { className: "dshfx-tab-x", onClick: (e) => { e.stopPropagation(); closeTab(path); } }, "✕") : null
          );
        }

        let body;
        if (active === TREE) {
          body = React.createElement("div", { style: { flex: "1 1 auto", minHeight: 0, display: "flex", flexDirection: "column" } },
            React.createElement("div", { style: { display: "flex", alignItems: "center", gap: 4, padding: "4px 6px", borderBottom: "1px solid var(--dsw-alias-border-l1,#2a2b2f)" } },
              React.createElement("button", { type: "button", className: "dshfx-btn", title: "上级目录", onClick: goUp }, "↑"),
              React.createElement("button", { type: "button", className: "dshfx-btn", title: "刷新", onClick: reload }, "↻"),
              React.createElement("span", { style: { flex: "1 1 auto", fontSize: 12, color: "var(--dsw-alias-label-secondary,#999)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } }, root || "…")
            ),
            React.createElement(ScrollArea, { className: "dshfx-scroll", style: { flex: "1 1 auto", minHeight: 0, padding: "4px 0" } },
              root === null
                ? React.createElement("div", { style: { padding: 8, color: "var(--dsw-alias-label-secondary,#999)", fontSize: 12 } }, "正在定位工作目录…")
                : renderChildren(root, 0)
            )
          );
        } else {
          body = React.createElement(ScrollArea, { className: "dshfx-scroll", style: { flex: "1 1 auto", minHeight: 0 } }, renderPreview(active));
        }

        return React.createElement("div", { style: { height: "100%", display: "flex", flexDirection: "column", background: "var(--dsw-alias-bg-base,#17181b)", color: "var(--dsw-alias-label-primary,#e6e6e6)" } },
          React.createElement("div", { className: "dshfx-tabs" },
            tabEl(null, TREE),
            tabs.map((p) => tabEl(p, p))
          ),
          body
        );
      }

      function ToggleButton() {
        const snap = useStore();
        const label = snap.open ? "关闭" : "文件浏览";
        return React.createElement("button", {
          type: "button",
          className: "dshfx-iconbtn",
          title: label,
          "aria-label": label,
          onClick: store.toggle,
        },
          React.createElement("svg", { width: 16, height: 16, viewBox: "0 0 16 16", fill: "none", xmlns: "http://www.w3.org/2000/svg" },
            React.createElement("rect", { x: 1.5, y: 2.5, width: 13, height: 11, rx: 2, stroke: "currentColor", strokeWidth: 1.3 }),
            React.createElement("path", { d: "M10.5 2.5v11", stroke: "currentColor", strokeWidth: 1.3 })
          )
        );
      }

      slots.inject("details", () => slots.register({ name: "details", priority: -1 }, Panel));
      slots.inject("conversation.session.header.utilities", () => slots.register(
        { name: "conversation.session.header.utilities", id: "file-explorer-toggle", order: 1000, label: () => "文件" },
        ToggleButton
      ));
    }

    exports.apply = apply;
    exports.inject = ["slots", "layout"];
    return module.exports;
  }
});
