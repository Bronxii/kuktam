package com.bronxii.kuktam;
import java.io.*;
import java.util.*;
public final class RecipeDocumentReadTest {
 static class Doc implements RecipeDocumentRead.Document {
  String name = "Túrós.kuktamrecipe"; byte[] bytes = new byte[]{1,2,3};
  boolean nameFailure, readFailure, opened, closed;
  public String displayName() throws IOException { if(nameFailure) throw new IOException(); return name; }
  public InputStream open() throws IOException {
   opened=true; if(readFailure) throw new IOException();
   return new ByteArrayInputStream(bytes) { public void close() { closed=true; } };
  }
 }
 public static void main(String[] args) throws Exception {
  String view="android.intent.action.VIEW";
  for(String mime: new String[]{RecipeFileInbox.MIME,"application/octet-stream","application/json",null}) {
   assert RecipeDocumentRead.routes(view,mime);
   Doc d=new Doc();
   assert Arrays.equals(d.bytes,RecipeDocumentRead.read(d,"content","/opaque/123",mime,false));
   assert d.closed;
  }
  assert RecipeDocumentRead.routes("android.intent.action.SEND",RecipeFileInbox.MIME);
  assert !RecipeDocumentRead.routes("android.intent.action.SEND","text/plain");
  assert !RecipeDocumentRead.routes("android.intent.action.SEND_MULTIPLE",RecipeFileInbox.MIME);
  Doc picker=new Doc(); RecipeDocumentRead.read(picker,"content","/123",null,true); assert picker.closed;
  Doc wrong=new Doc(); wrong.name="random.json";
  try { RecipeDocumentRead.read(wrong,"content","/123","application/json",false); throw new AssertionError(); }
  catch(RecipeDocumentRead.WrongFormat expected) { assert !wrong.opened; }
  Doc missing=new Doc(); missing.nameFailure=true;
  RecipeDocumentRead.read(missing,"content","/file.kuktamrecipe",null,false);
  Doc custom=new Doc(); custom.name=null;
  RecipeDocumentRead.read(custom,"content","/123",RecipeFileInbox.MIME,false);
  try { RecipeDocumentRead.read(custom,"content","/123",RecipeFileInbox.MIME,true); throw new AssertionError(); }
  catch(RecipeDocumentRead.WrongFormat expected) { }
  Doc huge=new Doc(); huge.bytes=new byte[RecipeFileInbox.LIMIT+1];
  try { RecipeDocumentRead.read(huge,"content","/123",null,false); throw new AssertionError(); }
  catch(RecipeFileInbox.TooLarge expected) { assert huge.closed; }
  Doc failure=new Doc(); failure.readFailure=true;
  try { RecipeDocumentRead.read(failure,"content","/123",null,false); throw new AssertionError(); }
  catch(IOException expected) { }
  Doc remote=new Doc();
  try { RecipeDocumentRead.read(remote,"https","/file.kuktamrecipe",null,false); throw new AssertionError(); }
  catch(IOException expected) { assert !remote.opened; }
  RecipeFileInbox inbox=new RecipeFileInbox();
  String cold=inbox.begin(); inbox.finish(cold,picker.bytes,null); // channel not ready
  assert inbox.take().get("id").equals(cold); assert inbox.take().get("id").equals(cold); assert inbox.take()==null;
  String warm=inbox.begin(); assert inbox.take().get("id").equals(warm); assert inbox.take()==null;
  inbox.finish(warm,picker.bytes,null); assert inbox.take().get("id").equals(warm); assert inbox.take()==null;
  System.out.println("RecipeDocumentRead PASS: opaque/displayName/MIME/SAF/bounds/errors/cold/warm/pending/once");
 }
}
