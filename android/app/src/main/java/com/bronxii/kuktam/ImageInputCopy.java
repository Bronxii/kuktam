package com.bronxii.kuktam;
import java.io.*;
/** Bounded local stream copy. Never opens a path or URI supplied by the caller. */
public final class ImageInputCopy {
 public static final class TooLarge extends IOException {}
 public static void copy(InputStream input, OutputStream output, long max) throws IOException {
  if (input == null || max <= 0) throw new IOException();
  byte[] buffer = new byte[8192]; long total = 0;
  int n;
  while ((n = input.read(buffer)) != -1) {
   total += n; if (total > max) throw new TooLarge();
   output.write(buffer, 0, n);
  }
  if (total == 0) throw new IOException();
 }
 public static boolean validCount(int count, int remaining) {
  return remaining >= 1 && remaining <= 5 && count >= 0 && count <= remaining;
 }
}
