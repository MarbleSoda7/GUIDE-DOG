open_project {D:/latest_project_pl_rectify/zynq_project/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
set run [get_runs led_test_eth_stream_0_0_synth_1]
puts "BEFORE=[get_property STATUS $run]"
launch_runs $run -jobs 1
wait_on_run $run
puts "AFTER=[get_property STATUS $run]"
close_project
