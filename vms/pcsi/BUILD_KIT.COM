$! Build a complete XMMS runtime PCSI kit from already-built native images.
$! P1 = existing work directory, e.g. DKA100:[XMMS_KIT]
$! P2 = GTK build root, e.g. DKA100:[GTK1210]
$! P3 = OPL runtime image, e.g. DKA100:[OPL]VMS_JACKETS.EXE
$! P4 = corresponding-source ZIP for this exact build (required)
$! P5 = OPL source/notices directory, e.g. DKA100:[OPL]
$! No installation, system configuration or recursive deletion is performed.
$! MATERIAL, OUTPUT and VERIFY under P1 must not already exist.
$ on warning then goto failed
$ on control_y then goto interrupted
$ old_default = f$environment("DEFAULT")
$ old_parse = f$getjpi("","PARSE_STYLE_PERM")
$ set process/parse_style=extended
$ procedure = f$environment("PROCEDURE")
$ here = f$parse(procedure,,,"DEVICE") + f$parse(procedure,,,"DIRECTORY")
$! Use the actual procedure path, independent of the caller's default directory.
$ kit_device = f$parse(procedure,,,"DEVICE")
$ kit_directory = f$parse(procedure,,,"DIRECTORY")
$ dir_length = f$length(kit_directory)
$ if dir_length .lt. 11 then goto bad_layout
$ if f$edit(f$extract(dir_length-10,10,kit_directory),"UPCASE") .nes. ".VMS.PCSI]" then goto bad_layout
$ vms_dir = kit_device + f$extract(0,dir_length-6,kit_directory) + "]"
$ source_dir = kit_device + f$extract(0,dir_length-10,kit_directory) + "]"
$ if p1 .eqs. "" then goto usage
$ if p2 .eqs. "" then p2 = "DKA100:[GTK1210]"
$ if p3 .eqs. "" then p3 = "SYS$SHARE:VMS_JACKETS.EXE"
$ if p4 .eqs. "" then goto usage
$ if p5 .eqs. "" then p5 = "DKA100:[OPL]"
$ if f$extract(f$length(p1)-1,1,p1) .nes. "]" then goto usage
$ if f$locate("*",p1) .lt. f$length(p1) then goto usage
$ if f$locate("%",p1) .lt. f$length(p1) then goto usage
$ if f$locate("...",p1) .lt. f$length(p1) then goto usage
$ if f$search(p4) .eqs. "" then goto missing
$ if f$edit(f$parse(p4,,,"TYPE"),"UPCASE") .nes. ".ZIP" then goto usage
$ workdev = f$parse(p1,,,"DEVICE")
$ workdir = f$parse(p1,,,"DIRECTORY")
$ workroot = workdev + f$extract(0,f$length(workdir)-1,workdir) + ".]"
$! PCSI needs a physical rooted material path; do not root a concealed logical twice.
$ material_root = workdev + f$extract(0,f$length(workdir)-1,workdir) + ".MATERIAL.]"
$ define/process/nolog/translation=concealed XMMS_KIT 'workroot'
$ gtkdev = f$parse(p2,,,"DEVICE")
$ gtkdir = f$parse(p2,,,"DIRECTORY")
$ gtkroot = gtkdev + f$extract(0,f$length(gtkdir)-1,gtkdir) + ".]"
$ define/process/nolog/translation=concealed XMMS_GTK 'gtkroot'
$ define/process/nolog XMMS_OPL 'p5'
$ if f$search("XMMS_KIT:[000000]MATERIAL.DIR") .nes. "" then goto occupied
$ if f$search("XMMS_KIT:[000000]OUTPUT.DIR") .nes. "" then goto occupied
$ if f$search("XMMS_KIT:[000000]VERIFY.DIR") .nes. "" then goto occupied
$! Check every required input before creating output directories.
$ if f$search(here + "XMMS.PCSI$DESC") .eqs. "" then goto missing
$ if f$search(here + "XMMS.PCSI$TEXT") .eqs. "" then goto missing
$ if f$search(here + "LICENSES.TXT") .eqs. "" then goto missing
$ if f$search(here + "RELEASE_NOTES.TXT") .eqs. "" then goto missing
$ app_image = kit_device + f$extract(0,dir_length-10,kit_directory) + ".VMS_BUILD]XMMS.EXE"
$ if f$search(app_image) .eqs. "" then goto missing
$ if f$search(vms_dir + "RUN.COM") .eqs. "" then goto missing
$ if f$search("XMMS_GTK:[GTK.GTK]LIBGTK.EXE") .eqs. "" then goto missing
$ if f$search("XMMS_GTK:[GTK.GDK]LIBGDK.EXE") .eqs. "" then goto missing
$ if f$search("XMMS_GTK:[GLIB]LIBGLIB.EXE") .eqs. "" then goto missing
$ if f$search("XMMS_GTK:[GLIB.GMODULE]LIBGMODULE.EXE") .eqs. "" then goto missing
$ if f$search(p3) .eqs. "" then goto missing
$ if f$search(source_dir + "COPYING.") .eqs. "" then goto missing
$ if f$search(source_dir + "AUTHORS.") .eqs. "" then goto missing
$ if f$search("XMMS_GTK:[GTK]COPYING.") .eqs. "" then goto missing
$ if f$search("XMMS_GTK:[GLIB]COPYING.") .eqs. "" then goto missing
$ if f$search("XMMS_GTK:[000000]LICENSE.TXT") .eqs. "" then goto missing
$ if f$search("XMMS_OPL:LICENSE.TXT") .eqs. "" then goto missing
$ if f$search("XMMS_OPL:GNU_PUBLIC_LICENSE.TXT") .eqs. "" then goto missing
$ create/directory XMMS_KIT:[MATERIAL.XMMS.LIB]
$ create/directory XMMS_KIT:[MATERIAL.XMMS.LICENSES]
$ create/directory XMMS_KIT:[OUTPUT]
$ create/directory XMMS_KIT:[VERIFY]
$ open/write manifest XMMS_KIT:[MATERIAL.XMMS]MANIFEST.TXT
$ write manifest "XMMS V1.2-11R1 runtime material; native COPY checksums and RMS attributes"
$ write manifest "Built " + f$time()
$ call copy_checked "''app_image'" "XMMS_KIT:[MATERIAL.XMMS]XMMS.EXE"
$ call copy_checked "''vms_dir'RUN.COM" "XMMS_KIT:[MATERIAL.XMMS]XMMS.COM"
$ call copy_checked "''source_dir'COPYING." "XMMS_KIT:[MATERIAL.XMMS]COPYING.TXT"
$ call copy_checked "''source_dir'AUTHORS." "XMMS_KIT:[MATERIAL.XMMS]AUTHORS.TXT"
$ call copy_checked "''here'LICENSES.TXT" "XMMS_KIT:[MATERIAL.XMMS]LICENSES.TXT"
$ call copy_checked "''here'RELEASE_NOTES.TXT" "XMMS_KIT:[MATERIAL.XMMS]RELEASE_NOTES.TXT"
$ call copy_checked "XMMS_GTK:[GTK.GTK]LIBGTK.EXE" "XMMS_KIT:[MATERIAL.XMMS.LIB]LIBGTK.EXE"
$ call copy_checked "XMMS_GTK:[GTK.GDK]LIBGDK.EXE" "XMMS_KIT:[MATERIAL.XMMS.LIB]LIBGDK.EXE"
$ call copy_checked "XMMS_GTK:[GLIB]LIBGLIB.EXE" "XMMS_KIT:[MATERIAL.XMMS.LIB]LIBGLIB.EXE"
$ call copy_checked "XMMS_GTK:[GLIB.GMODULE]LIBGMODULE.EXE" "XMMS_KIT:[MATERIAL.XMMS.LIB]LIBGMODULE.EXE"
$ call copy_checked "''p3'" "XMMS_KIT:[MATERIAL.XMMS.LIB]VMS_JACKETS.EXE"
$ call copy_checked "XMMS_GTK:[GTK]COPYING." "XMMS_KIT:[MATERIAL.XMMS.LICENSES]GTK_COPYING.TXT"
$ call copy_checked "XMMS_GTK:[GLIB]COPYING." "XMMS_KIT:[MATERIAL.XMMS.LICENSES]GLIB_COPYING.TXT"
$ call copy_checked "XMMS_GTK:[000000]LICENSE.TXT" "XMMS_KIT:[MATERIAL.XMMS.LICENSES]GTK_PORT_LICENSE.TXT"
$ call copy_checked "XMMS_OPL:LICENSE.TXT" "XMMS_KIT:[MATERIAL.XMMS.LICENSES]OPL_LICENSE.TXT"
$ call copy_checked "XMMS_OPL:GNU_PUBLIC_LICENSE.TXT" "XMMS_KIT:[MATERIAL.XMMS.LICENSES]OPL_GPL.TXT"
$ call copy_checked "''p4'" "XMMS_KIT:[OUTPUT]XMMS-SOURCE-V1_2_11R1.ZIP"
$ checksum/file/algorithm=md5 XMMS_KIT:[OUTPUT]XMMS-SOURCE-V1_2_11R1.ZIP
$ source_md5 = checksum$checksum
$ open/write source_info XMMS_KIT:[MATERIAL.XMMS]SOURCE_INFO.TXT
$ write source_info "Corresponding-source companion: XMMS-SOURCE-V1_2_11R1.ZIP"
$ write source_info "MD5: " + source_md5
$ write source_info "Distribute this exact companion with XMMS-AXPVMS-XMMS-V0102-11R1-1.PCSI."
$ write source_info "It contains the exact XMMS/GTK/GLib build sources and OPL source/notices."
$ write source_info "OpenVMS, DECwindows and MMOV development files are external dependencies."
$ close source_info
$ close manifest
$ product package XMMS /producer=XMMS /base_system=AXPVMS /version=V1.2-11R1 -
    /source='here'XMMS.PCSI$DESC /material='material_root' -
    /destination=XMMS_KIT:[OUTPUT] /format=sequential /log
