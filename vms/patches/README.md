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
git apply --check /path/to/OpenVMS-XMMS/vms/patches/gtk1210-vms-shared-colormap.patch
git apply /path/to/OpenVMS-XMMS/vms/patches/gtk1210-vms-shared-colormap.patch
```

The four affected C files in the pinned archive use LF line endings. If a
Windows tool converted a copy to CRLF, add `--ignore-whitespace` to each
`git apply` invocation, then restore LF source records before transfer. That
path produces the same source hashes below after LF normalization.
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

`gtk1210-vms-shared-colormap.patch` complements XMMS's VMS-only startup policy
for an 8-bit system PseudoColor visual. GdkRGB normally switches to a private
colormap when it cannot allocate its minimum color cube; that can recolor
other desktop windows while XMMS has focus. Setting the minimum to zero
allows smaller shared cubes, but alone does not prevent the private fallback.

The patch first retains GdkRGB's normal shared-cube attempts. Under this
explicit VMS shared-map policy, exhaustion instead retries a 6-by-6-by-6 cube
using read-only colors and nearest available shared matches. It keeps the
RGB lookup table, visual and window colormap together. If no safe shared
colors can be retained, initialization fails with a diagnostic rather than
switching the desktop palette. Non-VMS behavior and other visual policies
are unchanged. No system colormap entry owned by another client is rewritten.

| `gtk/gdk/gdkrgb.c` | SHA-256 |
| --- | --- |
| Original archive | `9fc911dc2532e0be804a09858185c66528d002bf1198bfad7d5e0f79a9c06496` |
| Shared-colormap patch | `134236da8775af377747a2f1964d97c562c1b9a4816f2bb29f2a0069a06b86cd` |

Native palette qualification must compare the system, XMMS-window and installed
X colormap IDs while focus changes, as well as the visible desktop. A capture
interpreted with each window's own colormap alone can hide palette flashing.
Consult the release validation report for the actual runtime results.
