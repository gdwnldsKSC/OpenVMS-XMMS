$! Build the public gtk1210-openvms-a1 source port for the current CRTL.
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
$ build_root = gd + gr
$ gr = gd + f$extract(0,f$length(gr)-1,gr) + ".]"
$ define/nolog/translation=concealed GROOT 'gr'
$! Slash-prefixed include names map to device logicals in VSI C.
$ define/process/nolog GDK GROOT:[GTK.GDK]
$ define/process/nolog GTK GROOT:[GTK.GTK]
$ define/nolog GROOTU "/GROOT"
$ define/nolog VJID 'p2'
$ define/nolog VJIDU "/VJID"
$ define/nolog VMS_JACKETS 'p3'
$ if f$search("GROOT:[GLIB]VMS_BUILD.COM") .eqs. "" then goto missing
$ if f$search("VJID:VMS_JACKETS.H") .eqs. "" then goto missing
$ if f$search("VMS_JACKETS") .eqs. "" then goto missing
$ set default 'build_root'
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
$ copy 'here'GTK_BUILD_CONFIG.H []VMS_BUILD_CONFIG.H
$ copy 'here'VMS_CRTL.H []VMS_CRTL.H
$! Published gtk1210-a1 patch: DECwindows keeps SHAPE.H directly in X11.
$! Apply once in this dependency build tree, keeping the preceding file version.
$ set noon
$ search/output=NL: GROOT:[GTK.GDK]GDKWINDOW.C "X11/extensions/shape.h"
$ shape_status = $status
$ set on
$ on error then goto failed
$ if shape_status .and. 1
$ then
$   call patch_shape
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
$ patch_shape: subroutine
$ on error then goto patch_failed
$ on control_y then goto patch_interrupted
$ old_include = "X11/extensions/shape.h"
$ new_include = "X11/shape.h"
$ open/read gtk_source GROOT:[GTK.GDK]GDKWINDOW.C
$ open/write gtk_fixed GROOT:[GTK.GDK]GDKWINDOW.C
$ patch_next:
$ read/end=patch_done gtk_source line
$ pos = f$locate(old_include,line)
$ if pos .lt. f$length(line)
$ then
$   write gtk_fixed "/* OpenVMS-XMMS 2026-11-09: published DECwindows SHAPE include fix. */"
$   line = f$extract(0,pos,line) + new_include + -
      f$extract(pos+f$length(old_include),f$length(line),line)
$ endif
$ write gtk_fixed line
$ goto patch_next
$ patch_done:
$ close gtk_source
$ close gtk_fixed
$ exit 1
$ patch_interrupted:
$ patch_status = %x0000002c
$ goto patch_cleanup
$ patch_failed:
$ patch_status = $status
$ patch_cleanup:
$ if f$trnlnm("GTK_SOURCE") .nes. "" then close gtk_source
$ if f$trnlnm("GTK_FIXED") .nes. "" then close gtk_fixed
$ exit 'patch_status'
$ endsubroutine
