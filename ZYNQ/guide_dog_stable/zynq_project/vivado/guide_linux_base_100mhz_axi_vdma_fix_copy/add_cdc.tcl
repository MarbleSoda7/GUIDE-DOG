set proj "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
open_project $proj
add_files -fileset constrs_1 -norecurse "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.srcs/constrs_1/new/cdc_timing.xdc"
set_property used_in_synthesis false [get_files *cdc_timing.xdc]
set_property used_in_implementation true [get_files *cdc_timing.xdc]
puts "CDC_CONSTRAINT_ADDED"
save_project
close_project
exit
