open_project [file join [file dirname [info script]] guide_linux_base.xpr]
foreach run [get_runs -quiet *] {
    puts "RUNCHK $run | [get_property STATUS $run] | refresh=[get_property NEEDS_REFRESH $run] | synth=[get_property IS_SYNTHESIS $run]"
}
close_project
