const fs = require("node:fs");

const manifestPath = process.argv[2];
if (!manifestPath) throw new Error("package.json path is required");

const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
if (manifest.scripts && typeof manifest.scripts === "object") {
  delete manifest.scripts.prepare;
  if (Object.keys(manifest.scripts).length === 0) delete manifest.scripts;
}
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
