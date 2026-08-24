const fs = require("node:fs");
const path = require("node:path");

const [, , runtimeRoot, profileRoot] = process.argv;
if (!runtimeRoot || !profileRoot) process.exit(0);

const YAML = require(path.join(runtimeRoot, "node_modules/yaml"));
const patchPath = path.join(profileRoot, "cordis.patch.yml");
if (fs.existsSync(patchPath)) {
  const source = fs.readFileSync(patchPath, "utf8");
  const document = YAML.parseDocument(source);
  let changed = false;
  if (YAML.isSeq(document.contents)) {
    for (let index = document.contents.items.length - 1; index >= 0; index -= 1) {
      const entry = document.contents.items[index];
      if (!YAML.isMap(entry)) continue;
      const inserts = entry.get("insert", true);
      if (!YAML.isSeq(inserts)) continue;
      const before = inserts.items.length;
      inserts.items = inserts.items.filter((item) => {
        if (!YAML.isMap(item)) return true;
        return String(item.get("name") ?? "") !== "dsh-frp-remote";
      });
      if (inserts.items.length !== before) changed = true;
      if (inserts.items.length === 0) document.contents.items.splice(index, 1);
    }
  }
  if (changed) {
    const backupPath = `${patchPath}.pre-plugin-manager.bak`;
    if (!fs.existsSync(backupPath)) fs.copyFileSync(patchPath, backupPath);
    fs.writeFileSync(patchPath, String(document), { mode: 0o600 });
  }
}

const workspacePath = path.join(profileRoot, "pnpm-workspace.yaml");
if (fs.existsSync(workspacePath)) {
  const workspace = YAML.parseDocument(fs.readFileSync(workspacePath, "utf8"));
  let changed = false;
  for (const packageName of ["dsh-better-sidebar", "node-pty"]) {
    if (workspace.getIn(["allowBuilds", packageName]) !== true) {
      workspace.setIn(["allowBuilds", packageName], true);
      changed = true;
    }
  }
  const allowBuilds = workspace.get("allowBuilds", true);
  if (YAML.isMap(allowBuilds)) {
    for (const pair of allowBuilds.items) {
      const packageName = String(pair.key ?? "");
      if (packageName.startsWith("dsh-better-sidebar@file:") && pair.value?.value !== true) {
        pair.value = workspace.createNode(true);
        changed = true;
      }
    }
  }
  if (changed) fs.writeFileSync(workspacePath, String(workspace), { mode: 0o600 });
}
