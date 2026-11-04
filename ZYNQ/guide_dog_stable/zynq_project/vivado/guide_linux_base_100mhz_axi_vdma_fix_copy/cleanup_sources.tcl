set proj "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
open_project $proj
set root "D:/distortion_correction/vivado/guide_linux_base"
# eth_rtl 只保留: 真实实现 + BD module_ref + wrapper
set ethkeep {eth_stream.v eth_stream_stage3_diag.v zynq_eth_stream_0_0.v}
foreach f [glob -nocomplain "$root/eth_rtl/*.v"] {
  if {[lsearch $ethkeep [file tail $f]] < 0} { remove_files $f ; puts "REMOVED [file tail $f]" }
}
update_compile_order -fileset sources_1
puts "=== 保留的 eth_rtl 源 ==="
foreach f [get_files -quiet "*/eth_rtl/*.v"] { puts "KEEP $f" }
puts "=== 保留的 rtl 源 ==="
foreach f [get_files -quiet "*/rtl/*.v"] { puts "KEEP $f" }
save_project
close_project
puts "CLEANUP_DONE"
exit
