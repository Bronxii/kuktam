package com.bronxii.kuktam;

/** Platform-neutral SAF boundary, shared with the native contract tests. */
public final class ExportDocumentContract {
    public static final String ACTION = "android.intent.action.CREATE_DOCUMENT";
    public static final String CATEGORY = "android.intent.category.OPENABLE";
    public static final String TITLE = "android.intent.extra.TITLE";
    public enum Selection { SELECTED, CANCELED, MISSING_URI }
    public static boolean busy(boolean chooser, boolean writing, boolean selected) {
        return chooser || writing || selected;
    }
    public static Selection selection(boolean canceled, boolean hasPending, boolean resultOk, String scheme) {
        if (canceled || !hasPending || !resultOk) return Selection.CANCELED;
        return "content".equals(scheme) ? Selection.SELECTED : Selection.MISSING_URI;
    }
}
