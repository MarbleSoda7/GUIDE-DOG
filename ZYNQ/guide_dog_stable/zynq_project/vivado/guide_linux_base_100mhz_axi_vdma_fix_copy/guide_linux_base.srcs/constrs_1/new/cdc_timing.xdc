# Independent OV5640 PCLKs and PHY RGMII RXC are asynchronous to PS FCLK0.
# Video and Ethernet IP handle their respective clock-domain crossings.
set_clock_groups -asynchronous   -group [get_clocks -include_generated_clocks clk_fpga_0]   -group [get_clocks -include_generated_clocks cam1_pclk]   -group [get_clocks -include_generated_clocks cam2_pclk]   -group [get_clocks -include_generated_clocks rgmii_rxc]
