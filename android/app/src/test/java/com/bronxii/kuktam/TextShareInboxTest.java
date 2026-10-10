package com.bronxii.kuktam;

/** Dependency-free JVM contract test. Run with java -ea after javac. */
public final class TextShareInboxTest {
    public static void main(String[] args) {
        TextShareInbox inbox = new TextShareInbox();
        String send = "android.intent.action.SEND";
        String text = "Áfonyás süti\n2 db tojás";
        assert "accepted".equals(inbox.receive(send, "text/plain", text));
        assert text.equals(inbox.take().get("text")); // Initial delivery.
        assert inbox.take() == null; // Consumed; startup poll/callback cannot duplicate.
        assert "accepted".equals(inbox.receive(send, "text/plain", text));
        String firstId = inbox.take().get("id");
        assert "accepted".equals(inbox.receive(send, "text/plain", text));
        assert !firstId.equals(inbox.take().get("id")); // New intent, even same text.
        assert "empty".equals(inbox.receive(send, "text/plain", null));
        assert "empty".equals(inbox.receive(send, "text/plain", " "));
        assert "unsupported".equals(inbox.receive(send, "image/png", text));
        assert "unsupported".equals(inbox.receive("android.intent.action.SEND_MULTIPLE", "text/plain", text));
        assert "unsupported".equals(inbox.receive("android.intent.action.MAIN", "text/plain", text));
        assert "tooLarge".equals(inbox.receive(send, "text/plain", "x".repeat(20001)));
        for (int i = 0; i < 10; i++) assert "accepted".equals(inbox.receive(send, "text/plain", "" + i));
        assert "full".equals(inbox.receive(send, "text/plain", text));
        for (int i = 0; i < 10; i++) assert ("" + i).equals(inbox.take().get("text"));
        assert inbox.take() == null;
        System.out.println("TextShareInbox contract PASS (initial/new/missing/MIME/multiple/consumption/Unicode/bounds/FIFO)");
    }
}
