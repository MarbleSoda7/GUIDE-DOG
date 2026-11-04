# Make both camera capture paths use the original success project's VDMA path.
# Camera1 already uses axis_rgb24_to_32_node_diag -> VDMA0.
# This adds the same bridge to camera2 and sets VDMA1 to 32-bit S2MM.
set proj "D:/distortion_correction/success_four/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr"
set bdfile "D:/distortion_correction/success_four/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd"
set rtl "D:/distortion_correction/success_four/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/rtl/axis_rgb24_to_32_node_diag.v"

open_project $proj
if {[llength [get_files -quiet $rtl]] == 0} { add_files -norecurse $rtl }
update_compile_order -fileset sources_1
open_bd_design $bdfile

set vdma1 [get_bd_cells axi_vdma_1]
set_property -dict [list \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_s2mm_genlock_mode {0} \
    CONFIG.c_s2mm_genlock_repeat_en {0}] $vdma1

# Remove a previous instance/net if this script is rerun.
set old [get_bd_cells -quiet axis_rgb24_to_32_1]
if {[llength $old] == 1} { delete_bd_objs $old }
set oldnet [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins axi_vdma_1/S_AXIS_S2MM]]
if {[llength $oldnet] == 1} { delete_bd_objs $oldnet }

create_bd_cell -type module -reference axis_rgb24_to_32_node_diag axis_rgb24_to_32_1
connect_bd_intf_net [get_bd_intf_pins v_vid_in_axi4s_1/video_out] [get_bd_intf_pins axis_rgb24_to_32_1/s_axis]
connect_bd_intf_net [get_bd_intf_pins axis_rgb24_to_32_1/m_axis] [get_bd_intf_pins axi_vdma_1/S_AXIS_S2MM]
connect_bd_net [get_bd_pins axi_vdma_1/s_axis_s2mm_aclk] [get_bd_pins axis_rgb24_to_32_1/aclk]
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins axis_rgb24_to_32_1/aresetn]

validate_bd_design
save_bd_design
generate_target all [get_files $bdfile]
close_project
exit
