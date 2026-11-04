
################################################################
# This is a generated script based on design: led_test
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2024.1
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source led_test_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# axis_flow_monitor, eth_stream_stage3_diag

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7z020clg400-2
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name led_test

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:processing_system7:5.5\
xilinx.com:ip:axi_gpio:2.0\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:hls:remap_accel:1.0\
xilinx.com:ip:smartconnect:1.0\
xilinx.com:user:ov5640_to_lcd:1.0\
xilinx.com:ip:v_vid_in_axi4s:5.0\
xilinx.com:ip:xlconstant:1.1\
xilinx.com:ip:axi_vdma:6.3\
xilinx.com:ip:axi_dma:7.1\
xilinx.com:ip:axis_data_fifo:2.0\
xilinx.com:ip:clk_wiz:6.0\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
axis_flow_monitor\
eth_stream_stage3_diag\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set led_4bits [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 led_4bits ]

  set cam_sccb [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 cam_sccb ]


  # Create ports
  set ov5640_pclk [ create_bd_port -dir I -type clk ov5640_pclk ]
  set ov5640_href [ create_bd_port -dir I ov5640_href ]
  set ov5640_vsync [ create_bd_port -dir I ov5640_vsync ]
  set ov5640_data [ create_bd_port -dir I -from 7 -to 0 ov5640_data ]
  set cam_rst_n [ create_bd_port -dir O cam_rst_n ]
  set cam_pdn_0 [ create_bd_port -dir O cam_pdn_0 ]
  set cam_xclk_0 [ create_bd_port -dir O cam_xclk_0 ]
  set rgmii_rxc [ create_bd_port -dir I -type clk -freq_hz 125000000 rgmii_rxc ]
  set rgmii_rx_ctl [ create_bd_port -dir I rgmii_rx_ctl ]
  set rgmii_rxd [ create_bd_port -dir I -from 3 -to 0 rgmii_rxd ]
  set rgmii_txc [ create_bd_port -dir O rgmii_txc ]
  set rgmii_tx_ctl [ create_bd_port -dir O rgmii_tx_ctl ]
  set rgmii_txd [ create_bd_port -dir O -from 3 -to 0 rgmii_txd ]
  set eth_rst_n [ create_bd_port -dir O eth_rst_n ]

  # Create instance: processing_system7_0, and set properties
  set processing_system7_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0 ]
  set_property -dict [list \
    CONFIG.PCW_ACT_APU_PERIPHERAL_FREQMHZ {666.666687} \
    CONFIG.PCW_ACT_CAN_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_DCI_PERIPHERAL_FREQMHZ {10.158730} \
    CONFIG.PCW_ACT_ENET0_PERIPHERAL_FREQMHZ {125.000000} \
    CONFIG.PCW_ACT_ENET1_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ {50.000000} \
    CONFIG.PCW_ACT_FPGA1_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA2_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA3_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_PCAP_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_QSPI_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_SDIO_PERIPHERAL_FREQMHZ {100.000000} \
    CONFIG.PCW_ACT_SMC_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_SPI_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_TPIU_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_TTC0_CLK0_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC0_CLK1_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC0_CLK2_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK0_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK1_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK2_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_UART_PERIPHERAL_FREQMHZ {100.000000} \
    CONFIG.PCW_ACT_WDT_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_CLK0_FREQ {50000000} \
    CONFIG.PCW_CLK1_FREQ {10000000} \
    CONFIG.PCW_CLK2_FREQ {10000000} \
    CONFIG.PCW_CLK3_FREQ {10000000} \
    CONFIG.PCW_DDR_RAM_HIGHADDR {0x3FFFFFFF} \
    CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
    CONFIG.PCW_ENET0_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ {1000 Mbps} \
    CONFIG.PCW_EN_EMIO_CD_SDIO0 {0} \
    CONFIG.PCW_EN_EMIO_ENET0 {0} \
    CONFIG.PCW_EN_EMIO_GPIO {1} \
    CONFIG.PCW_EN_EMIO_UART0 {0} \
    CONFIG.PCW_EN_ENET0 {1} \
    CONFIG.PCW_EN_GPIO {0} \
    CONFIG.PCW_EN_QSPI {1} \
    CONFIG.PCW_EN_SDIO0 {1} \
    CONFIG.PCW_EN_UART0 {1} \
    CONFIG.PCW_EN_USB0 {0} \
    CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
    CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} \
    CONFIG.PCW_GPIO_EMIO_GPIO_IO {2} \
    CONFIG.PCW_GPIO_EMIO_GPIO_WIDTH {2} \
    CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {0} \
    CONFIG.PCW_MIO_12_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_12_PULLUP {enabled} \
    CONFIG.PCW_MIO_12_SLEW {slow} \
    CONFIG.PCW_MIO_14_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_14_PULLUP {enabled} \
    CONFIG.PCW_MIO_14_SLEW {slow} \
    CONFIG.PCW_MIO_15_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_15_PULLUP {enabled} \
    CONFIG.PCW_MIO_15_SLEW {slow} \
    CONFIG.PCW_MIO_16_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_16_PULLUP {enabled} \
    CONFIG.PCW_MIO_16_SLEW {slow} \
    CONFIG.PCW_MIO_17_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_17_PULLUP {enabled} \
    CONFIG.PCW_MIO_17_SLEW {slow} \
    CONFIG.PCW_MIO_18_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_18_PULLUP {enabled} \
    CONFIG.PCW_MIO_18_SLEW {slow} \
    CONFIG.PCW_MIO_19_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_19_PULLUP {enabled} \
    CONFIG.PCW_MIO_19_SLEW {slow} \
    CONFIG.PCW_MIO_1_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_1_PULLUP {enabled} \
    CONFIG.PCW_MIO_1_SLEW {slow} \
    CONFIG.PCW_MIO_20_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_20_PULLUP {enabled} \
    CONFIG.PCW_MIO_20_SLEW {slow} \
    CONFIG.PCW_MIO_21_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_21_PULLUP {enabled} \
    CONFIG.PCW_MIO_21_SLEW {slow} \
    CONFIG.PCW_MIO_22_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_22_PULLUP {enabled} \
    CONFIG.PCW_MIO_22_SLEW {slow} \
    CONFIG.PCW_MIO_23_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_23_PULLUP {enabled} \
    CONFIG.PCW_MIO_23_SLEW {slow} \
    CONFIG.PCW_MIO_24_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_24_PULLUP {enabled} \
    CONFIG.PCW_MIO_24_SLEW {slow} \
    CONFIG.PCW_MIO_25_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_25_PULLUP {enabled} \
    CONFIG.PCW_MIO_25_SLEW {slow} \
    CONFIG.PCW_MIO_26_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_26_PULLUP {enabled} \
    CONFIG.PCW_MIO_26_SLEW {slow} \
    CONFIG.PCW_MIO_27_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_27_PULLUP {enabled} \
    CONFIG.PCW_MIO_27_SLEW {slow} \
    CONFIG.PCW_MIO_2_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_2_SLEW {slow} \
    CONFIG.PCW_MIO_3_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_3_SLEW {slow} \
    CONFIG.PCW_MIO_40_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_40_PULLUP {enabled} \
    CONFIG.PCW_MIO_40_SLEW {slow} \
    CONFIG.PCW_MIO_41_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_41_PULLUP {enabled} \
    CONFIG.PCW_MIO_41_SLEW {slow} \
    CONFIG.PCW_MIO_42_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_42_PULLUP {enabled} \
    CONFIG.PCW_MIO_42_SLEW {slow} \
    CONFIG.PCW_MIO_43_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_43_PULLUP {enabled} \
    CONFIG.PCW_MIO_43_SLEW {slow} \
    CONFIG.PCW_MIO_44_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_44_PULLUP {enabled} \
    CONFIG.PCW_MIO_44_SLEW {slow} \
    CONFIG.PCW_MIO_45_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_45_PULLUP {enabled} \
    CONFIG.PCW_MIO_45_SLEW {slow} \
    CONFIG.PCW_MIO_4_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_4_SLEW {slow} \
    CONFIG.PCW_MIO_52_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_52_PULLUP {enabled} \
    CONFIG.PCW_MIO_52_SLEW {slow} \
    CONFIG.PCW_MIO_53_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_53_PULLUP {enabled} \
    CONFIG.PCW_MIO_53_SLEW {slow} \
    CONFIG.PCW_MIO_5_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_5_SLEW {slow} \
    CONFIG.PCW_MIO_6_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_6_SLEW {slow} \
    CONFIG.PCW_MIO_TREE_PERIPHERALS {unassigned#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#unassigned#unassigned#unassigned#unassigned#unassigned#SD 0#unassigned#UART\
0#UART 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#SD\
0#SD 0#SD 0#SD 0#SD 0#SD 0#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#Enet 0#Enet 0} \
    CONFIG.PCW_MIO_TREE_SIGNALS {unassigned#qspi0_ss_b#qspi0_io[0]#qspi0_io[1]#qspi0_io[2]#qspi0_io[3]/HOLD_B#qspi0_sclk#unassigned#unassigned#unassigned#unassigned#unassigned#cd#unassigned#rx#tx#tx_clk#txd[0]#txd[1]#txd[2]#txd[3]#tx_ctl#rx_clk#rxd[0]#rxd[1]#rxd[2]#rxd[3]#rx_ctl#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#clk#cmd#data[0]#data[1]#data[2]#data[3]#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#mdc#mdio}\
\
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_QSPI_GRP_FBCLK_ENABLE {0} \
    CONFIG.PCW_QSPI_GRP_IO1_ENABLE {0} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_IO {MIO 1 .. 6} \
    CONFIG.PCW_QSPI_GRP_SS1_ENABLE {0} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_QSPI_PERIPHERAL_FREQMHZ {200} \
    CONFIG.PCW_QSPI_QSPI_IO {MIO 1 .. 6} \
    CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
    CONFIG.PCW_SD0_GRP_CD_IO {MIO 12} \
    CONFIG.PCW_SD0_GRP_POW_ENABLE {0} \
    CONFIG.PCW_SD0_GRP_WP_ENABLE {0} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_SDIO_PERIPHERAL_VALID {1} \
    CONFIG.PCW_SINGLE_QSPI_DATA_MODE {x4} \
    CONFIG.PCW_UART0_BAUD_RATE {115200} \
    CONFIG.PCW_UART0_GRP_FULL_ENABLE {0} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15} \
    CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_UART_PERIPHERAL_VALID {1} \
    CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {533.333374} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
  ] $processing_system7_0


  # Create instance: axi_gpio_0, and set properties
  set axi_gpio_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0 ]
  set_property -dict [list \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO_WIDTH {4} \
  ] $axi_gpio_0


  # Create instance: ps7_0_axi_periph, and set properties
  set ps7_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps7_0_axi_periph ]
  set_property CONFIG.NUM_MI {6} $ps7_0_axi_periph


  # Create instance: rst_ps7_0_50M, and set properties
  set rst_ps7_0_50M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_50M ]

  # Create instance: remap_accel_0, and set properties
  set remap_accel_0 [ create_bd_cell -type ip -vlnv xilinx.com:hls:remap_accel:1.0 remap_accel_0 ]

  # Create instance: remap_hp_smc, and set properties
  set remap_hp_smc [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 remap_hp_smc ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {6} \
  ] $remap_hp_smc


  # Create instance: ov5640_to_lcd_0, and set properties
  set ov5640_to_lcd_0 [ create_bd_cell -type ip -vlnv xilinx.com:user:ov5640_to_lcd:1.0 ov5640_to_lcd_0 ]

  # Create instance: v_vid_in_axi4s_0, and set properties
  set v_vid_in_axi4s_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_vid_in_axi4s:5.0 v_vid_in_axi4s_0 ]
  set_property CONFIG.C_HAS_ASYNC_CLK {1} $v_vid_in_axi4s_0


  # Create instance: const_axis_en, and set properties
  set const_axis_en [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_axis_en ]
  set_property -dict [list \
    CONFIG.CONST_VAL {1} \
    CONFIG.CONST_WIDTH {1} \
  ] $const_axis_en


  # Create instance: axi_vdma_0, and set properties
  set axi_vdma_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_0 ]
  set_property -dict [list \
    CONFIG.c_include_internal_genlock {0} \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_num_fstores {3} \
    CONFIG.c_s2mm_genlock_mode {0} \
    CONFIG.c_s2mm_linebuffer_depth {2048} \
    CONFIG.c_s2mm_max_burst_length {64} \
  ] $axi_vdma_0


  # Create instance: axi_dma_udp_0, and set properties
  set axi_dma_udp_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_udp_0 ]
  set_property -dict [list \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {0} \
    CONFIG.c_include_sg {0} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {64} \
    CONFIG.c_sg_length_width {23} \
  ] $axi_dma_udp_0


  # Create instance: axis_flow_monitor_0, and set properties
  set block_name axis_flow_monitor
  set block_cell_name axis_flow_monitor_0
  if { [catch {set axis_flow_monitor_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $axis_flow_monitor_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: axis_fifo_udp_0, and set properties
  set axis_fifo_udp_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 axis_fifo_udp_0 ]
  set_property -dict [list \
    CONFIG.FIFO_DEPTH {2048} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.TDATA_NUM_BYTES {8} \
  ] $axis_fifo_udp_0


  # Create instance: eth_stream_0, and set properties
  set block_name eth_stream_stage3_diag
  set block_cell_name eth_stream_0
  if { [catch {set eth_stream_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $eth_stream_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: u_clk_phase, and set properties
  set u_clk_phase [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 u_clk_phase ]
  set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125} \
    CONFIG.CLKOUT1_REQUESTED_PHASE {0.0} \
    CONFIG.PRIM_IN_FREQ {125} \
    CONFIG.USE_LOCKED {false} \
    CONFIG.USE_RESET {false} \
  ] $u_clk_phase


  # Create interface connections
  connect_bd_intf_net -intf_net axi_dma_udp_0_M_AXIS_MM2S [get_bd_intf_pins axi_dma_udp_0/M_AXIS_MM2S] [get_bd_intf_pins axis_flow_monitor_0/s_axis]
  connect_bd_intf_net -intf_net axi_dma_udp_0_M_AXI_MM2S [get_bd_intf_pins axi_dma_udp_0/M_AXI_MM2S] [get_bd_intf_pins remap_hp_smc/S05_AXI]
  connect_bd_intf_net -intf_net axi_gpio_0_GPIO [get_bd_intf_ports led_4bits] [get_bd_intf_pins axi_gpio_0/GPIO]
  connect_bd_intf_net -intf_net axi_vdma_0_M_AXI_S2MM [get_bd_intf_pins axi_vdma_0/M_AXI_S2MM] [get_bd_intf_pins remap_hp_smc/S04_AXI]
  connect_bd_intf_net -intf_net axis_fifo_udp_0_M_AXIS [get_bd_intf_pins axis_fifo_udp_0/M_AXIS] [get_bd_intf_pins eth_stream_0/dma_axis]
  connect_bd_intf_net -intf_net axis_flow_monitor_0_m_axis [get_bd_intf_pins axis_flow_monitor_0/m_axis] [get_bd_intf_pins axis_fifo_udp_0/S_AXIS]
  connect_bd_intf_net -intf_net processing_system7_0_GPIO_0 [get_bd_intf_ports cam_sccb] [get_bd_intf_pins processing_system7_0/GPIO_0]
  connect_bd_intf_net -intf_net processing_system7_0_M_AXI_GP0 [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins ps7_0_axi_periph/S00_AXI]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M00_AXI [get_bd_intf_pins ps7_0_axi_periph/M00_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M01_AXI [get_bd_intf_pins ps7_0_axi_periph/M01_AXI] [get_bd_intf_pins remap_accel_0/s_axi_control]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M02_AXI [get_bd_intf_pins ps7_0_axi_periph/M02_AXI] [get_bd_intf_pins axi_vdma_0/S_AXI_LITE]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M03_AXI [get_bd_intf_pins ps7_0_axi_periph/M03_AXI] [get_bd_intf_pins ov5640_to_lcd_0/S00_AXI]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M04_AXI [get_bd_intf_pins ps7_0_axi_periph/M04_AXI] [get_bd_intf_pins axi_dma_udp_0/S_AXI_LITE]
  connect_bd_intf_net -intf_net ps7_0_axi_periph_M05_AXI [get_bd_intf_pins ps7_0_axi_periph/M05_AXI] [get_bd_intf_pins eth_stream_0/s_axi]
  connect_bd_intf_net -intf_net remap_accel_0_m_axi_gmem0 [get_bd_intf_pins remap_accel_0/m_axi_gmem0] [get_bd_intf_pins remap_hp_smc/S00_AXI]
  connect_bd_intf_net -intf_net remap_accel_0_m_axi_gmem1 [get_bd_intf_pins remap_accel_0/m_axi_gmem1] [get_bd_intf_pins remap_hp_smc/S01_AXI]
  connect_bd_intf_net -intf_net remap_accel_0_m_axi_gmem2 [get_bd_intf_pins remap_accel_0/m_axi_gmem2] [get_bd_intf_pins remap_hp_smc/S02_AXI]
  connect_bd_intf_net -intf_net remap_accel_0_m_axi_gmem3 [get_bd_intf_pins remap_accel_0/m_axi_gmem3] [get_bd_intf_pins remap_hp_smc/S03_AXI]
  connect_bd_intf_net -intf_net remap_hp_smc_M00_AXI [get_bd_intf_pins remap_hp_smc/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]
  connect_bd_intf_net -intf_net v_vid_in_axi4s_0_video_out [get_bd_intf_pins v_vid_in_axi4s_0/video_out] [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]

  # Create port connections
  connect_bd_net -net axis_flow_monitor_0_dbg_accepted_beats [get_bd_pins axis_flow_monitor_0/dbg_accepted_beats] [get_bd_pins eth_stream_0/dma_mon_accepted_beats]
  connect_bd_net -net axis_flow_monitor_0_dbg_stall_cycles [get_bd_pins axis_flow_monitor_0/dbg_stall_cycles] [get_bd_pins eth_stream_0/dma_mon_stall_cycles]
  connect_bd_net -net axis_flow_monitor_0_dbg_tlasts [get_bd_pins axis_flow_monitor_0/dbg_tlasts] [get_bd_pins eth_stream_0/dma_mon_tlasts]
  connect_bd_net -net const_axis_en_dout [get_bd_pins const_axis_en/dout] [get_bd_pins v_vid_in_axi4s_0/axis_enable]
  connect_bd_net -net eth_stream_0_eth_rst_n [get_bd_pins eth_stream_0/eth_rst_n] [get_bd_ports eth_rst_n]
  connect_bd_net -net eth_stream_0_rgmii_tx_ctl [get_bd_pins eth_stream_0/rgmii_tx_ctl] [get_bd_ports rgmii_tx_ctl]
  connect_bd_net -net eth_stream_0_rgmii_txc [get_bd_pins eth_stream_0/rgmii_txc] [get_bd_ports rgmii_txc]
  connect_bd_net -net eth_stream_0_rgmii_txd [get_bd_pins eth_stream_0/rgmii_txd] [get_bd_ports rgmii_txd]
  connect_bd_net -net ov5640_data_1 [get_bd_ports ov5640_data] [get_bd_pins ov5640_to_lcd_0/ov5640_data]
  connect_bd_net -net ov5640_href_1 [get_bd_ports ov5640_href] [get_bd_pins ov5640_to_lcd_0/ov5640_href]
  connect_bd_net -net ov5640_pclk_1 [get_bd_ports ov5640_pclk] [get_bd_pins ov5640_to_lcd_0/ov5640_pclk]
  connect_bd_net -net ov5640_to_lcd_0_cam_pdn [get_bd_pins ov5640_to_lcd_0/cam_pdn] [get_bd_ports cam_pdn_0]
  connect_bd_net -net ov5640_to_lcd_0_cam_rst_n [get_bd_pins ov5640_to_lcd_0/cam_rst_n] [get_bd_ports cam_rst_n]
  connect_bd_net -net ov5640_to_lcd_0_cam_xclk [get_bd_pins ov5640_to_lcd_0/cam_xclk] [get_bd_ports cam_xclk_0]
  connect_bd_net -net ov5640_to_lcd_0_tft_ce [get_bd_pins ov5640_to_lcd_0/tft_ce] [get_bd_pins v_vid_in_axi4s_0/vid_io_in_ce]
  connect_bd_net -net ov5640_to_lcd_0_tft_clk [get_bd_pins ov5640_to_lcd_0/tft_clk] [get_bd_pins v_vid_in_axi4s_0/vid_io_in_clk]
  connect_bd_net -net ov5640_to_lcd_0_tft_data [get_bd_pins ov5640_to_lcd_0/tft_data] [get_bd_pins v_vid_in_axi4s_0/vid_data]
  connect_bd_net -net ov5640_to_lcd_0_tft_de [get_bd_pins ov5640_to_lcd_0/tft_de] [get_bd_pins v_vid_in_axi4s_0/vid_active_video]
  connect_bd_net -net ov5640_to_lcd_0_vsync [get_bd_pins ov5640_to_lcd_0/vsync] [get_bd_pins v_vid_in_axi4s_0/vid_vsync]
  connect_bd_net -net ov5640_vsync_1 [get_bd_ports ov5640_vsync] [get_bd_pins ov5640_to_lcd_0/ov5640_vsync]
  connect_bd_net -net processing_system7_0_FCLK_CLK0 [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] [get_bd_pins ps7_0_axi_periph/S00_ACLK] [get_bd_pins rst_ps7_0_50M/slowest_sync_clk] [get_bd_pins axi_gpio_0/s_axi_aclk] [get_bd_pins ps7_0_axi_periph/M00_ACLK] [get_bd_pins ps7_0_axi_periph/ACLK] [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] [get_bd_pins remap_accel_0/ap_clk] [get_bd_pins remap_hp_smc/aclk] [get_bd_pins ps7_0_axi_periph/M01_ACLK] [get_bd_pins v_vid_in_axi4s_0/aclk] [get_bd_pins axi_vdma_0/s_axi_lite_aclk] [get_bd_pins axi_vdma_0/m_axi_s2mm_aclk] [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] [get_bd_pins ps7_0_axi_periph/M02_ACLK] [get_bd_pins ps7_0_axi_periph/M03_ACLK] [get_bd_pins ov5640_to_lcd_0/s00_axi_aclk] [get_bd_pins axi_dma_udp_0/s_axi_lite_aclk] [get_bd_pins axi_dma_udp_0/m_axi_mm2s_aclk] [get_bd_pins axis_flow_monitor_0/aclk] [get_bd_pins axis_fifo_udp_0/s_axis_aclk] [get_bd_pins eth_stream_0/s_axi_aclk] [get_bd_pins ps7_0_axi_periph/M04_ACLK] [get_bd_pins ps7_0_axi_periph/M05_ACLK]
  connect_bd_net -net processing_system7_0_FCLK_RESET0_N [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_ps7_0_50M/ext_reset_in]
  connect_bd_net -net rgmii_rx_ctl_1 [get_bd_ports rgmii_rx_ctl] [get_bd_pins eth_stream_0/rgmii_rx_ctl]
  connect_bd_net -net rgmii_rxc_1 [get_bd_ports rgmii_rxc] [get_bd_pins u_clk_phase/clk_in1]
  connect_bd_net -net rgmii_rxd_1 [get_bd_ports rgmii_rxd] [get_bd_pins eth_stream_0/rgmii_rxd]
  connect_bd_net -net rst_ps7_0_50M_peripheral_aresetn [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins ps7_0_axi_periph/S00_ARESETN] [get_bd_pins axi_gpio_0/s_axi_aresetn] [get_bd_pins ps7_0_axi_periph/M00_ARESETN] [get_bd_pins ps7_0_axi_periph/ARESETN] [get_bd_pins remap_accel_0/ap_rst_n] [get_bd_pins remap_hp_smc/aresetn] [get_bd_pins ps7_0_axi_periph/M01_ARESETN] [get_bd_pins v_vid_in_axi4s_0/aresetn] [get_bd_pins axi_vdma_0/axi_resetn] [get_bd_pins ps7_0_axi_periph/M02_ARESETN] [get_bd_pins ps7_0_axi_periph/M03_ARESETN] [get_bd_pins ov5640_to_lcd_0/s00_axi_aresetn] [get_bd_pins ov5640_to_lcd_0/sys_rst_n] [get_bd_pins axi_dma_udp_0/axi_resetn] [get_bd_pins axis_flow_monitor_0/aresetn] [get_bd_pins axis_fifo_udp_0/s_axis_aresetn] [get_bd_pins eth_stream_0/s_axi_aresetn] [get_bd_pins eth_stream_0/sys_rst_n] [get_bd_pins ps7_0_axi_periph/M04_ARESETN] [get_bd_pins ps7_0_axi_periph/M05_ARESETN]
  connect_bd_net -net rst_ps7_0_50M_peripheral_reset [get_bd_pins rst_ps7_0_50M/peripheral_reset] [get_bd_pins v_vid_in_axi4s_0/vid_io_in_reset]
  connect_bd_net -net u_clk_phase_clk_out1 [get_bd_pins u_clk_phase/clk_out1] [get_bd_pins eth_stream_0/rgmii_rxc] [get_bd_pins axis_fifo_udp_0/m_axis_aclk]

  # Create address segments
  assign_bd_address -offset 0x41E00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_dma_udp_0/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x41200000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_gpio_0/S_AXI/Reg] -force
  assign_bd_address -offset 0x44A00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_vdma_0/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x40010000 -range 0x00001000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs eth_stream_0/s_axi/reg0] -force
  assign_bd_address -offset 0x44A10000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs ov5640_to_lcd_0/S00_AXI/S00_AXI_reg] -force
  assign_bd_address -offset 0x40000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs remap_accel_0/s_axi_control/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces remap_accel_0/Data_m_axi_gmem0] [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces remap_accel_0/Data_m_axi_gmem1] [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces remap_accel_0/Data_m_axi_gmem2] [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces remap_accel_0/Data_m_axi_gmem3] [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces axi_vdma_0/Data_S2MM] [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces axi_dma_udp_0/Data_MM2S] [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


