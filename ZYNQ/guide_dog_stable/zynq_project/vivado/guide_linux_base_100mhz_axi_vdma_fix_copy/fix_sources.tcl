set proj "D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr"
set root "D:/distortion_correction/vivado/guide_linux_base_100mhz"
open_project $proj
set need [list \
  "$root/eth_rtl/gmii_to_rgmii_phase_sweep.v" \
  "$root/eth_rtl/rgmii_tx_phase_sweep.v" \
  "$root/eth_rtl/gmii_to_rgmii/gmii_to_rgmii.v" \
  "$root/eth_rtl/gmii_to_rgmii/rgmii_rx.v" \
  "$root/eth_rtl/gmii_to_rgmii/rgmii_tx.v" ]
foreach f $need {
  if {[llength [get_files -quiet $f]] == 0} { add_files -norecurse $f ; puts "ADDED $f" } else { puts "ALREADY $f" }
}
update_compile_order -fileset sources_1
puts "=== sources_1 中所有 RTL ==="
foreach f [get_files -of_objects [get_filesets sources_1] -filter {FILE_TYPE == Verilog}] { puts "SRC $f" }
save_project
close_project
puts "SOURCES_FIXED"
exit
