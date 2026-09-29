const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const out = path.join(root, "dist/site");
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
fs.cpSync(path.join(root, "site"), out, { recursive: true });
fs.copyFileSync(path.join(root, "install.sh"), path.join(out, "install.sh"));
console.log(
  "Built static landing page in dist/site (public site assets and installer only).",
);
