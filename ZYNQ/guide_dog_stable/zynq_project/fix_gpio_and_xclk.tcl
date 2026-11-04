set prj {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
set bdfile {D:/distortion_correction/success_sec/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
open_project $prj
open_bd_design $bdfile
if {[llength [get_bd_ports -quiet cam2_xclk]]} {delete_bd_objs [get_bd_ports cam2_xclk]}
set old [get_bd_intf_ports -quiet cam_sccb]
if {[llength $old]} {delete_bd_objs $old}
set_property -dict [list CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} CONFIG.PCW_GPIO_EMIO_GPIO_IO {4} CONFIG.PCW_GPIO_EMIO_GPIO_WIDTH {4}] [get_bd_cells processing_system7_0]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 cam_sccb
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/GPIO_0] [get_bd_intf_ports cam_sccb]
validate_bd_design
save_bd_design
make_wrapper -files [get_files $bdfile] -top
update_compile_order -fileset sources_1
close_project
exit