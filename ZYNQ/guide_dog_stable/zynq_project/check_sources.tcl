open_project {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
puts "CONSTRS=[get_files -of_objects [get_filesets constrs_1]]"
puts "BDVALID=[get_property VALIDATION_STATUS [get_files */led_test.bd]]"
puts "CAM1=[get_bd_ports -quiet ov5640_data]"
close_project
exit
