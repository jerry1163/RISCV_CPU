`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/10/03 16:39:23
// Design Name: 
// Module Name: riscv_pc_gen
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


module riscv_pc_gen#(
    parameter bitwidth = 32
    )(
    input rst_n,
    input [4:0] branch_opcode,
    input pc_gen_src,
    input [bitwidth-1:0] pc,
    input [bitwidth-1:0] imm,
    input [bitwidth-1:0] alu_data,
    input alu_zero_flag,
    output reg [bitwidth-1:0] pc_next,
    output [bitwidth-1:0] pc_gen_data
    );
    
    wire [bitwidth-1:0] pc_i = pc + imm;
    wire [bitwidth-1:0] pc_4 = pc + 4;
    assign pc_gen_data = pc_gen_src ? pc_i : pc_4; // auipc
    
    always @(*) begin
      if (!rst_n) begin
        pc_next = {bitwidth{1'b0}};
      end
      else begin
        casez(branch_opcode)
          5'b1??01: pc_next = (branch_opcode[2] ^ alu_data[0]) ? pc_i : pc_4; // blt(u) & bge(u)
          5'b00?01: pc_next = (branch_opcode[2] ^ (alu_data == {bitwidth{1'b0}})) ? pc_i : pc_4;  // beq & bne
          5'b00011: pc_next = alu_data;  // jalr
          5'b00111: pc_next = pc_i;      // jal
          5'b01011: pc_next = pc;        // break
          5'b00000: pc_next = pc_4;      // no branch
           default: pc_next = pc_4;
        endcase
      end
    end
endmodule
