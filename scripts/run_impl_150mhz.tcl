set script_dir [file normalize [file dirname [info script]]]
set repo_dir [file normalize [file join $script_dir ".."]]

open_project [file join $repo_dir RISCV_FPGA.xpr]

set clk_ip [get_ips clk_wiz_sys]
set_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {150.000} $clk_ip
generate_target all $clk_ip

if {[llength [get_runs clk_wiz_sys_synth_1]]} {
  reset_run clk_wiz_sys_synth_1
} else {
  create_ip_run $clk_ip
}
launch_runs clk_wiz_sys_synth_1 -jobs 2
wait_on_run clk_wiz_sys_synth_1

reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1

reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1

open_run impl_1
report_timing_summary -max_paths 10 -warn_on_violation \
  -file [file join $repo_dir RISCV_FPGA.runs impl_1 riscv_mcu_tdpram_top_timing_summary_routed.rpt]

close_project
