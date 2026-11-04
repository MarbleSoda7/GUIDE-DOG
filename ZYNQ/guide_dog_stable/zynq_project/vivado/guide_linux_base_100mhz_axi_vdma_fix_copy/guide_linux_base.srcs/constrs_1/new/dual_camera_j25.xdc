# success_third: Wildfire dual-camera adapter J25 mapping supplied by user.
# O_* is camera 0 and I_* is camera 1. The adapter has a shared 24 MHz oscillator.
# J25 pin 19 (P15) is the adapter XCLK net and is intentionally not driven by FPGA.
# RST is shared at J25 pin 22 (R14); PWDN is shared at J25 pin 37 (R19).

# O camera data: D0=T10, D1=T11, D2=U12, D3=T12, D4=V13, D5=U13, D6=T15, D7=T14.
set_property IOSTANDARD LVCMOS33 [get_ports {ov5640_data[*] ov5640_pclk ov5640_vsync ov5640_href}]
set_property PACKAGE_PIN T10 [get_ports {ov5640_data[0]}]
set_property PACKAGE_PIN T11 [get_ports {ov5640_data[1]}]
set_property PACKAGE_PIN U12 [get_ports {ov5640_data[2]}]
set_property PACKAGE_PIN T12 [get_ports {ov5640_data[3]}]
set_property PACKAGE_PIN V13 [get_ports {ov5640_data[4]}]
set_property PACKAGE_PIN U13 [get_ports {ov5640_data[5]}]
set_property PACKAGE_PIN T15 [get_ports {ov5640_data[6]}]
set_property PACKAGE_PIN T14 [get_ports {ov5640_data[7]}]
set_property PACKAGE_PIN P16 [get_ports ov5640_pclk]
set_property PACKAGE_PIN U17 [get_ports ov5640_vsync]
set_property PACKAGE_PIN T16 [get_ports ov5640_href]

# Shared RST/PWDN only: do not create separate camera-2 output pins.
set_property IOSTANDARD LVCMOS33 [get_ports {cam_rst_n cam_pdn_0}]
set_property PACKAGE_PIN R14 [get_ports cam_rst_n]
set_property PACKAGE_PIN R19 [get_ports cam_pdn_0]

# I camera data: D0=P14, D1=W16, D2=V16, D3=W19, D4=W18, D5=U19, D6=U18, D7=R17.
set_property IOSTANDARD LVCMOS33 [get_ports {cam2_data[*]}]
set_property PACKAGE_PIN P14 [get_ports {cam2_data[0]}]
set_property PACKAGE_PIN W16 [get_ports {cam2_data[1]}]
set_property PACKAGE_PIN V16 [get_ports {cam2_data[2]}]
set_property PACKAGE_PIN W19 [get_ports {cam2_data[3]}]
set_property PACKAGE_PIN W18 [get_ports {cam2_data[4]}]
set_property PACKAGE_PIN U19 [get_ports {cam2_data[5]}]
set_property PACKAGE_PIN U18 [get_ports {cam2_data[6]}]
set_property PACKAGE_PIN R17 [get_ports {cam2_data[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam2_pclk cam2_vsync cam2_href}]
set_property PACKAGE_PIN W13 [get_ports cam2_pclk]
set_property PACKAGE_PIN W15 [get_ports cam2_vsync]
set_property PACKAGE_PIN P19 [get_ports cam2_href]

# O_SCL=V18, O_SDA=V17; I_SCL=R16, I_SDA=V12.
set_property IOSTANDARD LVCMOS33 [get_ports {cam_sccb_tri_io[*]}]
set_property PULLUP true [get_ports {cam_sccb_tri_io[*]}]
set_property PACKAGE_PIN V18 [get_ports {cam_sccb_tri_io[0]}]
set_property PACKAGE_PIN V17 [get_ports {cam_sccb_tri_io[1]}]
set_property PACKAGE_PIN R16 [get_ports {cam_sccb_tri_io[2]}]
set_property PACKAGE_PIN V12 [get_ports {cam_sccb_tri_io[3]}]

# Sensor PCLKs are asynchronous to FCLK0 and use non-dedicated input routing.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets ov5640_pclk_IBUF]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam2_pclk_IBUF]
create_clock -period 13.888 -name cam1_pclk [get_ports ov5640_pclk]
create_clock -period 13.888 -name cam2_pclk [get_ports cam2_pclk]
