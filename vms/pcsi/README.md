# XMMS runtime PCSI kit

This packages the already-built native player as `XMMS AXPVMS XMMS V1.2-11`.
The target is VSI OpenVMS Alpha V8.4-2L2 with DECwindows Motif V1.7 and
MMOV V2.2. Native packaging, clean installation, playback and removal are
pending validation; source review alone is not a release qualification.

The native product registry confirms `VSI AXPVMS VMS V8.4-2L2`,
`VSI AXPVMS DWMOTIF V1.7-F` and `DEC AXPVMS MMOV V2.2`. The dependency
statements use these registered product names; `OPENVMS` is a separate
platform registration.

The runtime is self-contained apart from those system products. Its six
images are `XMMS.EXE`, `LIBGTK.EXE`, `LIBGDK.EXE`, `LIBGLIB.EXE`,
`LIBGMODULE.EXE` and `VMS_JACKETS.EXE`. GLib's thread object is linked into
XMMS. The normal DECwindows fonts and compiled-in skin supply the default
interface. No compiler, GTK SDK, MMOV SDK, GNV, Perl or Autoconf is needed
on the target system.

All installed files are PCSI-managed under `[XMMS]`, `[XMMS.LIB]` and
`[XMMS.LICENSES]`. The runner defines process-local image logicals. The kit
creates no accounts, system logicals, startup jobs, login changes or desktop
customizations. PCSI handles installation, upgrade and removal of these
files. Close XMMS before removal; personal playlists and settings are kept.

## Build the kit

First complete the native builds described in [../DEPENDENCIES.md](../DEPENDENCIES.md).
Prepare a ZIP containing the **corresponding source for these exact images**:

- The complete XMMS source tree, including these OpenVMS adaptations and build
  scripts, without `.git`, binary output, private tests or unrelated material.
- GTK/GLib sources and licenses used by the build, including any modified
  headers/build files and the applied SHAPE include fix.
- The original OPL source distribution with its component licenses/notices
  and build instructions for the bundled runtime.
- A record of the source revisions/archive checksums and build changes.

Create the companion outside all three source roots with the supplied host
helper, after the sources used by the native build are frozen:

```text
python vms/pcsi/package_source.py --xmms-root REPO --gtk-root EXACT_PATCHED_GTK --opl-root NORMALIZED_OPL --output NEW_EXTERNAL.zip
```

The helper requires explicit source roots, rejects an existing output,
excludes build products and private material, records per-file SHA-256,
and reads every ZIP member back. It also verifies that the inputs did not
change during packaging. OPL text must already have its native variable
records decoded when preparing sources on a non-VMS host. This Python tool
is only for preparing the source companion; target installation uses PCSI.

The source companion must not contain MMOV SDK headers, libraries or other
proprietary system development files. Those remain external build dependencies.
Supply the companion alongside the binary kit when distributing the release.
The builder records its MD5 in the installed `SOURCE_INFO.TXT`; record SHA-256
for both final artifacts in the release manifest as well. A companion's name
and checksum do not by themselves prove its source is complete: inspect it
against the final native build before release.

For example, using an existing work directory on an ODS-5 work disk:

```text
$ CREATE/DIRECTORY DKA100:[XMMS_KIT]
$ @[.VMS.PCSI]BUILD_KIT DKA100:[XMMS_KIT] DKA100:[GTK1210] -
  DKA100:[OPL]VMS_JACKETS.EXE DKA100:[SOURCE]XMMS_SOURCE.ZIP DKA100:[OPL]
```

`P1` is the work directory; `P2` the GTK build root; `P3` the OPL runtime;
`P4` the exact corresponding-source ZIP; and `P5` the OPL source directory
containing its original `LICENSE.TXT` and `GNU_PUBLIC_LICENSE.TXT`. Use native
OPL self-extraction or explicitly decoded text records, as described in the
dependency notes. Native executable record attributes must be preserved.

The builder refuses existing `MATERIAL`, `OUTPUT` or `VERIFY` subdirectories
under P1. It preserves failed staging for diagnosis and never deletes files.
Use a new work directory for another attempt. It:

1. Copies the built images, runner and notices into a material tree, checking
   each copy's MD5, EOF and RMS record attributes.
2. Copies the source companion into `OUTPUT` and writes source provenance.
3. Runs `PRODUCT PACKAGE` using the original PDF/PTF and a root-form material
   path, creating `XMMS-AXPVMS-XMMS-V0102-11-1.PCSI`.
4. Uses `PRODUCT COPY /FORMAT=REFERENCE` to reconstruct the kit and compares
   every staged payload with the re-extracted material.

Both the `.PCSI` and `XMMS-SOURCE-V1_2_11.ZIP` are in `P1`'s `OUTPUT`
subdirectory. The source companion is distributed beside the kit; it is not
installed on the system disk. No compiled/proprietary artifacts belong in
this source repository.

## Install on the clean target

Supply the previously validated, separately licensed MMOV compatibility kit
alongside the XMMS kit. For the emulated ES1371, use the patched full native
`DEC-AXPVMS-MMOV-V0202--1.PCSI`, not an unmodified old driver. The PDF declares
MMOV as a PCSI dependency, so a missing MMOV product can be installed from the
same source directory. PCSI checks its registered product/version, not the
private compatibility changes; use the release manifest to select that kit.

```text
$ PRODUCT INSTALL XMMS /PRODUCER=XMMS /BASE_SYSTEM=AXPVMS -
  /SOURCE=DKA100:[KITS]
$ @SYS$STARTUP:MMOV$STARTUP.COM
```

Use MMOV's normal documented startup/shutdown hooks for subsequent boots.
When MMOV is already installed and running, do not start a second server.
No MMOV files are embedded in the XMMS product. The multimedia entitlement
and device configuration remain MMOV's responsibility.

From a normal DECwindows DECterm:

```text
$ @SYS$COMMON:[XMMS]XMMS.COM
$ @SYS$COMMON:[XMMS]XMMS.COM "SYS$LOGIN:SONG.WAV"
```

For a nondefault PCSI `/DESTINATION`, use that root's `[XMMS]` directory.
The installed command procedure finds its libraries relative to itself.
Installation's IVP invokes `--version`: it checks image activation and the
initial runtime path without opening a display or playing audio. PCSI leaves
a product installed if its IVP fails, so an IVP error is a failed validation,
not proof that installation rolled back.

Release qualification must install onto an isolated clean base, run the
version check with build/development logicals absent, launch on the ordinary
DECwindows display, play WAV and MP3, verify pause/seek/stop/volume, and remove
XMMS with `PRODUCT REMOVE XMMS /PRODUCER=XMMS /BASE_SYSTEM=AXPVMS`. Confirm that
PCSI-owned XMMS files are removed and the separate system products remain.

References: [VSI PCSI manual](https://docs.vmssoftware.com/vsi-openvms-polycenter-software-installation-utility-manual/),
[PRODUCT command reference](https://docs.vmssoftware.com/vsi-openvms-system-management-utilities-reference-manual-volume-ii-m-z/).
