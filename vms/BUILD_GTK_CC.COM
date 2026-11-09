$! Compiler for the native GTK 1.2.10 port. Installed into its build tree.
$ defs = "HAVE_CONFIG_H,VMS_AS_IS,USE_XIM,GTK_NO_CHECK_CASTS"
$ defs = defs + ",GENERIC_MOTIF_REDEFINES,GENERIC_PTHREAD_REDEFINES"
$ defs = defs + ",HAVE_PTHREAD_COND_TIMEDWAIT_POSIX,HAVE_PTHREAD_MUTEX_TRYLOCK_POSIX"
$ if vms_defines .nes. "" then defs = defs + "," + vms_defines
$ includes = "/include=(""./""," + vms_includes + ",""/VJID"")"
$ fullname = "GROOT:[''srcdir']''p1'"
$ obj = f$parse(fullname,,,"DEVICE") + f$parse(fullname,,,"DIRECTORY") + f$parse(fullname,,,"NAME")
$ on error then goto failed
$ write sys$output "CC ''fullname'"
$ cc /prefix=all /names=(as_is,shorten)/pointer_size=32 -
    /float=ieee/ieee=denorm/reentrancy=multithread -
    /warn=disable=(PTRMISMATCH,PTRMISMATCH1,QUESTCOMPARE,MACROREDEF) -
    /object='obj' /define=('defs') 'includes' -
    NL:'p1'+VJID:VMS_JACKETS.H+'fullname'
$ exit 1
$ failed:
$ status = $status
$ exit 'status'
