set proj "D:/distortion_correction/success_third/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr"
open_project $proj
open_bd_design {D:/distortion_correction/success_third/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
set bd [current_bd_design]
# Remove top-level pins that are not present as FPGA-driven signals on the adapter.
foreach pname {cam_xclk_0 cam2_rst_n cam2_pdn} {
  set p [get_bd_ports $pname -quiet]
  if {[llength $p]} {
    foreach n [get_bd_nets -of_objects $p] { catch {disconnect_bd_net $n $p} }
    delete_bd_objs $p
  }
}
# Preserve the existing internal constant drivers for camera 2 RST/PWDN; only delete their external wrapper ports.
# Remove the unused FPGA XCLK wizard. The adapter's Y1 oscillator supplies shared XCLK.
set wiz [get_bd_cells cam_xclk_wiz -quiet]
if {[llength $wiz]} { delete_bd_objs $wiz }
# The two sensor controllers retain their fixed active levels; only camera 0 owns shared external RST/PWDN pins.
validate_bd_design
save_bd_design
generate_target all [get_files {D:/distortion_correction/success_third/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}]
make_wrapper -files [get_files {D:/distortion_correction/success_third/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}] -top -force
update_compile_order -fileset sources_1
puts "SUCCESS_THIRD_BD_ADAPTED"
close_project
exit
