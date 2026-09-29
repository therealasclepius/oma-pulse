"use strict";
const tasks = [...document.querySelectorAll(".sample-task input")];
function updateTasks() {
  document.querySelector("#task-count").textContent =
    `${tasks.filter((task) => !task.checked).length} to do`;
}
tasks.forEach((task) => task.addEventListener("change", updateTasks));
let remaining = 25 * 60;
let endTime = 0;
let interval;
const timer = document.querySelector("#timer");
const start = document.querySelector("#timer-start");
const status = document.querySelector("#focus-status");
function renderTimer() {
  timer.innerHTML = `${String(Math.floor(remaining / 60)).padStart(2, "0")}<span>:</span>${String(remaining % 60).padStart(2, "0")}`;
  timer.setAttribute(
    "aria-label",
    `${Math.floor(remaining / 60)} minutes ${remaining % 60} seconds remaining`,
  );
}
function pause() {
  clearInterval(interval);
  interval = undefined;
  start.textContent = "Resume focusing ▶";
  status.textContent = "Take a breath. Come back when you’re ready.";
}
start.addEventListener("click", () => {
  if (interval) {
    remaining = Math.max(0, Math.ceil((endTime - Date.now()) / 1000));
    pause();
    renderTimer();
    return;
  }
  if (!remaining) remaining = 25 * 60;
  endTime = Date.now() + remaining * 1000;
  start.textContent = "Pause focus Ⅱ";
  status.textContent = "One thing. A little room to do it.";
  interval = setInterval(() => {
    remaining = Math.max(0, Math.ceil((endTime - Date.now()) / 1000));
    renderTimer();
    if (!remaining) {
      pause();
      start.textContent = "Start again ▶";
      status.textContent = "A little progress. Take a break.";
    }
  }, 250);
});
document.querySelector("#timer-reset").addEventListener("click", () => {
  pause();
  remaining = 25 * 60;
  renderTimer();
  start.textContent = "Start focusing ▶";
  status.textContent = "No rush. Just a beginning.";
});
document.querySelector("#demo-note").addEventListener("input", () => {
  document.querySelector("#note-status").textContent =
    "A little thought, kept in this tab only.";
});
const days = [
  {
    name: "Today",
    events: [
      ["10:00 — 10:30", "A fresh perspective", "Studio calendar"],
      ["14:00 — 15:00", "Time to make something", "Personal calendar"],
    ],
  },
  {
    name: "Tomorrow",
    events: [
      ["09:30 — 10:00", "A walk before work", "Personal calendar"],
      ["13:00 — 14:00", "Bring the ideas together", "Studio calendar"],
    ],
  },
  {
    name: "Thursday",
    events: [["11:00 — 12:00", "Share the first draft", "Studio calendar"]],
  },
];
let day = 0;
function renderDay() {
  document.querySelector("#calendar-date").textContent = days[day].name;
  document.querySelector("#preview-events").replaceChildren(
    ...days[day].events.map(([time, title, calendar]) => {
      const event = document.createElement("div");
      event.className = "event";
      for (const [tag, value] of [
        ["small", time],
        ["strong", title],
        ["span", calendar],
      ]) {
        const element = document.createElement(tag);
        element.textContent = value;
        event.append(element);
      }
      return event;
    }),
  );
  document.querySelector("#previous-day").disabled = day === 0;
  document.querySelector("#next-day").disabled = day === days.length - 1;
}
document.querySelector("#previous-day").addEventListener("click", () => {
  day = Math.max(0, day - 1);
  renderDay();
});
document.querySelector("#next-day").addEventListener("click", () => {
  day = Math.min(days.length - 1, day + 1);
  renderDay();
});
renderDay();
document.querySelector("#copy-install").addEventListener("click", async () => {
  const command = document.querySelector("#install-command");
  try {
    await navigator.clipboard.writeText(command.textContent);
    document.querySelector("#copy-install").textContent = "Copied";
    document.querySelector("#copy-status").textContent =
      "Copied. Paste into your Omarchy terminal.";
  } catch {
    const range = document.createRange();
    range.selectNodeContents(command);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.querySelector("#copy-status").textContent =
      "Command selected. Copy it with Ctrl+C or ⌘C.";
  }
});

