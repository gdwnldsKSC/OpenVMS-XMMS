$! Preserve link failure status, unlike the original optional-debug wrapper.
$ srcs = "''p2'/OPTIONS"
$ if vms_shares .nes. "" then srcs = srcs + "," + vms_shares
$ on warning then goto failed
$ write sys$output "LINK/SHARE ''p1'"
$ link/traceback/share='p1' 'srcs'
$ exit 1
$ failed:
$ status = $status
$! Promote link warnings so the original parent build loops stop as well.
$ if (status .and. 7) .eq. 0 then status = %x0000002c
$ exit 'status'
