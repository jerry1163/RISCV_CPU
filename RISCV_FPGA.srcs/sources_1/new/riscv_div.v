`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/08/17 20:36:19
// Design Name: 
// Module Name: riscv_div
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


module riscv_div#(
    parameter bitwidth = 32
)(
    input clk,rst_n,
    input [bitwidth-1:0] data_din_1, data_din_2,
    input is_opr_signed_i, wr_en_i, div_rem_n_flag_i,
    input [4:0] rd_idx_i,
    output stall_o,
    output is_opr_signed_o, wr_en_o, div_rem_n_flag_o,
    output [4:0] rd_idx_o,
    output [bitwidth-1:0] dout
    );
    wire [bitwidth:0] data_din_1_s,data_din_2_s;
    assign data_din_1_s = {is_opr_signed_i & data_din_1[bitwidth-1],data_din_1};
    assign data_din_2_s = {is_opr_signed_i & data_din_2[bitwidth-1],data_din_2};

    wire [2:0] user;
    assign user = {is_opr_signed_i, div_rem_n_flag_i, wr_en_i};
    wire data_valid;
    wire [79:0] m_axis_dout_tdata;
    wire [7:0] m_axis_dout_tuser;

    reg stall;

    div_gen_latency_16 div (
    .aclk(clk),
    .s_axis_divisor_tvalid(1'b1),    // input wire s_axis_divisor_tvalid
    .s_axis_divisor_tuser(rd_idx_i),      // input wire [4 : 0] s_axis_divisor_tuser
    .s_axis_divisor_tdata(data_din_2_s),      // input wire [39 : 0] s_axis_divisor_tdata
    .s_axis_dividend_tvalid(1'b1),  // input wire s_axis_dividend_tvalid
    .s_axis_dividend_tuser(user),    // input wire [2 : 0] s_axis_dividend_tuser
    .s_axis_dividend_tdata(data_din_1_s),    // input wire [39 : 0] s_axis_dividend_tdata
    .m_axis_dout_tvalid(data_valid),          // output wire m_axis_dout_tvalid
    .m_axis_dout_tuser(m_axis_dout_tuser),            // output wire [7 : 0] m_axis_dout_tuser
    .m_axis_dout_tdata(m_axis_dout_tdata)            // output wire [79 : 0] m_axis_dout_tdata
    );

    assign is_opr_signed_o = m_axis_dout_tuser[7];
    assign div_rem_n_flag_o = m_axis_dout_tuser[6];
    assign wr_en_o = m_axis_dout_tuser[5];
    assign rd_idx_o = m_axis_dout_tuser[4:0];

    assign dout = div_rem_n_flag_o ? m_axis_dout_tdata[71:40] : m_axis_dout_tdata[31:0];
    
    always @(posedge clk) begin
        if(!rst_n) stall <= 1'b0;
        else if(wr_en_i) stall <= 1'b1;
        else if(data_valid && wr_en_o) stall <= 1'b0;
        else stall <= stall;
    end
    assign stall_o = wr_en_i | stall;
endmodule
