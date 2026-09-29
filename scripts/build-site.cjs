const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const source = path.join(root, "site");
const out = path.join(root, "dist/site");
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
fs.cpSync(source, out, {
  recursive: true,
  filter: (file) => !path.basename(file).startsWith("_"),
});
const footer = fs.readFileSync(path.join(source, "_footer.html"), "utf8");
for (const file of fs.readdirSync(out)) {
  if (!file.endsWith(".html")) continue;
  const target = path.join(out, file);
  const html = fs.readFileSync(target, "utf8");
  if (!html.includes("<!-- SITE_FOOTER -->"))
    throw new Error(`Missing shared footer in ${file}`);
  fs.writeFileSync(target, html.replace("<!-- SITE_FOOTER -->", footer));
}
fs.copyFileSync(path.join(root, "install.sh"), path.join(out, "install.sh"));
console.log(
  "Built static landing page in dist/site with shared social footer.",
);
