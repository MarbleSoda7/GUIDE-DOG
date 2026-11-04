# XSCT script to generate FSBL from 100MHz XSA
setws ./workspace

# Create hardware platform
hsi::open_hw_design ../led_test_wrapper_100mhz.xsa

# Generate FSBL application
hsi::create_sw_design fsbl_design -proc ps7_cortexa9_0 -app {Zynq FSBL}

# Set output directory
hsi::set_property APP_COMPILER_FLAGS {-O2} [hsi::get_sw_designs fsbl_design]
hsi::generate_app -app fsbl_design -dir ./fsbl

# Close and exit
hsi::close_hw_design [hsi::current_hw_design]
puts "FSBL generation complete"
exit
