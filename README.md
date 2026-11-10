# XMMS for OpenVMS Alpha

A native port of classic XMMS 1.2.11 to OpenVMS Alpha, using GTK+ 1.2 for the
DECwindows interface and Multimedia Services for OpenVMS (MMOV) for sound.
The immediate target is a working desktop music player on OpenVMS V8.4-2L2.

**Status:** GTK and XMMS compile and link natively on OpenVMS Alpha
V8.4-2L2 with VSI C V7.4-002. The executable reports version 1.2.11 and
opens its DECwindows player window. Native WAV and full-track MP3 playback
are continuous, the file picker and playlist work, normal quit completes,
and saved settings survive a restart. The Alpha executable must enable
thread upcalls, as the supplied linker procedure does. Consult the release
validation report for detailed runtime, package installation, removal and
installed-runtime results.

R1 adds a shared-colormap policy for 8-bit PseudoColor DECwindows desktops.
It uses shared colors and approximation when necessary, keeping XMMS's RGB
rendering and window palette consistent. Builds must include the matching
[GTK patch](vms/patches/README.md); palette qualification results belong in
the release validation report.

The first build includes the original MP3 and WAV decoders and links them
with the MMOV output plugin. It keeps the player, playlist, equalizer, and
built-in visual display. It does not require a Unix shell or an autotools
installation on VMS.

## Native installation

The [PCSI build and installation instructions](vms/pcsi/README.md) describe
the runtime kit. It installs under `SYS$COMMON:[XMMS]` and includes private
GTK, GLib and OPL runtime libraries. The target system needs DECwindows and
a working, licensed MMOV installation; no compiler or SDK is needed to run
the installed player.

Launch it from an ordinary DECwindows session:

```text
$ @SYS$COMMON:[XMMS]XMMS.COM
```

The launcher defines its library logical names only in the calling process.
It does not replace the desktop session or change system startup files.

## Building

See [dependency instructions](vms/DEPENDENCIES.md). The build needs the native
GTK+ 1.2.10 port, OpenVMS Porting Library headers/runtime, VSI or Compaq C,
DECwindows development files, and the MMOV development headers/library.
These third-party dependencies are installed separately.

From the source root on an ODS-5 build volume:

```text
$ @[.VMS]BUILD_GTK DKA100:[GTK1210] DKA100:[OPL]
$ @[.VMS]BUILD DKA100:[GTK1210] DKA100:[OPL]
```

The native build writes objects and `XMMS.EXE` under `[.VMS_BUILD]`. Start the
player from an ordinary DECwindows session using the launch procedure in
`[.VMS]`; no alternate desktop session or system startup change is needed.

## Initial desktop scope

- MP3 and WAV files, playlists, playback, seeking, pause, and volume through MMOV.
- The embedded skin and unpacked skin directories; extract ZIP/WSZ skins first.
- Startup file arguments act on the newly opened player.
- Unix remote-session commands and dynamically loaded third-party plugins are
  excluded from this initial native build.

## Source and license

[Upstream provenance](vms/UPSTREAM.md) records the release archive and checksum.
The original XMMS documentation remains in [README](README).
XMMS is distributed under the GNU GPL version 2 or later; retain [COPYING](COPYING)
and the copyright/license notices in individual files.

No proprietary SDK files, guest images, firmware, license keys, or music are
included in this repository.
