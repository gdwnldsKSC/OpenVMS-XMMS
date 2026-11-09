$! Preserve link failure status, unlike the original optional-debug wrapper.
$ srcs = "''p2'/OPTIONS"
$ if vms_shares .nes. "" then srcs = srcs + "," + vms_shares
$ on error then goto failed
$ write sys$output "LINK/SHARE ''p1'"
$ link/traceback/share='p1' 'srcs'
$ exit 1
$ failed:
$ status = $status
$ exit 'status'
