$! Build the unmodified public gtk1210-openvms-a1 source port.
$! P1 = GTK tree (DKA100:[GTK1210]), P2 = OPL headers (DKA100:[OPL]),
$! P3 = OPL runtime (default SYS$SHARE:VMS_JACKETS.EXE).
$! Only this dependency build tree is configured; no system files are changed.
$! Pre-generated GTK enum/marshal files are supplied by the original archive.
$ on error then goto failed
$ on control_y then goto interrupted
$ old_default = f$environment("DEFAULT")
$ procedure = f$environment("PROCEDURE")
$ here = f$parse(procedure,,,"DEVICE") + f$parse(procedure,,,"DIRECTORY")
$ if p1 .eqs. "" then p1 = "DKA100:[GTK1210]"
$ if p2 .eqs. "" then p2 = "DKA100:[OPL]"
$ if p3 .eqs. "" then p3 = "SYS$SHARE:VMS_JACKETS.EXE"
$ gd = f$parse(p1,,,"DEVICE")
$ gr = f$parse(p1,,,"DIRECTORY")
$ gr = gd + f$extract(0,f$length(gr)-1,gr) + ".]"
$ define/nolog/translation=concealed GROOT 'gr'
$ define/nolog GROOTU "/GROOT"
$ define/nolog VJID 'p2'
$ define/nolog VJIDU "/VJID"
$ define/nolog VMS_JACKETS 'p3'
$ if f$search("GROOT:[GLIB]VMS_BUILD.COM") .eqs. "" then goto missing
$ if f$search("VJID:VMS_JACKETS.H") .eqs. "" then goto missing
$ if f$search("VMS_JACKETS") .eqs. "" then goto missing
$ set default GROOT:[000000]
$ open/write setup VMS_BUILD_SETUP.COM
$ write setup "$! Configured by XMMS BUILD_GTK.COM; original source license unchanged."
$ write setup "$ vms_cc == ""@GROOT:[000000]VMS_CC.COM"""
$ write setup "$ vms_share == ""@GROOT:[000000]VMS_SHARE.COM"""
$ write setup "$ vms_link == ""@GROOT:[000000]VMS_LINK.COM"""
$ write setup "$ vms_module_ver == ""1.2.10"""
$ write setup "$ exit 1"
$ close setup
$ copy 'here'BUILD_GTK_CC.COM []VMS_CC.COM
$ copy 'here'BUILD_GTK_SHARE.COM []VMS_SHARE.COM
$! Published gtk1210-a1 patch: DECwindows keeps SHAPE.H directly in X11.
$! Apply once in this dependency build tree, keeping the preceding file version.
$ set noon
$ search/output=NL: GROOT:[GTK.GDK]GDKWINDOW.C "X11/extensions/shape.h"
$ shape_status = $status
$ set on
$ on error then goto failed
$ if shape_status .and. 1
$ then
$   edit/edt/command=SYS$INPUT GROOT:[GTK.GDK]GDKWINDOW.C
s%X11/extensions/shape.h%X11/shape.h%w/notype
exit
$ endif
$! Skip POSIX configure helper generation; native compilation needs only headers.
$ copy [.GLIB]CONFIG.H_VMS [.GLIB]CONFIG.H
$ copy [.GLIB]GLIBCONFIG.H_VMS [.GLIB]GLIBCONFIG.H
$ set default GROOT:[GLIB]
$ @VMS_BUILD.COM GLIB
$ set default GROOT:[GTK]
$ copy CONFIG.H_VMS CONFIG.H
$ set default [.GDK]
$ @VMS_BUILD.COM
$ set default [-.GTK]
$ @VMS_BUILD.COM COMPILE
$ define/nolog LIBGLIB GROOT:[GLIB]LIBGLIB.EXE
$ define/nolog LIBGMODULE GROOT:[GLIB.GMODULE]LIBGMODULE.EXE
$ define/nolog LIBGDK GROOT:[GTK.GDK]LIBGDK.EXE
$ define/nolog LIBGTK GROOT:[GTK.GTK]LIBGTK.EXE
$ write sys$output "GTK native build complete; GROOT, LIBGLIB, LIBGMODULE, LIBGDK and LIBGTK defined."
$ set default 'old_default'
$ exit 1
$ missing:
$ write sys$error "Missing GTK source, OPL headers or OPL runtime. Check P1/P2/P3."
$ status = %x0000002c
$ goto cleanup
$ interrupted:
$ status = %x0000002c
$ goto cleanup
$ failed:
$ status = $status
$ cleanup:
$ if f$trnlnm("SETUP") .nes. "" then close setup
$ set default 'old_default'
$ exit 'status'
