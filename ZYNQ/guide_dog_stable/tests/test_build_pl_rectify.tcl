# Pure Tcl preflight. Reads scripts but never sources a build script.
set test_root [file normalize [file join [file dirname [info script]] ..]]
set copy [file join $test_root zynq_project vivado guide_linux_base_100mhz_axi_vdma_fix_copy]
set scripts [list [file join $copy run_pl_remap_hls.tcl] [file join $copy integrate_pl_remap.tcl] [file join $copy prepare_project.tcl] [file join $copy register_hls_ip.tcl] [file join $test_root tools launch_pl_rectify_build.tcl]]
foreach p $scripts {
    if {![file isfile $p]} { error "missing $p" }
    set ch [open $p r]; set s [read $ch]; close $ch
    if {![info complete $s]} { error "Incomplete Tcl syntax: $p" }
    if {[regexp -nocase {D:/distortion_correction/|D:/latest_project/} $s]} { error "stale path in $p" }
    foreach line [split $s [format %c 10]] {
        if {[string match {set root *} $line]} {
            set expression [string map [list {[info script]} [list $p]] $line]
            eval $expression
            if {$root ne $copy} { error "Incorrect root in $p: $root" }
        }
    }
    set command {}
    foreach line [split $s [format %c 10]] {
        append command $line [format %c 10]

        if {[info complete $command]} {
            set trimmed [string trim $command]
            if {[regexp {^proc ([A-Za-z0-9_]+) } $trimmed -> name]} {
                eval $command
                ::tcl::unsupported::disassemble proc $name
            }
            set command {}
        }
    }
}
if {[pr_number 64K] != 65536 || [pr_number 1G] != 1073741824} { error "address range conversion failed" }
puts "PASS: five Tcl scripts complete; roots and helper procedures checked (not Vivado)"
