run 3000ns

set cpu /riscv_mcu_top_tb/uut/riscv_cpu_inst
set rf  /riscv_mcu_top_tb/uut/riscv_cpu_inst/riscv_reg_file_inst/x

puts "pc=[get_value -radix hex $cpu/pc]"
puts "if_id_valid=[get_value $cpu/if_id_valid] if_id_pc=[get_value -radix hex $cpu/if_id_pc] if_id_inst=[get_value -radix hex $cpu/if_id_inst]"
puts "id_ex_valid=[get_value $cpu/id_ex_valid] id_ex_pc=[get_value -radix hex $cpu/id_ex_pc]"
puts "ex_mem_valid=[get_value $cpu/ex_mem_valid] mem_wb_valid=[get_value $cpu/mem_wb_valid]"
puts "last_wb_rd=[get_value -radix unsigned $cpu/mem_wb_rd_idx] last_wb_data=[get_value -radix hex $cpu/mem_wb_wb_data]"

for {set i 1} {$i < 32} {incr i} {
  set sig [format {%s[%d]} $rf $i]
  puts [format "x%02d=%s" $i [get_value -radix hex $sig]]
}

quit
