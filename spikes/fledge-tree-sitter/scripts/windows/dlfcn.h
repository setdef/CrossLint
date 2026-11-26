/* SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com> */
/* SPDX-License-Identifier: MIT */

/* The four dlfcn.h functions ruby_tree_sitter 2.1.1's language.c calls,
   over Windows' LoadLibrary, because MinGW has no dlfcn.h. */
#ifndef TSSPIKE_DLFCN_H
#define TSSPIKE_DLFCN_H

#include <stdio.h>
#include <windows.h>

#define RTLD_NOW 0

static void *dlopen(const char *path, int flags) {
  (void)flags;
  return (void *)LoadLibraryA(path);
}

static void *dlsym(void *handle, const char *name) {
  return (void *)GetProcAddress((HMODULE)handle, name);
}

static int dlclose(void *handle) { return !FreeLibrary((HMODULE)handle); }

static const char *dlerror(void) {
  static char message[64];
  DWORD code = GetLastError();
  if (code == 0) return NULL;
  snprintf(message, sizeof message, "Windows error %lu", (unsigned long)code);
  SetLastError(0);
  return message;
}

#endif
