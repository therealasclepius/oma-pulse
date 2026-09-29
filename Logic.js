function dayKey(ms) {
    var d = new Date(ms);
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
}
function fresh() {
    return {version: 1, tasks: [], notes: {}, activity: {}, focus: {title: "Open focus", duration: 1500, elapsed: 0, running: false}};
}
function parse(raw) {
    if (!raw.trim()) return fresh();
    var s = JSON.parse(raw);
    if (s.version !== 1 || !Array.isArray(s.tasks) || !s.notes || !s.activity || !s.focus
        || !Number.isFinite(s.focus.elapsed) || s.focus.elapsed < 0
        || !Number.isFinite(s.focus.duration) || s.focus.duration < 0
        || (s.taskSource !== undefined && ["local", "todoist"].indexOf(s.taskSource) < 0)
        || typeof s.focus.title !== "string"
        || s.tasks.some(function(t) { return !t || typeof t.id !== "string" || typeof t.title !== "string"; })
        || Object.keys(s.notes).some(function(k) { return typeof s.notes[k] !== "string"; }))
        throw new Error("Unrecognized workspace data");
    // A restarted shell cannot know how much unattended time was active work.
    s.focus.running = false;
    return s;
}
function advance(s, delta, now) {
    if (!s.focus.running) return "idle";
    // Suspend or a stalled desktop must not count as focus time.
    if (delta <= 0 || delta > 3) { s.focus.running = false; return "paused"; }
    var amount = s.focus.duration > 0 ? Math.min(delta, Math.max(0, s.focus.duration - s.focus.elapsed)) : delta;
    s.focus.elapsed += amount;
    var key = dayKey(now);
    s.activity[key] = (s.activity[key] || 0) + amount;
    if (s.focus.duration > 0 && s.focus.elapsed >= s.focus.duration) {
        s.focus.running = false;
        return "finished";
    }
    return "running";
}
function clock(seconds) {
    var n = Math.max(0, Math.ceil(seconds));
    var h = Math.floor(n / 3600);
    return (h ? h + ":" : "") + String(Math.floor(n / 60) % (h ? 60 : 100000)).padStart(2, "0") + ":" + String(n % 60).padStart(2, "0");
}
function calendarDays(feed) {
    var panel = feed.panel || {};
    var base = panel.date || dayKey(Date.now());
    var days = panel.agenda_days || [{date_label: panel.date_label || base, events: panel.events || feed.events || []}];
    return days.map(function(day, index) {
        // Increment date strings in UTC to avoid DST or machine/calendar zone differences.
        var d = new Date(base + "T12:00:00Z"); d.setUTCDate(d.getUTCDate() + index);
        return {date: d.toISOString().slice(0, 10), label: day.date_label,
                events: (day.events || []).filter(e => typeof e.start_ms === "number" && typeof e.end_ms === "number").slice().sort((a,b) => a.start_ms - b.start_ms)};
    });
}
