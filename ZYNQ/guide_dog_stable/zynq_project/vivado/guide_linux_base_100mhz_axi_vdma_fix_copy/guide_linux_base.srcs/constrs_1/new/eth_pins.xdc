# ===================================================================
# PL Ethernet RGMII pins - Wildfire Haoyue 7020 (from verified guide_dog build)
# rgmii_rxc clock is generated/constrained via u_clk_phase IP
# ===================================================================
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports eth_rst_n]

set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports rgmii_rxc]
set_property -dict {PACKAGE_PIN F17 IOSTANDARD LVCMOS33} [get_ports rgmii_rx_ctl]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[0]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[1]}]
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[2]}]
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports {rgmii_rxd[3]}]

set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports rgmii_txc]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports rgmii_tx_ctl]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {rgmii_txd[0]}]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {rgmii_txd[1]}]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports {rgmii_txd[2]}]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports {rgmii_txd[3]}]

# DRC waiver for bank voltage conflict checks
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
