# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  set C_S00_AXI_DATA_WIDTH [ipgui::add_param $IPINST -name "C_S00_AXI_DATA_WIDTH" -parent ${Page_0} -widget comboBox]
  set_property tooltip {Width of S_AXI data bus} ${C_S00_AXI_DATA_WIDTH}
  set C_S00_AXI_ADDR_WIDTH [ipgui::add_param $IPINST -name "C_S00_AXI_ADDR_WIDTH" -parent ${Page_0}]
  set_property tooltip {Width of S_AXI address bus} ${C_S00_AXI_ADDR_WIDTH}
  ipgui::add_param $IPINST -name "C_S00_AXI_BASEADDR" -parent ${Page_0}
  ipgui::add_param $IPINST -name "C_S00_AXI_HIGHADDR" -parent ${Page_0}

  ipgui::add_param $IPINST -name "VID_IN_DATA_WIDTH"
  ipgui::add_param $IPINST -name "VID_OUT_DATA_WIDTH"
  ipgui::add_param $IPINST -name "BULEDEPTH"
  ipgui::add_param $IPINST -name "REDDEPTH"
  ipgui::add_param $IPINST -name "GREENDEPTH"

}

proc update_PARAM_VALUE.BULEDEPTH { PARAM_VALUE.BULEDEPTH } {
	# Procedure called to update BULEDEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BULEDEPTH { PARAM_VALUE.BULEDEPTH } {
	# Procedure called to validate BULEDEPTH
	return true
}

proc update_PARAM_VALUE.GREENDEPTH { PARAM_VALUE.GREENDEPTH } {
	# Procedure called to update GREENDEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.GREENDEPTH { PARAM_VALUE.GREENDEPTH } {
	# Procedure called to validate GREENDEPTH
	return true
}

proc update_PARAM_VALUE.REDDEPTH { PARAM_VALUE.REDDEPTH } {
	# Procedure called to update REDDEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.REDDEPTH { PARAM_VALUE.REDDEPTH } {
	# Procedure called to validate REDDEPTH
	return true
}

proc update_PARAM_VALUE.VID_IN_DATA_WIDTH { PARAM_VALUE.VID_IN_DATA_WIDTH } {
	# Procedure called to update VID_IN_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.VID_IN_DATA_WIDTH { PARAM_VALUE.VID_IN_DATA_WIDTH } {
	# Procedure called to validate VID_IN_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.VID_OUT_DATA_WIDTH { PARAM_VALUE.VID_OUT_DATA_WIDTH } {
	# Procedure called to update VID_OUT_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.VID_OUT_DATA_WIDTH { PARAM_VALUE.VID_OUT_DATA_WIDTH } {
	# Procedure called to validate VID_OUT_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_DATA_WIDTH { PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to update C_S00_AXI_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_DATA_WIDTH { PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to validate C_S00_AXI_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_ADDR_WIDTH { PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to update C_S00_AXI_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_ADDR_WIDTH { PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to validate C_S00_AXI_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_BASEADDR { PARAM_VALUE.C_S00_AXI_BASEADDR } {
	# Procedure called to update C_S00_AXI_BASEADDR when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_BASEADDR { PARAM_VALUE.C_S00_AXI_BASEADDR } {
	# Procedure called to validate C_S00_AXI_BASEADDR
	return true
}

proc update_PARAM_VALUE.C_S00_AXI_HIGHADDR { PARAM_VALUE.C_S00_AXI_HIGHADDR } {
	# Procedure called to update C_S00_AXI_HIGHADDR when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S00_AXI_HIGHADDR { PARAM_VALUE.C_S00_AXI_HIGHADDR } {
	# Procedure called to validate C_S00_AXI_HIGHADDR
	return true
}


proc update_MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH { MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH PARAM_VALUE.C_S00_AXI_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S00_AXI_DATA_WIDTH}] ${MODELPARAM_VALUE.C_S00_AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH { MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH PARAM_VALUE.C_S00_AXI_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S00_AXI_ADDR_WIDTH}] ${MODELPARAM_VALUE.C_S00_AXI_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.VID_IN_DATA_WIDTH { MODELPARAM_VALUE.VID_IN_DATA_WIDTH PARAM_VALUE.VID_IN_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.VID_IN_DATA_WIDTH}] ${MODELPARAM_VALUE.VID_IN_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.REDDEPTH { MODELPARAM_VALUE.REDDEPTH PARAM_VALUE.REDDEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.REDDEPTH}] ${MODELPARAM_VALUE.REDDEPTH}
}

proc update_MODELPARAM_VALUE.GREENDEPTH { MODELPARAM_VALUE.GREENDEPTH PARAM_VALUE.GREENDEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.GREENDEPTH}] ${MODELPARAM_VALUE.GREENDEPTH}
}

proc update_MODELPARAM_VALUE.BULEDEPTH { MODELPARAM_VALUE.BULEDEPTH PARAM_VALUE.BULEDEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BULEDEPTH}] ${MODELPARAM_VALUE.BULEDEPTH}
}

proc update_MODELPARAM_VALUE.VID_OUT_DATA_WIDTH { MODELPARAM_VALUE.VID_OUT_DATA_WIDTH PARAM_VALUE.VID_OUT_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.VID_OUT_DATA_WIDTH}] ${MODELPARAM_VALUE.VID_OUT_DATA_WIDTH}
}

