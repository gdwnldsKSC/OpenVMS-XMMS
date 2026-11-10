# Native build dependencies

The target is OpenVMS Alpha V8.4-2L2 with VSI C, DECwindows and the working
MMOV installation. GTK and XMMS have compiled and linked natively on the
isolated target system. Native validation includes continuous 20-second WAV
and full-track MP3 playback, file selection and playlist display, normal
process exit, and settings preserved across a clean restart. Detailed runtime,
package installation, removal and installed-runtime checks are recorded
separately in the release validation report. No GNV,
Linux audio driver, Perl or Autoconf installation is required by these DCL
build procedures.

The isolated build system's native product registry reports these exact
installed dependencies:

- `VSI AXPVMS VMS V8.4-2L2`
- `VSI AXPVMS DWMOTIF V1.7-F`
- `DEC AXPVMS MMOV V2.2`

## Original source archives

Download these outside the XMMS source tree. Preserve their original license
notices. The SHA-256 values below describe the downloaded bytes.

| Archive | SHA-256 |
| --- | --- |
| [GTK+ 1.2.10 OpenVMS A1 source](https://www.digiater.nl/openvms/decus/vmslt05a/vu/gtk1210-openvms-a1.zip) | `172a419fba903576790ff9c697783a88a0f959d59b056b05db11fe13d235227b` |
| [OpenVMS Porting Library A9 runtime PCSI](https://www.digiater.nl/openvms/decus/vmslt05a/vu/cpq-axpvms-opl-v0100-0a9-1.pcsi) | `c7f4694b5497762e5aa355929fc1c62eacfa0b46f81ff8bdc73e7a68d8f4a9b7` |
| [OpenVMS Porting Library A9 source](https://www.digiater.nl/openvms/decus/vmslt05a/vu/porting-a9.sfx_axpexe) | `d63dbd7ffeced0f2050844986a5c34e12fdc00c7e47dcc97254f828abee8e530` |
| [Published GTK A1 portability patch](https://www.digiater.nl/openvms/decus/vmslt03a/vu/gtk1210-a1_patch.tar) | `a51b249b10556a81f8da67d0ac25f073f561b713f82b41a21b201000a9add6dc` |

The GTK archive includes its matching GLib sources and native build files.
Apply the [VMS file-picker and system-header patches](patches/README.md) to the original
GTK download before transfer. The kit's corresponding-source archive already
contains the patched GTK tree.
The OPL PCSI kit contains the runtime; the separate source archive supplies
`VMS_JACKETS.H`, the DECwindows and pthread name mappings, and support headers.
The source archive is an Alpha self-extracting Info-ZIP archive. Native
extraction preserves OpenVMS record attributes. When extracting on another
host, some OPL text files retain variable-record lengths inside their bytes;
convert those records explicitly before marking the resulting files STMLF.
Do not treat the embedded record-length words as C or DCL source text.

GTK and GLib carry GNU Library GPL version 2 or later notices. Most OPL
sources carry Compaq's permission to use, modify and distribute with notices
retained and modifications identified; individual components have their own
notices. XMMS's original source and applicable component licenses remain in
this repository. MMOV headers and libraries are supplied by the user's MMOV
installation and are not included here.

## Prepare the native directories

Example layout on an ODS-5 work disk:

```text
DKA100:[XMMS]          this repository
DKA100:[GTK1210]       contents of gtk1210-openvms-a1.zip
DKA100:[OPL]           extracted OPL source and VMS_JACKETS.EXE
```

Use native UnZip/self-extraction, or a transfer that preserves every filename
and converts text record formats correctly. Names such as `I18N.H.IN` need
extended filename syntax (`I18N^.H.IN`) in DCL. C/H/COM source transferred as
plain text should have stream-LF records. Preserve binary files as binary.
`BUILD.COM` saves the caller's DCL parse style, enables extended parsing for
the source filenames, and restores the original style when it returns.

Obtain `VMS_JACKETS.EXE` through the native OPL PCSI kit, either by installing
OPL in the build environment or extracting the runtime into a private
directory with `PRODUCT EXTRACT FILE`. Inspect `PRODUCT LIST OPL` first for
its exact material pathname. If OPL is already installed, use the existing
`SYS$SHARE:VMS_JACKETS.EXE`. A private extraction avoids changing system files;
pass its full specification as the third build argument.

The MMOV **DEVELOPMENT** option is needed for compilation, even though it is
not required for ordinary MMOV playback. It supplies `SYS$LIBRARY:MMOV.OLB`
and the headers reached through `MMOV$INCLUDE` (normally
`SYS$COMMON:[MMOV_INCLUDES]`). Verify that `MMOV$INCLUDE:MME_API.H` exists.
The build defines the process logical `MME` to this directory for
`#include <mme/mme_api.h>`. Its link also uses the installed `IPC$SHARE`,
`CMA$OPEN_RTL`, `PTHREAD$RTL` and DECwindows shareable images.

## Build and launch

From the copied XMMS tree, for a privately extracted OPL runtime:

```text
$ @[.VMS]BUILD_GTK DKA100:[GTK1210] DKA100:[OPL] DKA100:[OPL]VMS_JACKETS.EXE
$ @[.VMS]BUILD     DKA100:[GTK1210] DKA100:[OPL] DKA100:[OPL]VMS_JACKETS.EXE
```

Omit the third argument when using `SYS$SHARE:VMS_JACKETS.EXE`. The GTK build
configures only its dependency tree. It uses the archive's generated enum
and marshal files, applies the published DECwindows `X11/shape.h` include
correction, and supplies the POSIX thread result conventions. A compiler
preinclude reads current CRTL declarations before the older OPL name mappings.
Compiler and linker failures are returned to the caller. The link wrapper
retains diagnostics and permits only `LINK-W-WRNERS`, which repeats compiler
warnings already visible in the build; unresolved or multiply defined symbols
still fail. The player uses `/MAIN=POSIX_EXIT` so Unix-style failures become
failing VMS statuses. Generated objects and the XMMS
image go under `[XMMS.VMS_BUILD]`.

The executable must link with `/THREADS_ENABLE=UPCALLS`, supplied by
`BUILD_LINK.COM`. This allows the OpenVMS thread scheduler to handle a
thread waiting in a blocking system call. Alpha's default disables upcalls;
see the [VSI linker documentation](https://docs.vmssoftware.com/vsi-openvms-linker-utility-manual/).
A native comparison using identical compiled objects changed only this flag:
MP3 playback became continuous across a 204.6-second track, and the playlist
metadata thread and audio worker both joined during normal quit. The image
keeps kernel multithreading disabled (`MKTHREADS=0`); no system-wide thread
setting is changed. Do not omit this flag in a custom link procedure.

All components use 32-bit pointers, case-preserving shortened external names
and IEEE floating point, matching the native GTK and MMOV interfaces. Both
builds define `_DECC_SHORT_GID_T=1` before system headers because the OPL A9
runtime uses the legacy 49-byte `struct stat` with a 16-bit group ID. Current
CRTL defaults produce a 51-byte structure with shifted size and timestamp
fields, which is incompatible with that runtime. This switch is required
even when the compiler accepts the original source. The initial native image
statically registers WAV, MP3 and MMOV plugins. Unix
remote-control sockets and optional platform-specific plugins are excluded.

The VMS configuration reader uses the same OPL-translated text stream as the
writer. It does not use native `lstat` to size the file first: current CRTL
`lstat` does not apply OPL's legacy hidden-directory translation, so it can
report a missing `/.xmms/config` even when the jacketed stream opens the saved
`_XMMS` configuration. Reading the stream also avoids assuming that an RMS
physical byte count equals translated text length. Other platforms retain
the original reader.

Launch from a normal DECwindows DECterm with its existing display:

```text
$ @[.VMS]RUN "" DKA100:[GTK1210] DKA100:[OPL]VMS_JACKETS.EXE
$ @[.VMS]RUN "SYS$LOGIN:SONG.WAV" DKA100:[GTK1210] DKA100:[OPL]VMS_JACKETS.EXE
```

`RUN.COM` defines only process-local library locations and invokes XMMS.
It does not create a display, start a desktop session, modify login files,
or install system-wide logical names. MMOV must already be running.

The runtime PCSI kit installs `SYS$COMMON:[XMMS]XMMS.COM`, `XMMS.EXE`, and
private libraries under `[XMMS.LIB]`. After installation, launch with
`@SYS$COMMON:[XMMS]XMMS` (optionally followed by a quoted audio filename).
The same launcher detects this layout and needs no build-tree paths, compiler
or MMOV SDK. The corresponding-source archive accompanies the runtime kit.
