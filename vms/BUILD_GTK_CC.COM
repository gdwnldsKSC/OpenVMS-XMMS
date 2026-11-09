$! Compiler for the native GTK 1.2.10 port. Installed into its build tree.
$ defs = "HAVE_CONFIG_H,VMS_AS_IS,USE_XIM,GTK_NO_CHECK_CASTS"
$ defs = defs + ",GENERIC_MOTIF_REDEFINES,GENERIC_PTHREAD_REDEFINES"
$ defs = defs + ",HAVE_PTHREAD_COND_TIMEDWAIT_POSIX,HAVE_PTHREAD_MUTEX_TRYLOCK_POSIX"
$ unit = f$edit(srcdir,"UPCASE")
$ if unit .eqs. "GLIB" then defs = defs + ",XMMS_GTK_GLIB"
$ if unit .eqs. "GLIB.GMODULE" then defs = defs + ",XMMS_GTK_GMODULE"
$ if unit .eqs. "GLIB.GTHREAD" then defs = defs + ",XMMS_GTK_GTHREAD"
$ if unit .eqs. "GTK.GDK" then defs = defs + ",XMMS_GTK_GDK"
$ if unit .eqs. "GTK.GTK" then defs = defs + ",XMMS_GTK_GTK"
$! Native lists avoid nested quotation marks in the original Unix-style lists.
$ includes = "GROOT:[''srcdir'],GROOT:[GLIB],VJID:"
$ if unit .eqs. "GTK.GDK" .or. unit .eqs. "GTK.GTK" then -
    includes = "GROOT:[''srcdir'],GROOT:[GTK],GROOT:[GLIB],GROOT:[GLIB.GMODULE],VJID:"
$ fullname = "GROOT:[''srcdir']''p1'"
$ obj = f$parse(fullname,,,"DEVICE") + f$parse(fullname,,,"DIRECTORY") + f$parse(fullname,,,"NAME")
$ on error then goto failed
$ write sys$output "CC ''fullname'"
$! Changing filespec resets stream 8 before each version lookup.
$ search_reset = f$search(fullname,8)
$ old_object = f$search(obj + ".OBJ",8)
$ cc /prefix=all /names=(as_is,shorten)/pointer_size=32 -
    /float=ieee/ieee=denorm/reentrancy=multithread -
    /warn=disable=(PTRMISMATCH,PTRMISMATCH1,QUESTCOMPARE,MACROREDEF) -
    /object='obj' /define=('defs') /include=('includes') -
    NL:'p1'+GROOT:[000000]VMS_CRTL.H+VJID:VMS_JACKETS.H+-
    GROOT:[000000]VMS_BUILD_CONFIG.H+'fullname'
$ cc_status = $status
$ search_reset = f$search(fullname,8)
$ new_object = f$search(obj + ".OBJ",8)
$ if new_object .eqs. "" .or. new_object .eqs. old_object
$ then
$   write sys$error "CC produced no new object: ",fullname," STATUS=",f$fao("!8XL",cc_status)
$   exit %x0000002c
$ endif
$! Compiler warnings are acceptable only when a fresh object was produced.
$ exit 1
$ failed:
$ status = $status
$ exit 'status'
