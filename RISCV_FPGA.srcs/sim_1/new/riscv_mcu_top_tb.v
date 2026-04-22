`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/11/01 13:16:06
// Design Name: 
// Module Name: riscv_mcu_top_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module riscv_mcu_top_tb(

    );
    wire [31:0] PA = 32'h87654321;
    reg clk_sim;
    initial begin
      clk_sim = 0;
      forever #5 clk_sim = ~clk_sim;
    end
    riscv_mcu_tdpram_top uut(
      .CLK_FPGA(clk_sim),
      .PA(PA)
    );
endmodule
