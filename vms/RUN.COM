$! Launch XMMS from an existing DECwindows session.
$! P1 = optional audio file or help/version flag; P2 GTK root; P3 OPL image.
$! Installed as [XMMS]XMMS.COM beside XMMS.EXE and [.LIB] runtime libraries.
$! Also works as [source.VMS]RUN.COM with [source.VMS_BUILD]XMMS.EXE.
$! All logical names are process-local. The existing display is unchanged.
$ on error then goto failed
$! Expand concealed roots, then collapse RMS split directory boundaries before
$! defining our own root. A root's [000000] names that root, not a child directory.
$ procedure = f$parse(f$environment("PROCEDURE"),,,,"NO_CONCEAL")
$ here_device = f$parse(procedure,,,"DEVICE")
$ here_directory = f$parse(procedure,,,"DIRECTORY")
$ normalize_root:
$ boundary = f$locate(".][",here_directory)
$ if boundary .eq. f$length(here_directory) then goto root_normalized
$ root_prefix = f$extract(0,boundary,here_directory)
$ root_suffix = f$extract(boundary+3,f$length(here_directory),here_directory)
$ root_separator = "."
$ if f$extract(0,7,root_suffix) .eqs. "000000]"
$ then
$   root_suffix = f$extract(6,f$length(root_suffix),root_suffix)
$   root_separator = ""
$ else
$   if f$extract(0,7,root_suffix) .eqs. "000000." then -
        root_suffix = f$extract(7,f$length(root_suffix),root_suffix)
$ endif
$ here_directory = root_prefix + root_separator + root_suffix
$ goto normalize_root
$ root_normalized:
$ here = here_device + here_directory
$ installed = f$search(here + "XMMS.EXE") .nes. ""
$ if installed
$ then
$   rootdev = f$parse(here,,,"DEVICE")
$   rootdir = f$parse(here,,,"DIRECTORY")
$ else
$   rootdev = f$parse(here,,,"DEVICE")
$   rootdir = f$parse(here,,,"DIRECTORY")
$   rootlen = f$length(rootdir)
$   if rootlen .lt. 6 then goto bad_source_location
$   suffix = f$edit(f$extract(rootlen-5,5,rootdir),"UPCASE")
$   if suffix .nes. ".VMS]" then goto bad_source_location
$   rootdir = f$extract(0,rootlen-5,rootdir) + "]"
$ endif
$ root = rootdev + f$extract(0,f$length(rootdir)-1,rootdir) + ".]"
$ define/process/nolog/translation=concealed XMMS_ROOT 'root'
$ if installed
$ then
$   image = "XMMS_ROOT:[000000]XMMS.EXE"
$ else
$   image = "XMMS_ROOT:[VMS_BUILD]XMMS.EXE"
$ endif
$ private_libs = installed .and. p2 .eqs. ""
$ if private_libs
$ then
$   define/process/nolog LIBGLIB XMMS_ROOT:[LIB]LIBGLIB.EXE
$   define/process/nolog LIBGMODULE XMMS_ROOT:[LIB]LIBGMODULE.EXE
$   define/process/nolog LIBGDK XMMS_ROOT:[LIB]LIBGDK.EXE
$   define/process/nolog LIBGTK XMMS_ROOT:[LIB]LIBGTK.EXE
$ else
$   if p2 .eqs. "" .and. f$trnlnm("GROOT") .eqs. "" then p2 = "DKA100:[GTK1210]"
$   if p2 .nes. ""
$   then
$     gd = f$parse(p2,,,"DEVICE")
$     gr = f$parse(p2,,,"DIRECTORY")
$     gr = gd + f$extract(0,f$length(gr)-1,gr) + ".]"
$     define/process/nolog/translation=concealed GROOT 'gr'
$   endif
$   define/process/nolog LIBGLIB GROOT:[GLIB]LIBGLIB.EXE
$   define/process/nolog LIBGMODULE GROOT:[GLIB.GMODULE]LIBGMODULE.EXE
$   define/process/nolog LIBGDK GROOT:[GTK.GDK]LIBGDK.EXE
$   define/process/nolog LIBGTK GROOT:[GTK.GTK]LIBGTK.EXE
$ endif
$ if p3 .eqs. "" .and. installed then p3 = "XMMS_ROOT:[LIB]VMS_JACKETS.EXE"
$ if p3 .eqs. "" .and. f$trnlnm("VMS_JACKETS") .eqs. "" then p3 = "SYS$SHARE:VMS_JACKETS.EXE"
$ if p3 .nes. "" then define/process/nolog VMS_JACKETS 'p3'
$ if f$search(image) .eqs. "" then goto missing
$ if f$search("LIBGTK") .eqs. "" then goto missing
$ if f$search("VMS_JACKETS") .eqs. "" then goto missing
$! DCL uppercases unquoted parameters. Normalize only these known switches;
$! preserve the spelling and case of every filename argument.
$ flag = f$edit(p1,"UPCASE")
$ if flag .eqs. "--VERSION" .or. flag .eqs. "-V" .or. -
     flag .eqs. "--HELP" .or. flag .eqs. "-H" then p1 = f$edit(p1,"LOWERCASE")
$ if p1 .eqs. ""
$ then
$   mcr 'image'
$ else
$   mcr 'image' "''p1'"
$ endif
$ exit $status
$ bad_source_location:
$ write sys$error "Keep RUN.COM in the source VMS directory, or install it beside XMMS.EXE."
$ exit %x0000002c
$ missing:
$ write sys$error "XMMS, GTK or OPL runtime not found. Check installation or RUN arguments."
$ exit %x0000002c
$ failed:
$ status = $status
$ exit 'status'
