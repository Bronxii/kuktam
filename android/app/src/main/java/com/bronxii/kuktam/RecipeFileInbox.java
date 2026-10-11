package com.bronxii.kuktam;
import java.io.*;
import java.util.*;

/** Typed, bounded in-memory events; input streams are supplied by ContentResolver. */
public final class RecipeFileInbox {
    public static final String MIME = "application/vnd.kuktam.recipe+json";
    public static final int LIMIT = 256 * 1024;
    private final ArrayDeque<Map<String,Object>> events = new ArrayDeque<>();
    private int pending;
    public static boolean supports(String action, String mime) {
        return MIME.equals(mime) && ("android.intent.action.VIEW".equals(action) || "android.intent.action.SEND".equals(action));
    }
    public static boolean supports(String action, String mime, String scheme, String path) {
        if (supports(action, mime)) return true;
        return "android.intent.action.VIEW".equals(action) && validScheme(scheme)
            && ("application/octet-stream".equals(mime) || "application/json".equals(mime))
            && recipeName(path);
    }
    public static boolean recipeName(String name) { return name != null && name.endsWith(".kuktamrecipe"); }
    public static boolean validScheme(String scheme) { return "content".equals(scheme); }
    public synchronized String begin() {
        if (pending >= 10) return null;
        pending++;
        String id = UUID.randomUUID().toString();
        Map<String,Object> event = new HashMap<>(); event.put("id",id); event.put("stage","begin"); events.add(event);
        return id;
    }
    public synchronized void finish(String id, byte[] bytes, String error) {
        Map<String,Object> event = new HashMap<>(); event.put("id",id); event.put("stage","complete");
        if (error != null) event.put("error",error); else event.put("bytes",bytes);
        events.add(event);
    }
    public synchronized Map<String,Object> take() {
        Map<String,Object> event = events.poll();
        if (event != null && "complete".equals(event.get("stage"))) pending--;
        return event;
    }
    public static byte[] read(InputStream input) throws IOException {
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192]; int count;
        while ((count = input.read(buffer)) != -1) {
            if (result.size() + count > LIMIT) throw new TooLarge();
            result.write(buffer,0,count);
        }
        return result.toByteArray();
    }
    public static final class TooLarge extends IOException {}
}
