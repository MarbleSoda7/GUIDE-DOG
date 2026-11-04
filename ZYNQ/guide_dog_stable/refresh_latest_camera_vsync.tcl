set BASE [file normalize [file dirname [info script]]]
set PROJ [file join $BASE latest_frame_project latest_frame_project.xpr]
set SRC [file join $BASE ip_repo ov5640_to_lcd_1.0 hdl ov5640_to_lcd.v]
if {![file exists $PROJ] || ![file exists $SRC]} { error "LATEST_CAMERA_REFRESH_MISSING" }
open_project $PROJ
set generated [get_files -quiet *ov5640_to_lcd.v]
set matched {}
foreach f $generated {
    if {[string match */ipshared/28a6/hdl/ov5640_to_lcd.v [file normalize $f]]} { lappend matched $f }
}
if {[llength $matched] != 1} { error "LATEST_CAMERA_GENERATED_SOURCE_NOT_UNIQUE=$matched" }
set dst [lindex $matched 0]
file copy -force $SRC $dst
puts "LATEST_CAMERA_SOURCE=$dst"
set camera_runs [get_runs -quiet *ov5640*]
puts "LATEST_CAMERA_OOC_RUNS=$camera_runs"
foreach run $camera_runs { reset_run $run }
set bd [get_files -quiet */zynq.bd]
if {[llength $bd] != 1} { error "LATEST_CAMERA_BD_NOT_UNIQUE=$bd" }
reset_target all $bd
generate_target all $bd
update_compile_order -fileset sources_1
puts "LATEST_CAMERA_REFRESH_DONE"
close_project
exit
