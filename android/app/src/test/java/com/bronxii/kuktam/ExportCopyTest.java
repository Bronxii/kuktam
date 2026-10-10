package com.bronxii.kuktam;
import java.io.*;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;
public final class ExportCopyTest {
 public static void main(String[] args) throws Exception {
  assert ExportCopy.MIME.equals("application/zip");
  assert ExportCopy.validTitle("Kuktam-receptek-20261010-120000Z.zip");
  assert !ExportCopy.validTitle("../bad.zip");
  byte[] bytes = new byte[200000]; Arrays.fill(bytes,(byte)42);
  ByteArrayOutputStream output = new ByteArrayOutputStream();
  ExportCopy.copy(new ByteArrayInputStream(bytes),output,new AtomicBoolean(false));
  assert Arrays.equals(bytes,output.toByteArray());
  boolean failed=false;
  try {ExportCopy.copy(new ByteArrayInputStream(bytes),new ByteArrayOutputStream(),new AtomicBoolean(true));} catch(IOException e){failed=true;}
  assert failed;
  failed=false;
  try {ExportCopy.copy(new ByteArrayInputStream(bytes),new OutputStream(){public void write(int b)throws IOException{throw new IOException();}},new AtomicBoolean(false));} catch(IOException e){failed=true;}
  assert failed;
  System.out.println("ExportCopy PASS: MIME/title/full copy/cancel/write exception");
 }
}
