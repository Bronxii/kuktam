package com.bronxii.kuktam;

import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/** Process-local text transport. No disk, account data, URI handling or logging. */
public final class TextShareInbox {
    private final ArrayDeque<Map<String, String>> pending = new ArrayDeque<>();

    public String receive(String action, String mime, CharSequence text) {
        if (!"android.intent.action.SEND".equals(action) || !"text/plain".equals(mime)) return "unsupported";
        if (text == null || text.toString().trim().isEmpty()) return "empty";
        String value = text.toString();
        if (value.codePointCount(0, value.length()) > 20000) return "tooLarge";
        if (pending.size() >= 10) return "full";
        Map<String, String> event = new HashMap<>();
        event.put("id", UUID.randomUUID().toString());
        event.put("text", value);
        pending.addLast(event);
        return "accepted";
    }

    public Map<String, String> take() { return pending.pollFirst(); }
}
