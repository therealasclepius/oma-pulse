function action(kind, value, number) {
    return {kind:kind, value:value || "", number:number || 0, task_id:""};
}
function parse(question, today) {
    var text = String(question).trim().replace(/[.!?]$/, ""), match;
    text = text.replace(/^(?:(?:can|could|would) you\s+)?(?:please\s+)?/i, "").replace(/,?\s+please$/i, "");
    match = text.match(/^(?:start|set|make|create)\s+(?:me\s+)?(?:a\s+)?(\d+)\s*-?\s*(minutes?|mins?|m|hours?|hrs?|h)\s+(?:of\s+)?(?:focus(?:\s+session)?|timer)(?:\s+(?:called|for)\s+(.+))?$/i);
    if (!match) match = text.match(/^(?:start|set|make|create)\s+(?:me\s+)?(?:a\s+)?(?:timer|focus(?:\s+session)?)\s+(?:for\s+)?(\d+)\s*(minutes?|mins?|m|hours?|hrs?|h)(?:\s+(?:called|for)\s+(.+))?$/i);
    if (match) return action("start_focus",match[3] || "Open focus",Number(match[1]) * (/^h/i.test(match[2]) ? 60 : 1));
    if (/^start\s+(?:a\s+)?(?:focus|focus session|timer)$/i.test(text)) return action("start_focus","Open focus",25);

    if (/^pause\s+(?:the\s+)?(?:focus|timer|focus timer)$/i.test(text)) return action("pause_focus");
    if (/^resume\s+(?:the\s+)?(?:focus|timer|focus timer)$/i.test(text)) return action("resume_focus");
    match = text.match(/^(?:set\s+)?(?:the\s+)?volume\s+(?:to\s+)?(\d+)\s*%?$/i);
    if (match) return action("set_volume","",Number(match[1]));
    match = text.match(/^(?:add\s+(?:a\s+)?(?:todoist\s+)?task\s*:?|todo:)\s+(.+)$/i);
    if (match) return action("add_task",match[1]);
    match = text.match(/^note:\s*(.+)$/i);
    if (match) return action("append_note",match[1]);
    match = text.match(/^(?:find|search for)\s+files?\s+(?:named\s+)?(.+)$/i);
    if (match) return action("search_files",match[1]);
    match = text.match(/^show\s+(today|tomorrow)(?:[’']s)?(?:\s+calendar)?$/i);
    if (match) {
        var date = new Date(today + "T12:00:00Z");
        if (match[1].toLowerCase() === "tomorrow") date.setUTCDate(date.getUTCDate()+1);
        return action("show_day",date.toISOString().slice(0,10));
    }
    match = text.match(/^open\s+(?:(?:my|the)\s+)?(browser|terminal|file manager|files|hey|todoist|calendar)$/i);
    if (match) return action("open_app",match[1].toLowerCase() === "file manager" ? "files" : match[1].toLowerCase());
    return null;
}
