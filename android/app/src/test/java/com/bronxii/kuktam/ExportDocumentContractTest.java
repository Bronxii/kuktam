package com.bronxii.kuktam;
public final class ExportDocumentContractTest {
    public static void main(String[] args) {
        assert ExportDocumentContract.ACTION.equals("android.intent.action.CREATE_DOCUMENT");
        assert ExportDocumentContract.CATEGORY.equals("android.intent.category.OPENABLE");
        assert ExportDocumentContract.TITLE.equals("android.intent.extra.TITLE");
        assert ExportCopy.MIME.equals("application/zip");
        assert ExportCopy.validTitle("Kuktam-receptek-20261010-120000Z.zip");
        assert !ExportDocumentContract.busy(false, false, false);
        assert ExportDocumentContract.busy(true, false, false);
        assert ExportDocumentContract.busy(false, true, false);
        assert ExportDocumentContract.busy(false, false, true);
        assert ExportDocumentContract.selection(false, true, true, "content") == ExportDocumentContract.Selection.SELECTED;
        assert ExportDocumentContract.selection(false, true, false, null) == ExportDocumentContract.Selection.CANCELED;
        assert ExportDocumentContract.selection(true, true, true, "content") == ExportDocumentContract.Selection.CANCELED;
        assert ExportDocumentContract.selection(false, false, true, "content") == ExportDocumentContract.Selection.CANCELED;
        assert ExportDocumentContract.selection(false, true, true, null) == ExportDocumentContract.Selection.MISSING_URI;
        assert ExportDocumentContract.selection(false, true, true, "file") == ExportDocumentContract.Selection.MISSING_URI;
        System.out.println("ExportDocumentContractTest PASS");
    }
}
