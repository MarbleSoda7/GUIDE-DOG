proc prepare {} {
    set BASE [file normalize [file join [file dirname [info script]] ..]]
    connect -url tcp:127.0.0.1:3121
    targets -set -nocase -filter {name =~ "*A9*#0*"}
    puts "COMMIT_RESTART_A9_SELECTED=[state]"
    rst -processor
    puts "COMMIT_RESTART_A9_RESET=[state]"
    uplevel #0 [list source [file join $BASE bsp psinit ps7_init.tcl]]
    ps7_init
    puts COMMIT_RESTART_PS_INIT_COMPLETE
    ps7_post_config
    puts COMMIT_RESTART_PS_POST_CONFIG_COMPLETE
    fpga -file [file join $BASE test_artifacts 20261001T084500Z_commit_restart_v1 commit_restart_v1.bit]
    puts COMMIT_RESTART_BIT_PROGRAMMED
    targets -set -nocase -filter {name =~ "*A9*#0*"}
    dow [file join $BASE test_artifacts stage5_latest_frame_pl_owner_camera_baseline_v1.elf]
    puts COMMIT_RESTART_ELF_DOWNLOADED
    if {![string match {Stopped*} [state]]} { error "CPU_NOT_STOPPED=[state]" }
    puts COMMIT_RESTART_PREPARED_CPU_STOPPED
    disconnect
}
if {[catch {prepare} message options]} {
    puts stderr "COMMIT_RESTART_PREPARE_FAILED=$message"
    exit 1
}
exit 0
