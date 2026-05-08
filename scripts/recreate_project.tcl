# Recreate the Vivado project from repository-relative paths.
# Usage from Vivado Tcl Console:
#   cd <repo-root>
#   source scripts/recreate_project.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_dir [file normalize [file join $script_dir ".."]]
set project_name RISCV_FPGA
set part_name xc7a100tfgg676-2

cd $repo_dir

create_project $project_name $repo_dir -part $part_name -force
set_property source_mgmt_mode DisplayOnly [current_project]

add_files -norecurse [list \
  [file join $repo_dir RISCV_FPGA.srcs/sources_1/new/riscv_alu.v] \
  [file join $repo_dir RISCV_FPGA.srcs/sources_1/new/riscv_alu_decode.v] \
  [file join $repo_dir RISCV_FPGA.srcs/sources_1/new/riscv_cpu.v] \
  [file join $repo_dir RISCV_FPGA.srcs/sources_1/new/riscv_imm_gen.v] \
  [file join $repo_dir RISCV_FPGA.srcs/sources_1/new/riscv_inst_decode.v] \
  [file join $repo_dir RISCV_FPGA.srcs/sources_1/new/riscv_mcu_tdpram_top.v] \
  [file join $repo_dir RISCV_FPGA.srcs/sources_1/new/riscv_pc_gen.v] \
  [file join $repo_dir RISCV_FPGA.srcs/sources_1/new/riscv_reg_file.v] \
  [file join $repo_dir test6_tdp.coe] \
  [file join $repo_dir test7_tdp.coe] \
]

add_files -fileset constrs_1 -norecurse [list \
  [file join $repo_dir RISCV_FPGA.srcs/constrs_1/new/mul_para.xdc] \
]

add_files -fileset sim_1 -norecurse [list \
  [file join $repo_dir RISCV_FPGA.srcs/sim_1/new/riscv_mcu_top_tb.v] \
]

add_files -norecurse [list \
  [file join $repo_dir RISCV_FPGA.srcs/sources_1/ip/clk_wiz_sys/clk_wiz_sys.xci] \
  [file join $repo_dir RISCV_FPGA.srcs/sources_1/ip/tdp_bram/tdp_bram.xci] \
]

set_property top riscv_mcu_tdpram_top [current_fileset]
set_property top riscv_mcu_top_tb [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

foreach ip_name [get_ips] {
  puts "Generating output products for $ip_name"
  generate_target all [get_ips $ip_name]
}

puts "Project recreated at: [file join $repo_dir ${project_name}.xpr]"