$! Independently reconstruct the material tree through PCSI, then compare it.
$ product copy XMMS /producer=XMMS /base_system=AXPVMS /version=V1.2-11R1 -
    /source=XMMS_KIT:[OUTPUT] /destination=XMMS_KIT:[VERIFY] -
    /format=reference /options=noconfirm /log
$ search_context = 717
$ verified_files = 0
$ verify_next:
$ material = f$search("XMMS_KIT:[MATERIAL.XMMS...]*.*;",search_context)
$ if material .eqs. "" then goto verify_done
$ if f$edit(f$parse(material,,,"TYPE"),"UPCASE") .eqs. ".DIR" then goto verify_next
$ material_dir = f$parse(material,,,"DIRECTORY")
$ marker = f$locate("MATERIAL.XMMS",material_dir)
$ if marker .eq. f$length(material_dir) then goto mismatch
$ suffix = f$extract(marker+9,f$length(material_dir),material_dir)
$ verify_file = "XMMS_KIT:[VERIFY." + suffix + f$parse(material,,,"NAME") + f$parse(material,,,"TYPE")
$ call compare_checked "''material'" "''verify_file'"
$ verified_files = verified_files + 1
$ goto verify_next
$ verify_done:
$ if verified_files .ne. 18 then goto mismatch
$ write sys$output "%XMMS-I-KITBUILT, runtime kit and source companion in XMMS_KIT:[OUTPUT]"
$ write sys$output "%XMMS-I-VERIFIED, all re-extracted material matches native MD5/RMS attributes"
$ write sys$output "Next: install, launch, play and remove on the isolated clean system."
$ set default 'old_default'
$ set process/parse_style='old_parse'
$ exit 1
$ copy_checked: subroutine
$ on warning then goto copy_failed
$ src = f$search(p1)
$ if src .eqs. "" then exit %x0000002c
$ copy/nolog 'src' 'p2'
$ call compare_checked "''src'" "''p2'"
$ checksum/file/algorithm=md5 'src'
$ write manifest p2 + " MD5=" + checksum$checksum + " RFM=" + f$file_attributes(src,"RFM") + -
    " MRS=" + f$string(f$file_attributes(src,"MRS")) + " LRL=" + f$string(f$file_attributes(src,"LRL"))
