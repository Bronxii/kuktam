package com.bronxii.kuktam;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.IOException;
import java.util.concurrent.atomic.AtomicBoolean;

/** Bounded-memory, cancellable copy. Caller owns/cleans the created document. */
public final class ExportCopy {
    public static final String MIME = "application/zip";
    public static boolean validTitle(String title) {
        return title != null && title.matches("Kuktam-receptek-[0-9]{8}-[0-9]{6}Z\\.zip");
    }
    public static void copy(InputStream input, OutputStream output, AtomicBoolean cancelled) throws IOException {
        byte[] buffer = new byte[65536];
        int n;
        while ((n = input.read(buffer)) != -1) {
            if (cancelled.get()) throw new IOException("cancelled");
            output.write(buffer, 0, n);
        }
        output.flush();
        if (cancelled.get()) throw new IOException("cancelled");
    }
}
