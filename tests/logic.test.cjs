const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const context = vm.createContext({});
vm.runInContext(fs.readFileSync("Logic.js", "utf8"), context);
test("old workspaces migrate and running sessions resume paused", () => {
  const state = context.fresh();
  state.focus.running = true;
  const restored = context.parse(JSON.stringify(state));
  assert.equal(restored.focus.running, false);
  assert.equal(restored.version, 1);
});
test("stored task source is preserved and unknown source is rejected", () => {
  const state = context.fresh();
  state.taskSource = "local";
  assert.equal(context.parse(JSON.stringify(state)).taskSource, "local");
  state.taskSource = "invalid";
  assert.throws(() => context.parse(JSON.stringify(state)));
});
test("suspend never counts as active focus time", () => {
  const state = context.fresh();
  state.focus.running = true;
  assert.equal(context.advance(state, 90, Date.now()), "paused");
  assert.equal(state.focus.elapsed, 0);
  assert.equal(state.focus.running, false);
});
test("focus completion stops precisely and records active time", () => {
  const state = context.fresh();
  state.focus.duration = 2;
  state.focus.running = true;
  assert.equal(context.advance(state, 3, Date.now()), "finished");
  assert.equal(state.focus.elapsed, 2);
  assert.equal(state.focus.running, false);
  assert.equal(Object.values(state.activity)[0], 2);
});
test("site build keeps helper code and credentials outside the public output", () => {
  const { execFileSync } = require("node:child_process");
  execFileSync(process.execPath, ["scripts/build-site.cjs"]);
  const files = fs.readdirSync("dist/site", { recursive: true });
  assert(files.includes("install.sh"));
  assert(files.includes("index.html"));
  assert(
    !files.some((file) =>
      /\.py$|\.qml$|todoist\.json|workspace\.json|\.env/.test(file),
    ),
  );
});
test("every public HTML page includes the creator's social handles", () => {
  const pages = fs
    .readdirSync("dist/site")
    .filter((file) => file.endsWith(".html"));
  assert(pages.includes("index.html"));
  assert(pages.includes("404.html"));
  assert(!pages.includes("_footer.html"));
  for (const page of pages) {
    const html = fs.readFileSync(`dist/site/${page}`, "utf8");
    for (const url of [
      "https://twitter.com/kostahantzis",
      "https://www.linkedin.com/in/kostahantzis/",
      "https://www.instagram.com/kostahantzis/",
      "https://www.youtube.com/@kostahantzis_",
      "https://mentorpass.co/kostahantzis",
    ])
      assert(html.includes(url), `${page} is missing ${url}`);
    assert(!html.includes("<!-- SITE_FOOTER -->"));
  }
});

test("provider choices persist while unknown values are rejected", () => {
  const state = context.fresh();
  for (const source of ["hey", "gmail", "outlook", "imap", "off"]) {
    state.mailSource=source; state.calendarSource="google";
    assert.equal(context.parse(JSON.stringify(state)).mailSource,source);
  }
  state.mailSource="invalid";
  assert.throws(() => context.parse(JSON.stringify(state)));
});
