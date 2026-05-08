# The board input clock is constrained by clk_wiz_sys.xdc.
create_clock -name clk_mul -period 5 [get_ports clk]
create_clock -name clk -period 10 [get_ports CLK_FPGA]