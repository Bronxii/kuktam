package com.bronxii.kuktam;
import java.io.*;
public final class ImageInputCopyTest {
 public static void main(String[] args) throws Exception {
  assert ImageInputCopy.validCount(1,1); assert ImageInputCopy.validCount(5,5);
  assert ImageInputCopy.validCount(0,5); assert !ImageInputCopy.validCount(6,5);
  assert !ImageInputCopy.validCount(2,1); assert !ImageInputCopy.validCount(0,6);
  ByteArrayOutputStream output=new ByteArrayOutputStream();
  ImageInputCopy.copy(new ByteArrayInputStream(new byte[]{1,2,3}),output,3);
  assert output.size()==3;
  try {ImageInputCopy.copy(new ByteArrayInputStream(new byte[4]),new ByteArrayOutputStream(),3);throw new AssertionError();}
  catch(ImageInputCopy.TooLarge expected){}
  try {ImageInputCopy.copy(new ByteArrayInputStream(new byte[0]),output,3);throw new AssertionError();}
  catch(IOException expected){}
  try {ImageInputCopy.copy(null,output,3);throw new AssertionError();}
  catch(IOException expected){}
  try {ImageInputCopy.copy(new InputStream(){public int read()throws IOException{throw new IOException();}},output,3);throw new AssertionError();}
  catch(IOException expected){}
  System.out.println("ImageInputCopy PASS: 1/5/6/cancel/remaining/bounded/empty/read failure");
 }
}
