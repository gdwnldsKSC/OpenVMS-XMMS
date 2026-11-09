# GTK dependency patch

`gtk1210-vms-device-cache.patch` applies to `gtk/gtk/gtkfilesel.c` from the
exact GTK archive listed in [DEPENDENCIES.md](../DEPENDENCIES.md). It fixes
OpenVMS directory identity: legacy `st_dev` contains a borrowed device-name
pointer, so retained names need their own storage and comparisons use their
values. All three VMS file-ID words are preserved. Non-VMS behavior is unchanged.

The corresponding-source archive shipped with the runtime kit already contains
this change. Native users of that archive need no patch program: use the
normal DCL build procedures and their installed MMOV development files.

When starting with the original GTK download, apply the patch on the host
before transferring the source to VMS. From the extracted GTK root:

```text
git apply --check /path/to/OpenVMS-XMMS/vms/patches/gtk1210-vms-device-cache.patch
git apply /path/to/OpenVMS-XMMS/vms/patches/gtk1210-vms-device-cache.patch
```

GNU `patch -p1` can also apply this unified diff. Preserve LF source records.
The SHA-256 of `gtk/gtk/gtkfilesel.c` before and after the patch is:

| Source | SHA-256 |
| --- | --- |
| Original | `587b0c774b2973245dc33b37f49aacd222115e6dd7fcb0e1680ad300f62bcc5d` |
| Patched | `f96a974c57e283c52a20dbf7dffb241a04f340fd029450fb22f7071ceed1d9dd` |

The build procedure separately applies the published DECwindows shape-header
include correction. It copies the owned compiler preinclude headers into the
GTK tree; no system header or runtime image is modified.
