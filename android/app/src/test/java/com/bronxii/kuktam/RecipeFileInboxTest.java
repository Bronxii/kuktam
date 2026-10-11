package com.bronxii.kuktam;
import java.io.*;
import java.util.*;
public final class RecipeFileInboxTest {
 public static void main(String[] args) throws Exception {
  assert RecipeFileInbox.supports("android.intent.action.VIEW",RecipeFileInbox.MIME);
  assert RecipeFileInbox.supports("android.intent.action.SEND",RecipeFileInbox.MIME);
  assert !RecipeFileInbox.supports("android.intent.action.SEND_MULTIPLE",RecipeFileInbox.MIME);
  assert !RecipeFileInbox.supports("android.intent.action.SEND","text/plain");
  assert !RecipeFileInbox.supports("android.intent.action.VIEW","application/json");
  assert !RecipeFileInbox.supports("android.intent.action.VIEW","application/octet-stream");
  assert RecipeFileInbox.validScheme("content");
  assert !RecipeFileInbox.validScheme(null);
  assert !RecipeFileInbox.validScheme("file");
  assert !RecipeFileInbox.validScheme("https");
  assert RecipeFileInbox.supports("android.intent.action.VIEW","application/octet-stream","content","/docs/Túrós.süti.kuktamrecipe");
  assert RecipeFileInbox.supports("android.intent.action.VIEW","application/json","content","/docs/recept.kuktamrecipe");
  assert !RecipeFileInbox.supports("android.intent.action.VIEW","application/json","content","/docs/random.json");
  assert !RecipeFileInbox.supports("android.intent.action.VIEW","application/zip","content","/docs/recept.kuktamrecipe");
  assert !RecipeFileInbox.supports("android.intent.action.VIEW","application/octet-stream","content","/docs/random.bin");
  assert !RecipeFileInbox.supports("android.intent.action.VIEW","application/octet-stream","content","/opaque/123");
  assert !RecipeFileInbox.supports("android.intent.action.SEND","application/octet-stream","content","/docs/recept.kuktamrecipe");
  assert !RecipeFileInbox.supports("android.intent.action.VIEW","application/octet-stream","https","/recept.kuktamrecipe");
  byte[] bytes = new byte[RecipeFileInbox.LIMIT]; Arrays.fill(bytes,(byte)42);
  assert Arrays.equals(bytes,RecipeFileInbox.read(new ByteArrayInputStream(bytes)));
  boolean failed=false;
  try { RecipeFileInbox.read(new ByteArrayInputStream(new byte[RecipeFileInbox.LIMIT+1])); } catch(RecipeFileInbox.TooLarge e) { failed=true; }
  assert failed; failed=false;
  try { RecipeFileInbox.read(new InputStream(){public int read() throws IOException {throw new IOException();}}); } catch(IOException e) {failed=true;}
  assert failed;
  RecipeFileInbox inbox = new RecipeFileInbox();
  String cold=inbox.begin(); inbox.finish(cold,new byte[]{1},null);
  assert inbox.take().get("stage").equals("begin"); assert inbox.take().get("id").equals(cold); assert inbox.take()==null;
  String warm=inbox.begin(); assert !cold.equals(warm); inbox.finish(warm,null,"read");
  assert inbox.take().get("stage").equals("begin"); assert inbox.take().get("error").equals("read");
  for(int i=0;i<10;i++) assert inbox.begin()!=null;
  assert inbox.begin()==null;
  System.out.println("RecipeFileInbox PASS: MIME/actions/read/bounds/errors/queue/cold/warm/consumption");
 }
}
