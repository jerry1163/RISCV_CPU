`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/10/03 15:48:48
// Design Name: 
// Module Name: riscv_alu_decode
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


module riscv_alu_decode(
    input [1:0] alu_opcode,
    input [2:0] funct3,
    input [6:0] funct7,
    output reg [3:0] alu_ctl
    );

    always @(*) begin
      // Conservative default: address calculation / unknown combinations -> ADD
      alu_ctl = 4'b0010;

      case (alu_opcode)
        2'b00: begin
          // load/store/jalr class
          alu_ctl = 4'b0010; // ADD
        end

        2'b01: begin
          // branch class
          case (funct3)
            3'b000: alu_ctl = 4'b0110; // beq  -> SUB
            3'b001: alu_ctl = 4'b0110; // bne  -> SUB
            3'b100: alu_ctl = 4'b0111; // blt  -> SLT
            3'b101: alu_ctl = 4'b0111; // bge  -> SLT
            3'b110: alu_ctl = 4'b0101; // bltu -> SLTU
            3'b111: alu_ctl = 4'b0101; // bgeu -> SLTU
            default: alu_ctl = 4'b0110; // conservative branch compare -> SUB
          endcase
        end

        2'b10: begin
          // R-type ALU class
          case (funct3)
            3'b000: alu_ctl = funct7[5] ? 4'b0110 : 4'b0010; // sub/add
            3'b001: alu_ctl = 4'b0011; // sll
            3'b010: alu_ctl = 4'b0111; // slt
            3'b011: alu_ctl = 4'b0101; // sltu
            3'b100: alu_ctl = 4'b1100; // xor
            3'b101: alu_ctl = funct7[5] ? 4'b1111 : 4'b1011; // sra/srl
            3'b110: alu_ctl = 4'b0001; // or
            3'b111: alu_ctl = 4'b0000; // and
            default: alu_ctl = 4'b0010; // ADD
          endcase
        end

        2'b11: begin
          // I-type ALU class
          case (funct3)
            3'b000: alu_ctl = 4'b0010; // addi
            3'b001: alu_ctl = 4'b0011; // slli
            3'b010: alu_ctl = 4'b0111; // slti
            3'b011: alu_ctl = 4'b0101; // sltiu
            3'b100: alu_ctl = 4'b1100; // xori
            3'b101: alu_ctl = funct7[5] ? 4'b1111 : 4'b1011; // srai/srli
            3'b110: alu_ctl = 4'b0001; // ori
            3'b111: alu_ctl = 4'b0000; // andi
            default: alu_ctl = 4'b0010; // ADD
          endcase
        end

        default: begin
          alu_ctl = 4'b0010; // ADD
        end
      endcase
    end

endmodule
