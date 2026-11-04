proc monitor {} {
    connect -url tcp:127.0.0.1:3121
    targets -set -nocase -filter {name =~ "*A9*#0*"}
    if {![string match {Stopped*} [state]]} { error "CPU_NOT_STOPPED=[state]" }
    puts "COMMIT_RESTART_BUILD_ID=20261001T084500Z_commit_restart_v1 REUSED_ELF_BUILD_ID=20261001T062420Z_owner_camera_baseline_v1"
    puts "COMMIT_RESTART_INITIAL_OWNER=[mrd -force 0x40000008 6]"
    con
    puts COMMIT_RESTART_CPU_RUNNING
    for {set n 0} {$n < 120} {incr n} {
        after 5000
        puts "COMMIT_RESTART_SAMPLE=$n VDMA=[mrd -force 0x43000030 2] OWNER=[mrd -force 0x40000008 6] TX=[mrd -force 0x4000002C 3]"
    }
    disconnect
}
if {[catch {monitor} message options]} {
    puts stderr "COMMIT_RESTART_MONITOR_FAILED=$message"
    exit 1
}
exit 0
