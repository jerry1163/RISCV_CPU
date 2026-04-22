`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/09/27 21:34:58
// Design Name: 
// Module Name: riscv_reg_file
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


module riscv_reg_file #(
    parameter bitwidth = 32
    )(
    input clk, rst_n, wr_en,
    input [4:0] rd_idx_1, rd_idx_2, wr_idx,
    input [bitwidth-1:0] wr_data,
    output [bitwidth-1:0] rd_dout_1, rd_dout_2
    );
    
    reg [bitwidth-1:0] x [0:31];
    integer i;

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        for (i = 0; i < 32; i = i + 1)
          x[i] <= {bitwidth{1'b0}};
      end
      else begin
        if (wr_en && (wr_idx != 5'd0))
          x[wr_idx] <= wr_data;
        x[0] <= {bitwidth{1'b0}};
      end
    end

    assign rd_dout_1 = (rd_idx_1 == 5'd0) ? {bitwidth{1'b0}} : x[rd_idx_1];
    assign rd_dout_2 = (rd_idx_2 == 5'd0) ? {bitwidth{1'b0}} : x[rd_idx_2];

endmodule
