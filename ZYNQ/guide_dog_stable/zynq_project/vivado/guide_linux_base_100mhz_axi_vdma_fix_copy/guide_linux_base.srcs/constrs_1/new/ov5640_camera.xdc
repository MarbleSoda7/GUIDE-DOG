# ===================================================================
# OV5640 camera DVP pins - Wildfire Haoyue 7020 hardware spec
# SCCB (T17/R18) routed through PS EMIO GPIO[1:0]: bit0=SCL, bit1=SDA
# ===================================================================
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets ov5640_pclk_IBUF]
create_clock -period 13.888 -name ov5640_pclk [get_ports ov5640_pclk]

set_property IOSTANDARD LVCMOS33 [get_ports ov5640_pclk]
set_property IOSTANDARD LVCMOS33 [get_ports {ov5640_data[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports ov5640_href]
set_property IOSTANDARD LVCMOS33 [get_ports ov5640_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports cam_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports cam_pdn_0]
set_property IOSTANDARD LVCMOS33 [get_ports cam_xclk_0]

set_property PACKAGE_PIN N15 [get_ports {ov5640_data[0]}]
set_property PACKAGE_PIN N16 [get_ports {ov5640_data[1]}]
set_property PACKAGE_PIN L14 [get_ports {ov5640_data[2]}]
set_property PACKAGE_PIN L15 [get_ports {ov5640_data[3]}]
set_property PACKAGE_PIN M14 [get_ports {ov5640_data[4]}]
set_property PACKAGE_PIN M15 [get_ports {ov5640_data[5]}]
set_property PACKAGE_PIN L16 [get_ports {ov5640_data[6]}]
set_property PACKAGE_PIN L17 [get_ports {ov5640_data[7]}]
set_property PACKAGE_PIN M19 [get_ports ov5640_vsync]
set_property PACKAGE_PIN M20 [get_ports ov5640_href]
set_property PACKAGE_PIN L19 [get_ports ov5640_pclk]
set_property PACKAGE_PIN M18 [get_ports cam_rst_n]
set_property PACKAGE_PIN M17 [get_ports cam_pdn_0]
set_property PACKAGE_PIN L20 [get_ports cam_xclk_0]
# === SCCB (camera I2C via PS EMIO GPIO) ===
set_property PACKAGE_PIN T17 [get_ports {cam_sccb_tri_io[0]}]
set_property PACKAGE_PIN R18 [get_ports {cam_sccb_tri_io[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_sccb_tri_io[*]}]
set_property PULLUP true [get_ports {cam_sccb_tri_io[*]}]
