$! Native XMMS 1.2.11 build; invoke from any directory.
$! P1 = native GTK source/build root, e.g. DKA100:[GTK1210]
$! P2 = OpenVMS Porting Library header directory, e.g. DKA100:[OPL]
$! P3 = VMS_JACKETS.EXE specification (optional: SYS$SHARE:VMS_JACKETS.EXE)
$! GTK must already have been built with BUILD_GTK.COM; MMOV development
$! headers and MMOV.OLB must be installed. No installation is performed here.
$ on error then goto failed
$ on control_y then goto interrupted
$ old_default = f$environment("DEFAULT")
$ old_parse = f$getjpi("","PARSE_STYLE_PERM")
$ set process/parse_style=extended
$ procedure = f$environment("PROCEDURE")
$ here = f$parse(procedure,,,"DEVICE") + f$parse(procedure,,,"DIRECTORY")
$ rootdev = f$parse("[-]",here,,"DEVICE")
$ rootdir = f$parse("[-]",here,,"DIRECTORY")
$ source_default = rootdev + rootdir
$ root = rootdev + f$extract(0,f$length(rootdir)-1,rootdir) + ".]"
$ define/nolog/translation=concealed XMMS_ROOT 'root'
$ if p1 .eqs. "" then p1 = "DKA100:[GTK1210]"
$ if p2 .eqs. "" then p2 = "DKA100:[OPL]"
$ if p3 .eqs. "" then p3 = "SYS$SHARE:VMS_JACKETS.EXE"
$ gd = f$parse(p1,,,"DEVICE")
$ gr = f$parse(p1,,,"DIRECTORY")
$ gr = gd + f$extract(0,f$length(gr)-1,gr) + ".]"
$ define/nolog/translation=concealed GROOT 'gr'
$ define/nolog VJID 'p2'
$ define/nolog VMS_JACKETS 'p3'
$ define/nolog LIBGLIB GROOT:[GLIB]LIBGLIB.EXE
$ define/nolog LIBGMODULE GROOT:[GLIB.GMODULE]LIBGMODULE.EXE
$ define/nolog LIBGDK GROOT:[GTK.GDK]LIBGDK.EXE
$ define/nolog LIBGTK GROOT:[GTK.GTK]LIBGTK.EXE
$ define/nolog MME MMOV$INCLUDE
$ if f$search("VJID:VMS_JACKETS.H") .eqs. "" then goto missing
$ if f$search("VMS_JACKETS") .eqs. "" then goto missing
$ if f$search("LIBGTK") .eqs. "" then goto missing
$ if f$search("GROOT:[GLIB.GTHREAD]GTHREAD.OBJ") .eqs. "" then goto missing
$ if f$search("SYS$LIBRARY:MMOV.OLB") .eqs. "" then goto missing
$ set default 'source_default'
$ if f$search("VMS_BUILD.DIR") .eqs. "" then create/directory [.VMS_BUILD]
$ if f$search("[.VMS_BUILD]CORE.DIR") .eqs. "" then create/directory [.VMS_BUILD.CORE]
$ if f$search("[.VMS_BUILD]LIB.DIR") .eqs. "" then create/directory [.VMS_BUILD.LIB]
$ if f$search("[.VMS_BUILD]MPG.DIR") .eqs. "" then create/directory [.VMS_BUILD.MPG]
$ copy [.VMS]CONFIG.H []CONFIG.H
$ copy [.XMMS]I18N^.H.IN [.XMMS]I18N.H
$ defs = "HAVE_CONFIG_H,XMMS_STATIC_PLUGINS,VMS_AS_IS,GENERIC_MOTIF_REDEFINES,GENERIC_PTHREAD_REDEFINES"
$ includes = source_default + ",XMMS_ROOT:[XMMS],GROOT:[GTK],GROOT:[GLIB],GROOT:[GLIB.GMODULE],VJID:,MMOV$INCLUDE:"
$ ccflags = "/NAMES=(AS_IS,SHORTEN)/POINTER_SIZE=32/FLOAT=IEEE/IEEE=DENORM/REENTRANCY=MULTITHREAD/STANDARD=RELAXED_ANSI89/PREFIX=ALL/MAIN=POSIX_EXIT"
$ open/write options [.VMS_BUILD]XMMS.OPT
$ write options "CASE_SENSITIVE=YES"
$ call compile "[.XMMS]BMP.C" "[.VMS_BUILD.CORE]BMP.OBJ"
$ call compile "[.XMMS]SKIN.C" "[.VMS_BUILD.CORE]SKIN.OBJ"
$ call compile "[.XMMS]UTIL.C" "[.VMS_BUILD.CORE]UTIL.OBJ"
$ call compile "[.XMMS]OUTPUT.C" "[.VMS_BUILD.CORE]OUTPUT.OBJ"
$ call compile "[.XMMS]FFT.C" "[.VMS_BUILD.CORE]FFT.OBJ"
$ call compile "[.XMMS]INPUT.C" "[.VMS_BUILD.CORE]INPUT.OBJ"
$ call compile "[.XMMS]EFFECT.C" "[.VMS_BUILD.CORE]EFFECT.OBJ"
$ call compile "[.XMMS]GENERAL.C" "[.VMS_BUILD.CORE]GENERAL.OBJ"
$ call compile "[.XMMS]VISUALIZATION.C" "[.VMS_BUILD.CORE]VISUALIZATION.OBJ"
$ call compile "[.XMMS]FULLSCREEN.C" "[.VMS_BUILD.CORE]FULLSCREEN.OBJ"
$ call compile "[.XMMS]PLUGINENUM.C" "[.VMS_BUILD.CORE]PLUGINENUM.OBJ"
$ call compile "[.XMMS]PLAYLIST.C" "[.VMS_BUILD.CORE]PLAYLIST.OBJ"
$ call compile "[.XMMS]DOCK.C" "[.VMS_BUILD.CORE]DOCK.OBJ"
$ call compile "[.XMMS]WIDGET.C" "[.VMS_BUILD.CORE]WIDGET.OBJ"
$ call compile "[.XMMS]SBUTTON.C" "[.VMS_BUILD.CORE]SBUTTON.OBJ"
$ call compile "[.XMMS]PBUTTON.C" "[.VMS_BUILD.CORE]PBUTTON.OBJ"
$ call compile "[.XMMS]TBUTTON.C" "[.VMS_BUILD.CORE]TBUTTON.OBJ"
$ call compile "[.XMMS]TEXTBOX.C" "[.VMS_BUILD.CORE]TEXTBOX.OBJ"
$ call compile "[.XMMS]MENUROW.C" "[.VMS_BUILD.CORE]MENUROW.OBJ"
$ call compile "[.XMMS]HSLIDER.C" "[.VMS_BUILD.CORE]HSLIDER.OBJ"
$ call compile "[.XMMS]MONOSTEREO.C" "[.VMS_BUILD.CORE]MONOSTEREO.OBJ"
$ call compile "[.XMMS]VIS.C" "[.VMS_BUILD.CORE]VIS.OBJ"
$ call compile "[.XMMS]SVIS.C" "[.VMS_BUILD.CORE]SVIS.OBJ"
$ call compile "[.XMMS]NUMBER.C" "[.VMS_BUILD.CORE]NUMBER.OBJ"
$ call compile "[.XMMS]PLAYSTATUS.C" "[.VMS_BUILD.CORE]PLAYSTATUS.OBJ"
$ call compile "[.XMMS]PLAYLIST_LIST.C" "[.VMS_BUILD.CORE]PLAYLIST_LIST.OBJ"
$ call compile "[.XMMS]PLAYLIST_SLIDER.C" "[.VMS_BUILD.CORE]PLAYLIST_SLIDER.OBJ"
$ call compile "[.XMMS]PLAYLIST_POPUP.C" "[.VMS_BUILD.CORE]PLAYLIST_POPUP.OBJ"
$ call compile "[.XMMS]EQ_GRAPH.C" "[.VMS_BUILD.CORE]EQ_GRAPH.OBJ"
$ call compile "[.XMMS]EQ_SLIDER.C" "[.VMS_BUILD.CORE]EQ_SLIDER.OBJ"
$ call compile "[.XMMS]MAIN.C" "[.VMS_BUILD.CORE]MAIN.OBJ"
$ call compile "[.XMMS]SKINWIN.C" "[.VMS_BUILD.CORE]SKINWIN.OBJ"
$ call compile "[.XMMS]PREFSWIN.C" "[.VMS_BUILD.CORE]PREFSWIN.OBJ"
$ call compile "[.XMMS]PLAYLISTWIN.C" "[.VMS_BUILD.CORE]PLAYLISTWIN.OBJ"
$ call compile "[.XMMS]EQUALIZER.C" "[.VMS_BUILD.CORE]EQUALIZER.OBJ"
$ call compile "[.XMMS]HINTS.C" "[.VMS_BUILD.CORE]HINTS.OBJ"
$ call compile "[.XMMS]ABOUT.C" "[.VMS_BUILD.CORE]ABOUT.OBJ"
$ call compile "[.XMMS]SM.C" "[.VMS_BUILD.CORE]SM.OBJ"
$ call compile "[.XMMS]GETOPT.C" "[.VMS_BUILD.CORE]GETOPT.OBJ"
$ call compile "[.XMMS]GETOPT1.C" "[.VMS_BUILD.CORE]GETOPT1.OBJ"
$ call compile "[.XMMS]URLDECODE.C" "[.VMS_BUILD.CORE]URLDECODE.OBJ"
$ call compile "[.XMMS]MKDTEMP.C" "[.VMS_BUILD.CORE]MKDTEMP.OBJ"
$ call compile "[.LIBXMMS]CONFIGFILE.C" "[.VMS_BUILD.LIB]CONFIGFILE.OBJ"
$ call compile "[.LIBXMMS]DIRBROWSER.C" "[.VMS_BUILD.LIB]DIRBROWSER.OBJ"
$ call compile "[.LIBXMMS]UTIL.C" "[.VMS_BUILD.LIB]UTIL.OBJ"
$ call compile "[.LIBXMMS]FORMATTER.C" "[.VMS_BUILD.LIB]FORMATTER.OBJ"
$ call compile "[.LIBXMMS]TITLESTRING.C" "[.VMS_BUILD.LIB]TITLESTRING.OBJ"
$ call compile "[.LIBXMMS]XENTRY.C" "[.VMS_BUILD.LIB]XENTRY.OBJ"
$ call compile "[.LIBXMMS]XCONVERT.C" "[.VMS_BUILD.LIB]XCONVERT.OBJ"
$ call compile "[.LIBXMMS]CHARSET.C" "[.VMS_BUILD.LIB]CHARSET.OBJ"
$ call compile "[.INPUT.MPG123]MPG123.C" "[.VMS_BUILD.MPG]MPG123.OBJ"
$ call compile "[.INPUT.MPG123]COMMON.C" "[.VMS_BUILD.MPG]COMMON.OBJ"
$ call compile "[.INPUT.MPG123]TABINIT.C" "[.VMS_BUILD.MPG]TABINIT.OBJ"
$ call compile "[.INPUT.MPG123]CONFIGURE.C" "[.VMS_BUILD.MPG]CONFIGURE.OBJ"
$ call compile "[.INPUT.MPG123]FILEINFO.C" "[.VMS_BUILD.MPG]FILEINFO.OBJ"
$ call compile "[.INPUT.MPG123]DECODE_2TO1.C" "[.VMS_BUILD.MPG]DECODE_2TO1.OBJ"
$ call compile "[.INPUT.MPG123]DECODE_4TO1.C" "[.VMS_BUILD.MPG]DECODE_4TO1.OBJ"
$ call compile "[.INPUT.MPG123]LAYER1.C" "[.VMS_BUILD.MPG]LAYER1.OBJ"
$ call compile "[.INPUT.MPG123]LAYER2.C" "[.VMS_BUILD.MPG]LAYER2.OBJ"
$ call compile "[.INPUT.MPG123]LAYER3.C" "[.VMS_BUILD.MPG]LAYER3.OBJ"
$ call compile "[.INPUT.MPG123]EQUALIZER.C" "[.VMS_BUILD.MPG]EQUALIZER.OBJ"
$ call compile "[.INPUT.MPG123]HTTP.C" "[.VMS_BUILD.MPG]HTTP.OBJ"
$ call compile "[.INPUT.MPG123]DXHEAD.C" "[.VMS_BUILD.MPG]DXHEAD.OBJ"
$ call compile "[.INPUT.MPG123]ID3.C" "[.VMS_BUILD.MPG]ID3.OBJ"
$ call compile "[.INPUT.MPG123]ID3_FRAME.C" "[.VMS_BUILD.MPG]ID3_FRAME.OBJ"
$ call compile "[.INPUT.MPG123]ID3_FRAME_CONTENT.C" "[.VMS_BUILD.MPG]ID3_FRAME_CONTENT.OBJ"
$ call compile "[.INPUT.MPG123]ID3_FRAME_TEXT.C" "[.VMS_BUILD.MPG]ID3_FRAME_TEXT.OBJ"
$ call compile "[.INPUT.MPG123]ID3_FRAME_URL.C" "[.VMS_BUILD.MPG]ID3_FRAME_URL.OBJ"
$ call compile "[.INPUT.MPG123]ID3_TAG.C" "[.VMS_BUILD.MPG]ID3_TAG.OBJ"
$ call compile "[.INPUT.MPG123]UNICODE.C" "[.VMS_BUILD.MPG]UNICODE.OBJ"
$ call compile "[.INPUT.MPG123]DECODE.C" "[.VMS_BUILD.MPG]DECODE.OBJ"
$ call compile "[.INPUT.MPG123]DCT64.C" "[.VMS_BUILD.MPG]DCT64.OBJ"
$ call compile "[.INPUT.WAV]WAV.C" "[.VMS_BUILD]WAV.OBJ"
$ call compile "[.OUTPUT.MMOV]MMOV.C" "[.VMS_BUILD]MMOV.OBJ"
$ write options "GROOT:[GLIB.GTHREAD]GTHREAD.OBJ"
$ write options "GROOT:[GTK.GTK]LIBGTK.EXE/SHARE"
$ write options "GROOT:[GTK.GDK]LIBGDK.EXE/SHARE"
$ write options "GROOT:[GLIB.GMODULE]LIBGMODULE.EXE/SHARE"
$ write options "GROOT:[GLIB]LIBGLIB.EXE/SHARE"
$ write options "VMS_JACKETS/SHARE"
$ write options "SYS$LIBRARY:MMOV.OLB/LIBRARY"
$ write options "SYS$SHARE:IPC$SHARE.EXE/SHARE"
$ write options "SYS$SHARE:CMA$OPEN_RTL.EXE/SHARE"
$ write options "SYS$SHARE:PTHREAD$RTL.EXE/SHARE"
$ write options "SYS$SHARE:DECW$XLIBSHR.EXE/SHARE"
$ write options "SYS$SHARE:DECW$XEXTLIBSHR.EXE/SHARE"
$ close options
$ on warning then goto failed
$ link/executable=[.VMS_BUILD]XMMS.EXE/map=[.VMS_BUILD]XMMS.MAP -
    /full/traceback [.VMS_BUILD]XMMS.OPT/options
