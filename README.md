# XMMS for OpenVMS Alpha

A native port of classic XMMS 1.2.11 to OpenVMS Alpha, using GTK+ 1.2 for the
DECwindows interface and Multimedia Services for OpenVMS (MMOV) for sound.
The immediate target is a working desktop music player on OpenVMS V8.4-2L2.

**Status:** implementation and native build verification are in progress.
The MMOV backend has passed private host-side behavior checks; this is not
yet evidence of a working Alpha executable or audible native playback.

The first build includes the original MP3 and WAV decoders and links them
with the MMOV output plugin. It keeps the player, playlist, equalizer, and
built-in visual display. It does not require a Unix shell or an autotools
installation on VMS.

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
