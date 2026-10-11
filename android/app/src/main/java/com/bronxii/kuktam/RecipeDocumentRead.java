package com.bronxii.kuktam;
import java.io.*;

/** Shared direct-open / picker contract. No payload or URI diagnostics. */
public final class RecipeDocumentRead {
    public interface Document {
        String displayName() throws IOException;
        InputStream open() throws IOException;
    }
    public static boolean routes(String action, String mime) {
        return "android.intent.action.VIEW".equals(action)
            || ("android.intent.action.SEND".equals(action) && RecipeFileInbox.MIME.equals(mime));
    }
    public static byte[] read(Document document, String scheme, String path,
                              String mime, boolean requireName) throws IOException {
        if (!RecipeFileInbox.validScheme(scheme)) throw new IOException();
        String name = null;
        try { name = document.displayName(); } catch (IOException ignored) { }
        boolean named = RecipeFileInbox.recipeName(name) || RecipeFileInbox.recipeName(path);
        if (!named && (requireName || !RecipeFileInbox.MIME.equals(mime))) throw new WrongFormat();
        try (InputStream input = document.open()) {
            if (input == null) throw new IOException();
            return RecipeFileInbox.read(input);
        }
    }
    public static final class WrongFormat extends IOException { }
}
