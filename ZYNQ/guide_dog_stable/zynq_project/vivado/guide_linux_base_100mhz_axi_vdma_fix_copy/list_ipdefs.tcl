open_project "D:/distortion_correction/vivado/guide_linux_base/guide_linux_base.xpr"
puts "PART=[get_property PART [current_project]]"
puts "=== v_vid_in_axi4s matches ==="
foreach d [get_ipdefs -all *v_vid_in_axi4s*] { puts "VLNV: $d" }
puts "=== axi_vdma matches ==="
foreach d [get_ipdefs -all *axi_vdma*] { puts "VLNV: $d" }
puts "=== vid_in matches ==="
foreach d [get_ipdefs -all *vid_in*] { puts "VLNV: $d" }
puts "=== END ==="
close_project
exit
