set xpr [lindex $argv 0]
set out [lindex $argv 1]
open_project $xpr
open_run impl_1
write_hwdef -force -file $out
close_project
puts "HWH=$out"
