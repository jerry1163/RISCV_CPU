set script_dir [file normalize [file dirname [info script]]]
set repo_dir [file normalize [file join $script_dir ".."]]

open_project [file join $repo_dir RISCV_FPGA.xpr]

set synth_run synth_2
set impl_run impl_2

set_property strategy Performance_Explore [get_runs $impl_run]

reset_run $impl_run
reset_run $synth_run

launch_runs $synth_run -jobs 2
wait_on_run $synth_run
if {[get_property PROGRESS [get_runs $synth_run]] ne "100%"} {
  error "$synth_run did not complete successfully"
}

launch_runs $impl_run -to_step route_design -jobs 2
wait_on_run $impl_run
if {[get_property PROGRESS [get_runs $impl_run]] ne "100%"} {
  error "$impl_run did not complete successfully"
}

open_run $impl_run
report_timing_summary -max_paths 10 -warn_on_violation -file [file join $repo_dir RISCV_FPGA.runs $impl_run riscv_mcu_tdpram_top_timing_summary_routed.rpt]

close_project
