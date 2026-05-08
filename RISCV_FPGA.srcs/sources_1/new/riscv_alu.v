`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/09/27 09:18:23
// Design Name: 
// Module Name: riscv_alu
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


module riscv_alu #(
    parameter bitwidth = 32
    )(
    input [3:0] ctl_in,
    input [bitwidth-1:0] din_a, din_b,
    output [bitwidth-1:0] dout,
    output zero_flag
    );
    
    wire signed [bitwidth-1:0] din_a_s, din_b_s;
    reg  [bitwidth-1:0] dout_r;
    
    assign din_a_s = din_a;
    assign din_b_s = din_b;
    assign dout = dout_r;
    assign zero_flag = (dout_r == {bitwidth{1'b0}});

    always @(*) begin
      case (ctl_in)
        4'b0000: dout_r = din_a & din_b;                          // AND
        4'b0001: dout_r = din_a | din_b;                          // OR
        4'b0010: dout_r = din_a + din_b;                          // ADD
        4'b0110: dout_r = din_a - din_b;                          // SUB
        4'b0111: dout_r = (din_a_s < din_b_s) ? {{(bitwidth-1){1'b0}}, 1'b1} : {bitwidth{1'b0}}; // SLT
        4'b0101: dout_r = (din_a   < din_b)   ? {{(bitwidth-1){1'b0}}, 1'b1} : {bitwidth{1'b0}}; // SLTU
        4'b1100: dout_r = din_a ^ din_b;                          // XOR
        4'b0011: dout_r = din_a << din_b[4:0];                    // SLL
        4'b1011: dout_r = din_a >> din_b[4:0];                    // SRL
        4'b1111: dout_r = din_a_s >>> din_b[4:0];                 // SRA
        default: dout_r = {bitwidth{1'b0}};                       // conservative default
      endcase
    end

endmodule
