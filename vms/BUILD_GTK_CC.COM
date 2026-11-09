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
$ includes = "/include=(""./""," + vms_includes + ",""/VJID"")"
$ fullname = "GROOT:[''srcdir']''p1'"
$ obj = f$parse(fullname,,,"DEVICE") + f$parse(fullname,,,"DIRECTORY") + f$parse(fullname,,,"NAME")
$ on error then goto failed
$ write sys$output "CC ''fullname'"
$ cc /prefix=all /names=(as_is,shorten)/pointer_size=32 -
    /float=ieee/ieee=denorm/reentrancy=multithread -
    /warn=disable=(PTRMISMATCH,PTRMISMATCH1,QUESTCOMPARE,MACROREDEF) -
    /object='obj' /define=('defs') 'includes' -
    NL:'p1'+GROOT:[000000]VMS_CRTL.H+VJID:VMS_JACKETS.H+-
    GROOT:[000000]VMS_BUILD_CONFIG.H+'fullname'
$ exit 1
$ failed:
$ status = $status
$ exit 'status'
