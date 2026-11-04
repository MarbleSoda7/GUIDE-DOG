# Copy-only preparation. No source globs, synthesis, implementation or SD writes.
set root [file normalize [file dirname [info script]]]
set proj [file join $root guide_linux_base.xpr]
proc pr_inside {path root} {
    set p [string tolower [file normalize $path]]
    set r [string tolower [file normalize $root]]
    return [expr {$p eq $r || [string first "$r/" $p] == 0}]
}
if {[llength [get_projects -quiet]] == 0} { open_project $proj }
if {![pr_inside [get_property DIRECTORY [current_project]] $root]} {
    error "Refusing project outside copied project directory"
}
# Validate only explicitly registered active sources, never glob historical RTL.
foreach fs {sources_1 constrs_1} {
    foreach f [get_files -quiet -of_objects [get_filesets $fs]] {
        set name [get_property NAME $f]
        if {![pr_inside $name $root]} { error "External active source: $name; run copy-local relocation first" }
        if {![file exists $name] && [file extension $name] ni {.v .vhd}} { error "Missing source: $name" }
    }
}
set repos [list [file join $root ip_repo]]
if {[file isdirectory [file join $root hls_ip_repo]]} { lappend repos [file join $root hls_ip_repo] }
set_property ip_repo_paths $repos [current_project]
update_ip_catalog -rebuild
set guard [file join $root rtl remap_axi_guard.v]
if {![file isfile $guard]} { error "Missing canonical guard: $guard" }
if {![llength [get_files -quiet $guard]]} { add_files -norecurse $guard }
# Do not reuse inherited synthesis checkpoints in a new build.
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
catch {set_property INCREMENTAL_CHECKPOINT {} [get_runs synth_1]}
update_compile_order -fileset sources_1
puts "PL_RECTIFY_COPY_READY=$root"
