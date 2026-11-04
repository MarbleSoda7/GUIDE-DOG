# Integrate only the prepared copy. No synthesis or implementation here.
set root [file normalize [file dirname [info script]]]
source [file join $root register_hls_ip.tcl]
set bdfile [file join $root guide_linux_base.srcs sources_1 bd led_test led_test.bd]
open_bd_design $bdfile

proc pr_one {objects label} {
    if {[llength $objects] != 1} { error "Expected one $label, got: $objects" }
    return [lindex $objects 0]
}
# Idempotent connections: join a free endpoint to an existing net, or no-op
# when already connected. Never disconnect or merge two established nets.
proc pr_connect {a b interface} {
    if {$interface} {
        set pa [pr_one [get_bd_intf_pins -quiet $a] $a]
        set pb [pr_one [get_bd_intf_pins -quiet $b] $b]
        set na [get_bd_intf_nets -quiet -of_objects $pa]
        set nb [get_bd_intf_nets -quiet -of_objects $pb]
    } else {
        set pa [pr_one [get_bd_pins -quiet $a] $a]
        set pb [pr_one [get_bd_pins -quiet $b] $b]
        set na [get_bd_nets -quiet -of_objects $pa]
        set nb [get_bd_nets -quiet -of_objects $pb]
    }
    if {[llength $na] && [llength $nb]} {
        if {$na ne $nb} { error "Refusing to merge existing nets: $a=$na; $b=$nb" }
        return
    }
    if {$interface} { connect_bd_intf_net $pa $pb } else { connect_bd_net $pa $pb }
}
# A monitor TAP is a load on an existing net, never a second endpoint. Using
# connect_bd_net with two bare pins makes Vivado override the master pin's
# interface net (BD 41-1271) and tie the responses to 0, so the tap is always
# attached to the ALREADY-EXISTING net by name.
# Resolve the physical net a pin sits on. A pin that belongs to a connected
# interface has NO entry in get_bd_nets; the interface net is the real wire, so
# fall back to get_bd_intf_nets instead of concluding the pin is unconnected.
proc pr_pin_net {pin} {
    set nets [get_bd_nets -quiet -of_objects $pin]
    if {[llength $nets] == 0} {
        # Only a pin that is ITSELF a member of an interface inherits that
        # interface's net. Never fall back to every interface of the parent
        # cell, or an unconnected tap would inherit the unrelated S_AXI net.
        foreach ip [get_bd_intf_pins -quiet -of_objects $pin] {
            set inets [get_bd_intf_nets -quiet -of_objects $ip]
            if {[llength $inets]} { return [lindex $inets 0] }
        }
    }
    return $nets
}
proc pr_number {s} {
    if {[regexp -nocase {^([0-9]+)([KMG])$} $s -> n unit]} {
        return [expr {$n * (1 << (10 * (1 + [string first [string toupper $unit] KMG])))}]
    }
    return [expr {wide($s)}]
}
proc pr_fixed_segment {space slave name offset size} {
    set expected [format %s/%s $space $name]
    foreach seg [get_bd_addr_segs -quiet -of_objects $space] {
        set base [get_property OFFSET $seg]
        set span [get_property RANGE $seg]
        if {$base eq "" || $span eq ""} { continue }
        set base [pr_number $base]
        set span [pr_number $span]
        if {$seg eq $expected} {
            if {$base != $offset || $span != $size} { error "Existing $seg has incorrect fixed range" }
            return
        }
        if {$base < $offset + $size && $offset < $base + $span} {
            error [format "Fixed address conflict: %s overlaps 0x%08x..0x%08x; original mapping unchanged" $seg $offset [expr {$offset+$size-1}]]
        }
    }
    create_bd_addr_seg -range $size -offset $offset $space $slave $name
}