$ write sys$output "XMMS native build complete: XMMS_ROOT:[VMS_BUILD]XMMS.EXE"
$ set default 'old_default'
$ set process/parse_style='old_parse'
$ exit 1
$ compile: subroutine
$ on error then goto compile_failed
$ source_dir = f$parse(p1,,,"DEVICE") + f$parse(p1,,,"DIRECTORY")
$ module = f$parse(p1,,,"NAME")
$ write sys$output "CC ''p1'"
$ search_reset = f$search(p1,8)
$ old_object = f$search(p2,8)
$ cc 'ccflags' /define=('defs') /include=('source_dir','includes') -
    /object='p2' NL:'module'.C+XMMS_ROOT:[VMS]VMS_CRTL.H+VJID:VMS_JACKETS.H+'p1'
$ cc_status = $status
$ search_reset = f$search(p1,8)
$ new_object = f$search(p2,8)
$ if new_object .eqs. "" .or. new_object .eqs. old_object
$ then
$   write sys$error "No new object for ''p1'; CC status ",f$fao("!8XL",cc_status)
$   exit %x0000002c
$ endif
$ write options p2
$ exit 1
$ compile_failed:
$ compile_status = $status
$ exit 'compile_status'
$ endsubroutine
$ missing:
$ write sys$error "Missing GTK, OPL or MMOV development files. Check P1/P2/P3 and MMOV$INCLUDE."
$ status = %x0000002c
$ goto cleanup
$ interrupted:
$ status = %x0000002c
$ goto cleanup
$ failed:
$ status = $status
$ if (status .and. 7) .eq. 0 then status = %x0000002c
$ cleanup:
$ if f$trnlnm("OPTIONS") .nes. "" then close options
$ set default 'old_default'
$ set process/parse_style='old_parse'
$ exit 'status'
