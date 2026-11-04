open_project {D:/distortion_correction/success_seven/vivado/guide_linux_base_100mhz_axi_vdma_fix_copy/guide_linux_base.xpr}
puts "--- runs ---"
foreach r [get_runs] { puts "RUN $r status=[get_property STATUS $r]" }
puts "--- bd ---"
foreach b [get_files *.bd] { puts "BD $b mode=[get_property synth_checkpoint_mode $b]" }
puts "--- top ---"
puts "TOP=[get_property top [current_fileset]]"
close_project
exit
