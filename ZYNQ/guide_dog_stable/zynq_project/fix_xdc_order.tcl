open_project {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
set c [get_files -of_objects [get_filesets constrs_1] *cdc_timing.xdc]
puts "CDC_FILE=$c"
set_property PROCESSING_ORDER LATE $c
report_compile_order -constraints -fileset constrs_1 -file {D:/distortion_correction/success_sec/constraint_order.rpt}
close_project
exit
