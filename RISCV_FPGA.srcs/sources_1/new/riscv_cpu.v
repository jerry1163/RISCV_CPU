`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/09/27 22:24:28
// Design Name: 
// Module Name: riscv_cpu
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


module riscv_cpu #(
    parameter bitwidth = 32
    )(
    input clk, rst_n,
    input [31:0] inst,
    output [bitwidth-1:0] inst_bram_addr,
    input [bitwidth-1:0] data_bram_rd_data,
    output [bitwidth-1:0] data_bram_addr,
    output [bitwidth-1:0] data_bram_wr_data,
    output [3:0] data_bram_wr_byte_mask,
    output data_bram_wr_en, data_bram_rd_en
    );

    wire [4:0] rs1_idx = inst[19:15];
    wire [4:0] rs2_idx = inst[24:20];
    wire [4:0] rd_idx  = inst[11:7];

    wire [2:0] funct3;
    wire [6:0] funct7;
    wire [1:0] alu_opcode;
    wire       alu_src_b_is_imm;
    wire [1:0] reg_wr_src;
    wire       reg_wr_en;
    wire       mem_wr_en;
    wire       mem_rd_en;
    wire [4:0] branch_opcode;
    wire       pc_gen_src;
    wire       opr_is_32b;
    wire [7:0] mem_byte_mask;
    wire       ld_unsigned;
    wire       ebreak;
    wire       ecall;

    wire [bitwidth-1:0] imm;
    wire [3:0]          alu_ctl;
    wire [bitwidth-1:0] reg_rd_dout_1;
    wire [bitwidth-1:0] reg_rd_dout_2;
    reg  [bitwidth-1:0] reg_wr_data;

    wire [bitwidth-1:0] alu_din_a;
    wire [bitwidth-1:0] alu_din_b;
    wire [bitwidth-1:0] alu_dout;
    wire                alu_zero_flag;

    reg [bitwidth-1:0]  pc = 0;
    wire [bitwidth-1:0] pc_next;
    wire [bitwidth-1:0] pc_gen_data;

    assign alu_din_a = reg_rd_dout_1;
    assign alu_din_b = alu_src_b_is_imm ? imm : reg_rd_dout_2;

    always @(*) begin
      case (reg_wr_src)
        2'b01: reg_wr_data = data_bram_rd_data;
        2'b10: reg_wr_data = pc_gen_data;
        2'b11: reg_wr_data = imm;
        default: reg_wr_data = alu_dout;
      endcase
    end

    riscv_inst_decode riscv_inst_decode_inst (
      .inst(inst),
      .funct3(funct3),
      .funct7(funct7),
      .alu_opcode(alu_opcode),
      .alu_src_b_is_imm(alu_src_b_is_imm),
      .reg_wr_src(reg_wr_src),
      .reg_wr_en(reg_wr_en),
      .mem_wr_en(mem_wr_en),
      .mem_rd_en(mem_rd_en),
      .branch_opcode(branch_opcode),
      .pc_gen_src(pc_gen_src),
      .opr_is_32b(opr_is_32b),
      .mem_byte_mask(mem_byte_mask),
      .ld_unsigned(ld_unsigned),
      .ebreak(ebreak),
      .ecall(ecall)
    );

    riscv_imm_gen #(
      .bitwidth(bitwidth)
    ) riscv_imm_gen_inst (
      .inst(inst),
      .imm(imm)
    );

    riscv_alu_decode riscv_alu_decode_inst (
      .alu_opcode(alu_opcode),
      .funct3(funct3),
      .funct7(funct7),
      .alu_ctl(alu_ctl)
    );

    riscv_reg_file #(
      .bitwidth(bitwidth)
    ) riscv_reg_file_inst (
      .clk(clk),
      .rst_n(rst_n),
      .wr_en(reg_wr_en),
      .rd_idx_1(rs1_idx),
      .rd_idx_2(rs2_idx),
      .wr_idx(rd_idx),
      .wr_data(reg_wr_data),
      .rd_dout_1(reg_rd_dout_1),
      .rd_dout_2(reg_rd_dout_2)
    );

    riscv_alu #(
      .bitwidth(bitwidth)
    ) riscv_alu_inst (
      .ctl_in(alu_ctl),
      .din_a(alu_din_a),
      .din_b(alu_din_b),
      .dout(alu_dout),
      .zero_flag(alu_zero_flag)
    );

    riscv_pc_gen#(
      .bitwidth(bitwidth)
    ) riscv_pc_gen_inst (
      .rst_n(rst_n),
      .branch_opcode(branch_opcode),
      .pc_gen_src(pc_gen_src),
      .pc(pc),
      .imm(imm),
      .alu_data(alu_dout),
      .alu_zero_flag(alu_zero_flag),
      .pc_next(pc_next),
      .pc_gen_data(pc_gen_data)
    );

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) pc <= 0;
      else pc <= pc_next;
    end

    assign data_bram_wr_en        = mem_wr_en;
    assign data_bram_rd_en        = mem_rd_en;
    assign data_bram_addr         = alu_dout;
    assign data_bram_wr_data      = reg_rd_dout_2;
    assign data_bram_wr_byte_mask = mem_byte_mask[3:0];
    assign inst_bram_addr         = pc;

endmodule
