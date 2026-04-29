create_clock -name clk_mul -period 5 [get_ports clk]
create_clock -name clk -period 8.333 [get_ports CLK_FPGA]