// This preview has no connection to HEY: every message below is sample data.
const sampleMail = [
  {
    id: "studio",
    sender: "Alex at the studio",
    title: "A good place to start",
    excerpt: "The first sketches are ready for a look.",
    body: "Hey,\n\nI put together a few sketches for the new project. There’s a small idea in there that I think could become something good.\n\nHave a look when you’ve got a little room in your day.\n\nAlex",
    unread: true,
  },
  {
    id: "weekend",
    sender: "Sam",
    title: "A little weekend plan",
    excerpt: "Coffee, a walk, and nowhere to rush.",
    body: "Hey!\n\nHow about coffee on Saturday, then a walk by the water? No big plan. Just a chance to catch up.\n\nSee you soon,\nSam",
    unread: true,
  },
];
const mailUndo = [];
const mailList = document.querySelector("#preview-mail");
const mailDialog = document.querySelector("#mail-dialog");
let openedMail;
function renderMail() {
  const unread = sampleMail.filter((message) => message.unread);
  document.querySelector("#mail-count").textContent = `${unread.length} unread`;
  document.querySelector("#mail-undo").disabled = mailUndo.length === 0;
  mailList.replaceChildren(
    ...unread.map((message) => {
      const row = document.createElement("article");
      row.className = "sample-mail";
      row.dataset.mailId = message.id;
      const open = document.createElement("button");
      open.type = "button";
      open.className = "mail-open";
      open.dataset.openMail = message.id;
      for (const [tag, text, className] of [
        ["span", message.sender, "mail-sender"],
        ["strong", message.title, ""],
        ["span", message.excerpt, ""],
      ]) {
        const element = document.createElement(tag);
        element.textContent = text;
        element.className = className;
        open.append(element);
      }
      const read = document.createElement("button");
      read.type = "button";
      read.className = "mail-read";
      read.dataset.readMail = message.id;
      read.textContent = "✓";
      read.title = "Mark as read";
      read.setAttribute("aria-label", `Mark ${message.title} as read`);
      row.append(open, read);
      return row;
    }),
  );
  if (!unread.length) {
    const empty = document.createElement("p");
    empty.className = "mail-empty";
    empty.textContent = "All caught up. A little breathing room.";
    mailList.append(empty);
  }
}
function markSampleRead(id) {
  const message = sampleMail.find((item) => item.id === id);
  if (!message || !message.unread) return;
  message.unread = false;
  mailUndo.push(id);
  renderMail();
  document.querySelector("#mail-status").textContent =
    `Marked “${message.title}” as read.`;
  document.querySelector("#mail-undo").focus({ preventScroll: true });
}
mailList.addEventListener("click", (event) => {
  const read = event.target.closest("[data-read-mail]");
  if (read) {
    markSampleRead(read.dataset.readMail);
    return;
  }
  const open = event.target.closest("[data-open-mail]");
  if (!open) return;
  openedMail = sampleMail.find(
    (message) => message.id === open.dataset.openMail,
  );
  document.querySelector("#mail-dialog-sender").textContent =
    `From ${openedMail.sender}`;
  document.querySelector("#mail-dialog-title").textContent = openedMail.title;
  document.querySelector("#mail-dialog-body").textContent = openedMail.body;
  mailDialog.showModal();
});
document
  .querySelector("#mail-dialog-close")
  .addEventListener("click", () => mailDialog.close());
document.querySelector("#mail-dialog-read").addEventListener("click", () => {
  mailDialog.close();
  markSampleRead(openedMail.id);
});
document.querySelector("#mail-undo").addEventListener("click", () => {
  const id = mailUndo.pop();
  if (!id) return;
  sampleMail.find((message) => message.id === id).unread = true;
  renderMail();
  document.querySelector("#mail-status").textContent =
    "Undone. The sample message is unread again.";
});
renderMail();
