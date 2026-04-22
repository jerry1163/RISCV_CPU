`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/09/27 23:49:35
// Design Name: 
// Module Name: riscv_inst_decode
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


module riscv_inst_decode (
    input      [31:0] inst,
    output     [ 2:0] funct3,
    output     [ 6:0] funct7,
    output reg [ 1:0] alu_opcode,
    output            alu_src_b_is_imm,
    output reg [ 1:0] reg_wr_src,
    output            reg_wr_en,
    output            mem_wr_en,
    output            mem_rd_en,
    output reg [ 4:0] branch_opcode,
    output reg        pc_gen_src,
    output reg        opr_is_32b = 0,
    output reg [ 7:0] mem_byte_mask,
    output            ld_unsigned,
    output            ebreak,
    output            ecall
);

    wire [6:0] opcode = inst[6:0];
    reg        alu_src_b_is_imm_r;
    reg        reg_wr_en_r;
    reg        mem_wr_en_r;
    reg        mem_rd_en_r;
    reg        ld_unsigned_r;
    reg        ebreak_r;
    reg        ecall_r;

    assign funct3           = inst[14:12];
    assign funct7           = inst[31:25];
    assign alu_src_b_is_imm = alu_src_b_is_imm_r;
    assign reg_wr_en        = reg_wr_en_r;
    assign mem_wr_en        = mem_wr_en_r;
    assign mem_rd_en        = mem_rd_en_r;
    assign ld_unsigned      = ld_unsigned_r;
    assign ebreak           = ebreak_r;
    assign ecall            = ecall_r;

    always @(*) begin
        // defaults to avoid latches/X-propagation
        alu_opcode        = 2'b00;
        alu_src_b_is_imm_r = 1'b0;
        reg_wr_src        = 2'b00;
        reg_wr_en_r       = 1'b0;
        mem_wr_en_r       = 1'b0;
        mem_rd_en_r       = 1'b0;
        branch_opcode     = 5'b00000;
        pc_gen_src        = 1'b0;
        opr_is_32b        = 1'b0;
        mem_byte_mask     = 8'h00;
        ld_unsigned_r     = 1'b0;
        ebreak_r          = 1'b0;
        ecall_r           = 1'b0;

        case (opcode)
            // R-type ALU: add/sub/and/or/xor/sll/srl/sra/slt/sltu
            7'b0110011: begin
                alu_opcode         = 2'b10;
                alu_src_b_is_imm_r = 1'b0;
                reg_wr_src         = 2'b00; // ALU
                reg_wr_en_r        = 1'b1;
            end

            // I-type ALU: addi/andi/ori/xori/slli/srli/srai/slti/sltiu
            7'b0010011: begin
                alu_opcode         = 2'b11;
                alu_src_b_is_imm_r = 1'b1;
                reg_wr_src         = 2'b00; // ALU
                reg_wr_en_r        = 1'b1;
            end

            // Load: lw
            7'b0000011: begin
                alu_opcode         = 2'b00; // address add
                alu_src_b_is_imm_r = 1'b1;
                reg_wr_src         = 2'b01; // Memory
                reg_wr_en_r        = 1'b1;
                mem_rd_en_r        = 1'b1;
                mem_byte_mask      = 8'h0F; // low 4 bits valid (word)
                ld_unsigned_r      = funct3[2];
            end

            // Store: sw
            7'b0100011: begin
                alu_opcode         = 2'b00; // address add
                alu_src_b_is_imm_r = 1'b1;
                mem_wr_en_r        = 1'b1;
                mem_byte_mask      = 8'h0F; // low 4 bits valid (word)
            end

            // Branch: beq/blt/bltu/bge/bgeu (and bne-compatible encoding)
            7'b1100011: begin
                alu_opcode         = 2'b01;
                alu_src_b_is_imm_r = 1'b0;
                branch_opcode      = {funct3, 2'b01};
            end

            // JAL
            7'b1101111: begin
                reg_wr_src    = 2'b10; // PC generator
                reg_wr_en_r   = 1'b1;
                branch_opcode = 5'b00111; // pc_next = pc + imm
                pc_gen_src    = 1'b0;     // write-back uses pc+4
            end

            // JALR
            7'b1100111: begin
                alu_opcode         = 2'b00; // rs1 + imm
                alu_src_b_is_imm_r = 1'b1;
                reg_wr_src         = 2'b10; // PC generator
                reg_wr_en_r        = 1'b1;
                branch_opcode      = 5'b00011; // pc_next = alu_data
                pc_gen_src         = 1'b0;     // write-back uses pc+4
            end

            // LUI: direct immediate write-back path
            7'b0110111: begin
                alu_opcode         = 2'b00; // add
                alu_src_b_is_imm_r = 1'b1;
                reg_wr_src         = 2'b11; // Immediate
                reg_wr_en_r        = 1'b1;
            end

            // AUIPC: write pc+imm through pc_gen_data
            7'b0010111: begin
                reg_wr_src  = 2'b10; // PC generator
                reg_wr_en_r = 1'b1;
                pc_gen_src  = 1'b1;  // pc_gen_data = pc + imm
            end

            // System opcodes are not needed by test6; keep conservative behavior.
            7'b1110011: begin
                branch_opcode = 5'b01011; // hold pc if encountered
                ebreak_r      = inst[20];
                ecall_r       = ~inst[20];
            end

            default: begin
                // keep defaults
            end
        endcase
    end

endmodule
