open_project {D:/latest_project_pl_rectify/zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
foreach r {led_test_eth_stream_0_0_synth_1 led_test_axis_rgb24_to_32_0_0_synth_1 led_test_axis_rgb24_to_32_1_0_synth_1} {
    set run [get_runs $r]
    if {[catch {set_property NEEDS_REFRESH 0 $run} e]} { puts "SETFAIL $r : $e" } else { puts "SETOK $r -> [get_property NEEDS_REFRESH $run]" }
}
close_project
