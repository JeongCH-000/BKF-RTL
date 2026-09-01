# Vivado is intentionally not run by the macOS regression. Invoke later with:
#   TARGET_FPGA_PART=<part> VIVADO_CONFIG=<name|all> \
#     vivado -mode batch -source scripts/vivado/run_all.tcl
if {![info exists ::env(TARGET_FPGA_PART)] || $::env(TARGET_FPGA_PART) eq ""} {
    error "Set TARGET_FPGA_PART before running this script"
}
set target_part $::env(TARGET_FPGA_PART)
set selected_config "all"
if {[info exists ::env(VIVADO_CONFIG)] && $::env(VIVADO_CONFIG) ne ""} {
    set selected_config [string tolower [string trim $::env(VIVADO_CONFIG)]]
}
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ".." ".."]]
set report_root [file join $root_dir "results" "vivado"]
file mkdir $report_root
cd $root_dir

set common_sources [list \
    rtl/common/fx_divider_q8_16.v \
    rtl/nonlinear/q8_16_rsqrt_lut.v \
    rtl/nonlinear/arcsine_cov_lut_q8_16.v \
    rtl/bkf/bkf_core.v]

set configurations [list \
    [list ekf_l1 ekf_core "" [list rtl/ekf/ekf_core.v]] \
    [list bkf_l1 bkf_l1_core "" [list rtl/bkf/bkf_l1_core.v]] \
    [list rbkf_l1 rbkf_core NUM_BRANCHES=1 [list rtl/rbkf/rbkf_core.v]] \
    [list rbkf_l8 rbkf_core NUM_BRANCHES=8 [list rtl/rbkf/rbkf_core.v]]]

set valid_configurations [list all]
foreach configuration $configurations {
    lappend valid_configurations [lindex $configuration 0]
}
if {[lsearch -exact $valid_configurations $selected_config] < 0} {
    error "Unknown VIVADO_CONFIG '$selected_config'; choose one of: $valid_configurations"
}

puts "Vivado target part: $target_part"
puts "Vivado configuration: $selected_config"

foreach configuration $configurations {
    lassign $configuration name top generic extra_sources
    if {$selected_config ne "all" && $name ne $selected_config} {
        continue
    }
    puts "Starting configuration: $name (top=$top, generic=$generic)"
    set output_dir [file join $report_root $name]
    file mkdir $output_dir
    create_project -in_memory -part $target_part
    read_verilog -include_dirs [list $root_dir] $common_sources
    read_verilog -include_dirs [list $root_dir] $extra_sources
    read_xdc constraints/common_clock.xdc
    if {$generic eq ""} {
        synth_design -top $top -part $target_part -mode out_of_context
    } else {
        synth_design -top $top -part $target_part -mode out_of_context -generic $generic
    }
    report_utilization -file [file join $output_dir utilization_post_synth.rpt]
    report_timing_summary -file [file join $output_dir timing_post_synth.rpt]
    opt_design
    place_design
    phys_opt_design
    route_design
    report_utilization -file [file join $output_dir utilization_post_route.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained \
        -file [file join $output_dir timing_post_route.rpt]
    check_timing -verbose -file [file join $output_dir check_timing_post_route.rpt]
    report_drc -file [file join $output_dir drc_post_route.rpt]
    report_power -file [file join $output_dir power_post_route.rpt]
    write_checkpoint -force [file join $output_dir post_route.dcp]
    close_project
    puts "Completed configuration: $name"
}
