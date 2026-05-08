`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/10/03 15:17:25
// Design Name: 
// Module Name: riscv_imm_gen
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


module riscv_imm_gen#(
    parameter bitwidth = 32
    )(
    input [31:0] inst,
    output reg [bitwidth-1:0] imm
    );
    
    wire [6:0] opcode;
    assign opcode = inst[6:0];
    
    always @(*) begin
      casez (opcode)
        7'b0010011, // OP-IMM (addi/andi/ori/xori/slli/srli/srai/slti/sltiu)
        7'b0000011, // LOAD
        7'b1100111: // JALR
          imm = {{(bitwidth-12){inst[31]}}, inst[31:20]}; // I-type

        7'b0100011: // STORE
          imm = {{(bitwidth-12){inst[31]}}, inst[31:25], inst[11:7]}; // S-type

        7'b1100011: // BRANCH
          imm = {{(bitwidth-13){inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}; // B-type

        7'b0110111, // LUI
        7'b0010111: // AUIPC
          imm = {{(bitwidth-32){inst[31]}}, inst[31:12], 12'b0}; // U-type

        7'b1101111: // JAL
          imm = {{(bitwidth-21){inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}; // J-type

        default:
          imm = {bitwidth{1'b0}}; // conservative default
      endcase
    end
    
endmodule
