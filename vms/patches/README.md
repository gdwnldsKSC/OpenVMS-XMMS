# GTK dependency patches

`gtk1210-vms-device-cache.patch` applies to `gtk/gtk/gtkfilesel.c` from the
exact GTK archive listed in [DEPENDENCIES.md](../DEPENDENCIES.md). It fixes
OpenVMS directory identity: legacy `st_dev` contains a borrowed device-name
pointer, so retained names need their own storage and comparisons use their
values. All three VMS file-ID words are preserved. Non-VMS behavior is unchanged.

The corresponding-source archive shipped with the runtime kit already contains
these changes. Native users of that archive need no patch program: use the
normal DCL build procedures and their installed MMOV development files.

When starting with the original GTK download, apply the patch on the host
before transferring the source to VMS. From the extracted GTK root:

```text
git apply --check /path/to/OpenVMS-XMMS/vms/patches/gtk1210-vms-device-cache.patch
git apply /path/to/OpenVMS-XMMS/vms/patches/gtk1210-vms-device-cache.patch
git apply --check /path/to/OpenVMS-XMMS/vms/patches/gtk1210-vms-system-headers.patch
git apply /path/to/OpenVMS-XMMS/vms/patches/gtk1210-vms-system-headers.patch
```

GNU `patch -p1` can also apply this unified diff. Preserve LF source records.
The SHA-256 of `gtk/gtk/gtkfilesel.c` before and after the device-cache patch is:

| Source | SHA-256 |
| --- | --- |
| Original | `587b0c774b2973245dc33b37f49aacd222115e6dd7fcb0e1680ad300f62bcc5d` |
| Patched | `e7b82cbce24d7ce0eb94616f2cf85690833f195d8b529b29c91d32018b3de82c` |

The build procedure separately applies the published DECwindows shape-header
include correction. It copies the owned compiler preinclude headers into the
GTK tree; no system header or runtime image is modified.

`gtk1210-vms-system-headers.patch` replaces the unavailable `<sys/param.h>`
with standard `<limits.h>` on OpenVMS in the file selector, preview and resource
parser. The file selector retains its existing `PATH_MAX`/`MAXPATHLEN` fallback;
GLib already supplies `MIN` and `MAX`. The non-VMS include remains unchanged.
Apply it after the device-cache patch. The native scan identified these as its
only three failures among 156 source files.

| Final patched source | SHA-256 |
| --- | --- |
| `gtkfilesel.c` | `76f6a728b74302de54c4d3408fdcb375eae665fd223c44ab667dededa4ecd589` |
| `gtkpreview.c` | `3ff8f1c8e4f3b9aca066303b2baea2c3802d6c49c1a24d7bfde8ef147acca96c` |
| `gtkrc.c` | `c3f69ebf5aa713f63b08651f9a0aefd099d204e8b56c2973bb7f37713e089a10` |