$ exit 1
$ copy_failed:
$ copy_status = $status
$ exit 'copy_status'
$ endsubroutine
$ compare_checked: subroutine
$ on warning then goto compare_failed
$ src = f$search(p1)
$ dst = f$search(p2)
$ if src .eqs. "" .or. dst .eqs. "" then exit %x0000002c
$ checksum/file/algorithm=md5 'src'
$ expected = checksum$checksum
$ checksum/file/algorithm=md5 'dst'
$ if checksum$checksum .nes. expected then goto compare_bad
$ if f$file_attributes(src,"RFM") .nes. f$file_attributes(dst,"RFM") then goto compare_bad
$ if f$file_attributes(src,"MRS") .ne. f$file_attributes(dst,"MRS") then goto compare_bad
$ if f$file_attributes(src,"LRL") .ne. f$file_attributes(dst,"LRL") then goto compare_bad
$ if f$file_attributes(src,"RAT") .nes. f$file_attributes(dst,"RAT") then goto compare_bad
$ if f$file_attributes(src,"EOF") .ne. f$file_attributes(dst,"EOF") then goto compare_bad
$ if f$file_attributes(src,"FFB") .ne. f$file_attributes(dst,"FFB") then goto compare_bad
$ exit 1
$ compare_bad:
$ write sys$error "%XMMS-E-MISMATCH, copied bytes or RMS attributes differ: ''p2'"
$ exit %x0000002c
$ compare_failed:
$ compare_status = $status
$ exit 'compare_status'
$ endsubroutine
$ bad_layout:
$ write sys$error "Expected BUILD_KIT.COM in the source tree's [.VMS.PCSI] directory."
$ status = %x0000002c
$ goto cleanup
$ usage:
$ write sys$error "Usage: @BUILD_KIT work-directory GTK-root OPL-image exact-source.ZIP OPL-source-directory"
$ write sys$error "Create the work directory first; its MATERIAL/OUTPUT/VERIFY subdirectories must be absent."
$ status = %x0000002c
$ goto cleanup
$ occupied:
$ write sys$error "%XMMS-E-OCCUPIED, staging directories already exist; use a fresh work directory"
$ status = %x0000002c
$ goto cleanup
$ missing:
$ write sys$error "%XMMS-E-MISSING, required native image, source companion or component notice is absent"
$ status = %x0000002c
$ goto cleanup
$ mismatch:
$ write sys$error "%XMMS-E-MISMATCH, could not map staged material to verification directory"
$ status = %x0000002c
$ goto cleanup
$ interrupted:
$ status = %x0000002c
$ goto cleanup
$ failed:
$ status = $status
$ cleanup:
$ if f$trnlnm("MANIFEST") .nes. "" then close manifest
$ if f$trnlnm("SOURCE_INFO") .nes. "" then close source_info
$ set default 'old_default'
$ set process/parse_style='old_parse'
$ exit 'status'