set ps [pr_one [get_bd_cells -quiet processing_system7_0] PS7]
set freq [get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $ps]
if {abs(double($freq) - 100.0) > 0.001} { error "Existing FCLK0 must be 100MHz, got $freq; do not retime capture chain silently" }
set xbar [pr_one [get_bd_cells -quiet ps7_0_axi_periph] ps7_0_axi_periph]
set smc [pr_one [get_bd_cells -quiet remap_hp_smc] remap_hp_smc]
set mi [get_property CONFIG.NUM_MI $xbar]
set si [get_property CONFIG.NUM_SI $smc]
if {$mi ni {7 9} || $si ni {3 4}} { error "Unexpected existing interconnect sizes MI=$mi SI=$si; inspect before changing" }
# M00..M06 and S00..S02 are untouched. Guard is slave-only, NOT an HP master.
set_property CONFIG.NUM_MI {9} $xbar
set_property CONFIG.NUM_SI {4} $smc
set core [get_bd_cells -quiet pl_remap_accel_0]
if {![llength $core]} {
    set core [create_bd_cell -type ip -vlnv xilinx.com:hls:pl_remap_accel:1.0 pl_remap_accel_0]
} elseif {[get_property VLNV $core] ne "xilinx.com:hls:pl_remap_accel:1.0"} {
    error "Wrong VLNV at pl_remap_accel_0"
}
set guard [get_bd_cells -quiet remap_axi_guard_0]
if {![llength $guard]} {
    create_bd_cell -type module -reference remap_axi_guard remap_axi_guard_0
} elseif {[get_property REF_NAME $guard] ne "remap_axi_guard"} {
    error "Wrong module at remap_axi_guard_0"
}
pr_connect ps7_0_axi_periph/M07_AXI pl_remap_accel_0/s_axi_control 1
pr_connect ps7_0_axi_periph/M08_AXI remap_axi_guard_0/S_AXI 1
pr_connect pl_remap_accel_0/m_axi_gmem remap_hp_smc/S03_AXI 1
# Existing HP0 path must still be the capture/UDP shared DDR path.
pr_connect remap_hp_smc/M00_AXI processing_system7_0/S_AXI_HP0 1
foreach pin {pl_remap_accel_0/ap_clk remap_axi_guard_0/aclk ps7_0_axi_periph/M07_ACLK ps7_0_axi_periph/M08_ACLK} {
    pr_connect processing_system7_0/FCLK_CLK0 $pin 0
}
foreach pin {pl_remap_accel_0/ap_rst_n remap_axi_guard_0/aresetn ps7_0_axi_periph/M07_ARESETN ps7_0_axi_periph/M08_ARESETN} {
    pr_connect rst_ps7_0_50M/peripheral_aresetn $pin 0
}
# The six guard response taps are deliberately NOT connected.
# pl_remap_accel_0/m_axi_gmem is bound to an AXI4 *interface* net. A scalar
# connect_bd_net onto a member of an interface net makes Vivado override the
# interface connection for that pin, which drops the master's RVALID/RRESP/
# BVALID/BRESP inputs and ties them to 0 (verified: BD 41-1271 + 41-759, the
# DDR read path then never completes). There is no supported way to attach a
# scalar monitor to an interface-net member in the block design.
# Consequence, stated explicitly: the guard provides identity (ID/ABI) and a
# clear-on-write flag register only; it does NOT observe AXI responses. Real
# AXI faults are caught by the software watchdog timeout and the fatal latch
# in remap.py, not by this block.
# The guard's observation inputs stay unwired on purpose (see the note above).
# They are driven by explicit constant cells instead of being left floating, so
# the block design carries no partially-connected AXI monitor and no unresolved
# critical warnings. With these ties the monitor can never report a fault, and
# the software contract is unchanged: identity/ABI still gate PL mode, flags
# stay clear, and real AXI faults surface as the remap timeout + fatal latch.
foreach {name width value pins} {
    guard_tie1_0 1 0 {rvalid rready bvalid bready}
    guard_tie2_0 2 0 {rresp bresp}
} {
    set cell [get_bd_cells -quiet $name]
    if {![llength $cell]} {
        set cell [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 $name]
        set_property -dict [list CONFIG.CONST_WIDTH $width CONFIG.CONST_VAL $value] $cell
    }
    foreach pin $pins {
        pr_connect $name/dout remap_axi_guard_0/$pin 0
    }
}
set ps_space [pr_one [get_bd_addr_spaces -quiet processing_system7_0/Data] PS_Data]
set ctrl [pr_one [get_bd_addr_segs -quiet pl_remap_accel_0/s_axi_control/*] HLS_control_segment]
set guard_seg [pr_one [get_bd_addr_segs -quiet remap_axi_guard_0/S_AXI/*] guard_segment]
# Check actual assigned slave segments, NOT the PS GP0 1GiB address aperture.
pr_fixed_segment $ps_space $ctrl SEG_pl_remap_ctrl 0x40000000 0x10000
pr_fixed_segment $ps_space $guard_seg SEG_remap_guard 0x40020000 0x10000
set master_space [pr_one [get_bd_addr_spaces -quiet -of_objects [get_bd_intf_pins pl_remap_accel_0/m_axi_gmem]] HLS_master_space]
set ddr [pr_one [get_bd_addr_segs -quiet processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] HP0_DDR]
pr_fixed_segment $master_space $ddr SEG_HP0_DDR 0x00000000 0x40000000
validate_bd_design
save_bd_design
set wrappers [make_wrapper -files [get_files $bdfile] -top]
foreach wrapper $wrappers {
    if {![llength [get_files -quiet $wrapper]]} { add_files -norecurse $wrapper }
}
update_compile_order -fileset sources_1
puts "PL_REMAP_BD_READY: M07 core@0x40000000; M08 guard@0x40020000; HP S03; 100MHz"
close_project
