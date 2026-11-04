set proj "D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr"
set bdfile "D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
set src "D:/distortion_correction/vivado/guide_linux_base_100mhz/rtl/axis_rgb24_to_32_node_diag.v"
open_project $proj
if {[llength [get_files -quiet $src]] == 0} { add_files -norecurse $src }
update_compile_order -fileset sources_1
open_bd_design $bdfile
set old [get_bd_cells -quiet axis_rgb24_to_32_0]
if {[llength $old] == 1} { delete_bd_objs $old }
set oldnet [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]]
if {[llength $oldnet] == 1} { delete_bd_objs $oldnet }
set_property -dict [list CONFIG.c_s_axis_s2mm_tdata_width {32}] [get_bd_cells axi_vdma_0]
create_bd_cell -type module -reference axis_rgb24_to_32_node_diag axis_rgb24_to_32_0
connect_bd_intf_net [get_bd_intf_pins v_vid_in_axi4s_0/video_out] [get_bd_intf_pins axis_rgb24_to_32_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins axis_rgb24_to_32_0/m_axis] [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
connect_bd_net [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] [get_bd_pins axis_rgb24_to_32_0/aclk]
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins axis_rgb24_to_32_0/aresetn]
validate_bd_design
save_bd_design
close_project
exit
