open_project {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
set old [get_files -quiet */ov5640_camera.xdc]
if {[llength $old]} {remove_files -fileset constrs_1 $old}
add_files -fileset constrs_1 -norecurse {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/constrs_1/new/dual_camera_j25.xdc}
update_compile_order -fileset constrs_1
report_property [get_filesets constrs_1]
close_project
exit
