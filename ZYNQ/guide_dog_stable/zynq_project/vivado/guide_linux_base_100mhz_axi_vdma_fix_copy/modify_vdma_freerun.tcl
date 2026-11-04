# Generate a free-run S2MM-only VDMA variant for the current Linux software.
# The current BD has C_INCLUDE_MM2S=0, so internal Genlock cannot be paired
# with the latest_frame MM2S/commit protocol. Keep camera SOF/FSYNC enabled.
open_project D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.xpr
open_bd_design {D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd}
set vdma_cell [get_bd_cells -filter {VLNV =~ "*axi_vdma*"}]
set_property CONFIG.c_include_internal_genlock {0} $vdma_cell
set_property CONFIG.c_s2mm_genlock_mode {0} $vdma_cell
set_property CONFIG.c_s2mm_genlock_repeat_en {0} $vdma_cell
validate_bd_design
save_bd_design
generate_target all [get_files D:/distortion_correction/vivado/guide_linux_base_100mhz/guide_linux_base.srcs/sources_1/bd/led_test/led_test.bd]
close_project
exit
