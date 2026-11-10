$! Link XMMS while retaining the compiler-warning flags in upstream objects.
$! P1 options file, P2 executable, P3 map (optional).
$! Only LINK-W-WRNERS (previous compilation warnings) is accepted.
$! Undefined/multiple symbols and every other linker diagnostic still fail.
$ on warning then goto failed
$ on control_y then goto interrupted
$ log_open = 0
$ if p1 .eqs. "" .or. p2 .eqs. "" then goto bad_arguments
$ options_file = f$search(p1)
$ if options_file .eqs. "" then goto bad_arguments
$ image_base = f$parse(p2,,,"DEVICE") + f$parse(p2,,,"DIRECTORY") + f$parse(p2,,,"NAME")
$ if p3 .eqs. "" then p3 = image_base + ".MAP"
$ output_log = image_base + ".LINK_OUT"
$ error_log = image_base + ".LINK_ERR"
$ search_reset = f$search(options_file,8)
$ old_image = f$search(p2,8)
$ warning_count = 0
$ unexpected = 0
$! PIPE 2> appends; start a fresh empty version, also valid for quiet success.
$ open/write XMMS_LINK_EMPTY 'error_log'
$ close XMMS_LINK_EMPTY
$ set noon
$ pipe link/threads_enable=UPCALLS/executable='p2'/map='p3'/full/traceback 'options_file'/options -
    > 'output_log' 2> 'error_log'
$ link_status = f$integer($status)
$ set on
$ on warning then goto failed
$ severity = link_status .and. 7
$ log_file = f$search(output_log)
$ if log_file .eqs. "" then goto rejected
$ gosub inspect_log
$ log_file = f$search(error_log)
$ if log_file .eqs. "" then goto rejected
$ gosub inspect_log
$ if unexpected then goto rejected
$ if severity .ne. 0 .and. .not. (severity .and. 1) then goto rejected
$ if severity .eq. 0 .and. warning_count .eq. 0 then goto rejected
$ search_reset = f$search(options_file,8)
$ new_image = f$search(p2,8)
$ if new_image .eqs. "" .or. new_image .eqs. old_image then goto rejected
$ if f$file_attributes(new_image,"EOF") .le. 0 then goto rejected
$ write sys$output "XMMS_LINK_COMPLETE ",new_image," prior compiler warnings=",warning_count
$ exit 1
$ inspect_log:
$ open/read XMMS_LINK_LOG 'log_file'
$ log_open = 1
$ next_record:
$ read/end=end_log XMMS_LINK_LOG record
$ write sys$output record
$ text = f$edit(record,"UPCASE,TRIM")
$ if f$extract(0,1,text) .eqs. "%" .or. f$extract(0,1,text) .eqs. "-"
$ then
$   if f$extract(0,15,text) .eqs. "%LINK-W-WRNERS,"
$   then
$     warning_count = warning_count + 1
$   else
$     unexpected = 1
$   endif
$ endif
$ goto next_record
$ end_log:
$ close XMMS_LINK_LOG
$ log_open = 0
$ return
$ bad_arguments:
$ write sys$error "BUILD_LINK requires an existing options file and output image."
$ exit %x0000002c
$ rejected:
$ write sys$error "LINK failed or emitted diagnostics other than prior compilation warnings."
$ write sys$error "See ",output_log," and ",error_log,"; status=",f$fao("!8XL",f$integer(link_status))
$ exit %x0000002c
$ interrupted:
$ status = %x0000002c
$ goto cleanup
$ failed:
$ status = f$integer($status)
$ if (status .and. 7) .eq. 0 then status = %x0000002c
$ cleanup:
$ if f$trnlnm("XMMS_LINK_EMPTY") .nes. "" then close XMMS_LINK_EMPTY
$ if log_open then close XMMS_LINK_LOG
$ exit 'status'
