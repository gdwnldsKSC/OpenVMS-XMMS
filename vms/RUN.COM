$! Launch XMMS from an existing DECwindows session.
$! P1 = optional audio file; P2 = GTK build root; P3 = OPL runtime image.
$! With no P2/P3, use existing process logicals or the build defaults.
$ on error then goto failed
$ procedure = f$environment("PROCEDURE")
$ here = f$parse(procedure,,,"DEVICE") + f$parse(procedure,,,"DIRECTORY")
$ rootdev = f$parse("[-]",here,,"DEVICE")
$ rootdir = f$parse("[-]",here,,"DIRECTORY")
$ root = rootdev + f$extract(0,f$length(rootdir)-1,rootdir) + ".]"
$ define/process/nolog/translation=concealed XMMS_ROOT 'root'
$ if p2 .eqs. "" .and. f$trnlnm("GROOT") .eqs. "" then p2 = "DKA100:[GTK1210]"
$ if p2 .nes. ""
$ then
$   gd = f$parse(p2,,,"DEVICE")
$   gr = f$parse(p2,,,"DIRECTORY")
$   gr = gd + f$extract(0,f$length(gr)-1,gr) + ".]"
$   define/process/nolog/translation=concealed GROOT 'gr'
$ endif
$ if p3 .eqs. "" .and. f$trnlnm("VMS_JACKETS") .eqs. "" then p3 = "SYS$SHARE:VMS_JACKETS.EXE"
$ if p3 .nes. "" then define/process/nolog VMS_JACKETS 'p3'
$ define/process/nolog LIBGLIB GROOT:[GLIB]LIBGLIB.EXE
$ define/process/nolog LIBGMODULE GROOT:[GLIB.GMODULE]LIBGMODULE.EXE
$ define/process/nolog LIBGDK GROOT:[GTK.GDK]LIBGDK.EXE
$ define/process/nolog LIBGTK GROOT:[GTK.GTK]LIBGTK.EXE
$ if f$search("XMMS_ROOT:[VMS_BUILD]XMMS.EXE") .eqs. "" then goto missing
$ if f$search("LIBGTK") .eqs. "" then goto missing
$ if f$search("VMS_JACKETS") .eqs. "" then goto missing
$ if p1 .eqs. ""
$ then
$   mcr XMMS_ROOT:[VMS_BUILD]XMMS.EXE
$ else
$   mcr XMMS_ROOT:[VMS_BUILD]XMMS.EXE "''p1'"
$ endif
$ exit $status
$ missing:
$ write sys$error "XMMS, GTK or OPL runtime not found. Check build and RUN arguments."
$ exit %x0000002c
$ failed:
$ status = $status
$ exit 'status'
