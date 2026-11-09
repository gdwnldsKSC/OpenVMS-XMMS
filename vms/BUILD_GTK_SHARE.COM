$! Preserve link failure status, unlike the original optional-debug wrapper.
$ srcs = "''p2'/OPTIONS"
$ if vms_shares .nes. "" then srcs = srcs + "," + vms_shares
$ on warning then goto failed
$ write sys$output "LINK/SHARE ''p1'"
$ search_reset = f$search(p2 + ".OPT",9)
$ old_image = f$search(p1 + ".EXE",9)
$ link/traceback/share='p1' 'srcs'
$ search_reset = f$search(p2 + ".OPT",9)
$ new_image = f$search(p1 + ".EXE",9)
$ if new_image .eqs. "" .or. new_image .eqs. old_image
$ then
$   write sys$error "LINK produced no new shareable image: ",p1
$   exit %x0000002c
$ endif
$ exit 1
$ failed:
$ status = $status
$! Promote link warnings so the original parent build loops stop as well.
$ if (status .and. 7) .eq. 0 then status = %x0000002c
$ exit 'status'
