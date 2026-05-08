`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/09/27 09:18:23
// Design Name: 
// Module Name: riscv_mul_para
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


module riscv_mul_para #(parameter bitwidth = 32) (
    input clk,
    input [bitwidth-1:0] din_a, din_b,
    output reg [bitwidth*2-1:0] dout = 0
    );
    
    reg [bitwidth-1:0] din_a_r, din_b_r;
    always @(posedge clk) begin din_a_r <= din_a; din_b_r <= din_b; end
    
    genvar i;
    reg [bitwidth-1:0] bitwise_prod [0:bitwidth-1];
    generate
      for (i = 0; i < bitwidth; i = i + 1) begin
        always @(*) bitwise_prod[i] <= din_a_r & {bitwidth{din_b_r[i]}};
      end
    endgenerate
    
    reg [bitwidth-1+2:0] sum_s1 [0:bitwidth/2-1];
    generate
      for (i = 0; i < bitwidth/2; i = i + 1) begin
        always @(posedge clk) sum_s1[i] <= bitwise_prod[i*2] + {bitwise_prod[i*2+1], 1'd0};
      end
    endgenerate
    
    reg [bitwidth-1+4:0] sum_s2 [0:bitwidth/4-1];
    generate
      for (i = 0; i < bitwidth/4; i = i + 1) begin
        always @(*) sum_s2[i] <= sum_s1[i*2] + {sum_s1[i*2+1], 2'd0};
      end
    endgenerate
    
    reg [bitwidth-1+8:0] sum_s3 [0:bitwidth/8-1];
    generate
      for (i = 0; i < bitwidth/8; i = i + 1) begin
        always @(posedge clk) sum_s3[i] <= sum_s2[i*2] + {sum_s2[i*2+1], 4'd0};
      end
    endgenerate
    
    reg [bitwidth-1+16:0] sum_s4 [0:bitwidth/16-1];
    generate
      for (i = 0; i < bitwidth/16; i = i + 1) begin
        always @(posedge clk) sum_s4[i] <= sum_s3[i*2] + {sum_s3[i*2+1], 8'd0};
      end
    endgenerate
    
    reg [bitwidth-1+32:0] sum_s5 [0:bitwidth/32-1];
    generate
      for (i = 0; i < bitwidth/32; i = i + 1) begin
        always @(*) sum_s5[i] <= sum_s4[i*2] + {sum_s4[i*2+1], 16'd0};
      end
    endgenerate
    
    always @(posedge clk) dout <= sum_s5[0];
endmodule
