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

    localparam REG_SRC_ALU = 2'b00;
    localparam REG_SRC_MEM = 2'b01;
    localparam REG_SRC_PC  = 2'b10;
    localparam REG_SRC_IMM = 2'b11;

    // IF: request PC. The block RAM has one-cycle read latency, so the
    // instruction at inst belongs to imem_resp_pc.
    reg [bitwidth-1:0] pc = 0;
    reg [bitwidth-1:0] imem_resp_pc = 0;
    reg                imem_resp_valid = 0;

    // One-entry fetch buffer used when the ID stage stalls while the next
    // instruction has already returned from the synchronous instruction RAM.
    reg                fetch_buf_valid = 0;
    reg [bitwidth-1:0] fetch_buf_pc = 0;
    reg [31:0]         fetch_buf_inst = 0;

    // IF/ID pipeline register.
    reg                if_id_valid = 0;
    reg [bitwidth-1:0] if_id_pc = 0;
    reg [31:0]         if_id_inst = 0;

    wire [4:0] id_rs1_idx = if_id_inst[19:15];
    wire [4:0] id_rs2_idx = if_id_inst[24:20];
    wire [4:0] id_rd_idx  = if_id_inst[11:7];
    wire [6:0] id_opcode  = if_id_inst[6:0];

    wire [2:0] id_funct3;
    wire [6:0] id_funct7;
    wire [1:0] id_alu_opcode;
    wire       id_alu_src_b_is_imm;
    wire [1:0] id_reg_wr_src;
    wire       id_reg_wr_en;
    wire       id_mem_wr_en;
    wire       id_mem_rd_en;
    wire [4:0] id_branch_opcode;
    wire       id_pc_gen_src;
    wire       id_opr_is_32b;
    wire [7:0] id_mem_byte_mask;
    wire       id_ld_unsigned;
    wire       id_ebreak;
    wire       id_ecall;

    wire [bitwidth-1:0] id_imm;
    wire [3:0]          id_alu_ctl;
    wire [bitwidth-1:0] reg_rd_dout_1;
    wire [bitwidth-1:0] reg_rd_dout_2;

    // MEM/WB write-back signals are also used for same-cycle ID read bypass.
    reg                mem_wb_valid = 0;
    reg [4:0]          mem_wb_rd_idx = 0;
    reg [1:0]          mem_wb_reg_wr_src = 0;
    reg                mem_wb_reg_wr_en = 0;
    reg [bitwidth-1:0] mem_wb_wb_data = 0;

    wire mem_wb_do_write = mem_wb_valid && mem_wb_reg_wr_en && (mem_wb_rd_idx != 5'd0);
    wire [bitwidth-1:0] id_rs1_data =
      (id_rs1_idx == 5'd0) ? {bitwidth{1'b0}} :
      ((mem_wb_do_write && (mem_wb_rd_idx == id_rs1_idx)) ? mem_wb_wb_data : reg_rd_dout_1);
    wire [bitwidth-1:0] id_rs2_data =
      (id_rs2_idx == 5'd0) ? {bitwidth{1'b0}} :
      ((mem_wb_do_write && (mem_wb_rd_idx == id_rs2_idx)) ? mem_wb_wb_data : reg_rd_dout_2);

    // ID/EX pipeline register.
    reg                id_ex_valid = 0;
    reg [bitwidth-1:0] id_ex_pc = 0;
    reg [31:0]         id_ex_inst = 0;
    reg [4:0]          id_ex_rs1_idx = 0;
    reg [4:0]          id_ex_rs2_idx = 0;
    reg [4:0]          id_ex_rd_idx = 0;
    reg [2:0]          id_ex_funct3 = 0;
    reg [6:0]          id_ex_funct7 = 0;
    reg [3:0]          id_ex_alu_ctl = 0;
    reg                id_ex_alu_src_b_is_imm = 0;
    reg [1:0]          id_ex_reg_wr_src = 0;
    reg                id_ex_reg_wr_en = 0;
    reg                id_ex_mem_wr_en = 0;
    reg                id_ex_mem_rd_en = 0;
    reg [4:0]          id_ex_branch_opcode = 0;
    reg                id_ex_pc_gen_src = 0;
    reg [7:0]          id_ex_mem_byte_mask = 0;
    reg                id_ex_ld_unsigned = 0;
    reg [bitwidth-1:0] id_ex_imm = 0;
    reg [bitwidth-1:0] id_ex_rs1_data = 0;
    reg [bitwidth-1:0] id_ex_rs2_data = 0;

    // EX/MEM pipeline register. Load data arrives from the RAM during this
    // stage and is captured into MEM/WB on the next clock edge.
    reg                ex_mem_valid = 0;
    reg [4:0]          ex_mem_rd_idx = 0;
    reg [1:0]          ex_mem_reg_wr_src = 0;
    reg                ex_mem_reg_wr_en = 0;
    reg                ex_mem_mem_rd_en = 0;
    reg [7:0]          ex_mem_mem_byte_mask = 0;
    reg                ex_mem_ld_unsigned = 0;
    reg [1:0]          ex_mem_addr_low = 0;
    reg [bitwidth-1:0] ex_mem_wb_data = 0;

    riscv_inst_decode riscv_inst_decode_inst (
      .inst(if_id_inst),
      .funct3(id_funct3),
      .funct7(id_funct7),
      .alu_opcode(id_alu_opcode),
      .alu_src_b_is_imm(id_alu_src_b_is_imm),
      .reg_wr_src(id_reg_wr_src),
      .reg_wr_en(id_reg_wr_en),
      .mem_wr_en(id_mem_wr_en),
      .mem_rd_en(id_mem_rd_en),
      .branch_opcode(id_branch_opcode),
      .pc_gen_src(id_pc_gen_src),
      .opr_is_32b(id_opr_is_32b),
      .mem_byte_mask(id_mem_byte_mask),
      .ld_unsigned(id_ld_unsigned),
      .ebreak(id_ebreak),
      .ecall(id_ecall)
    );

    riscv_imm_gen #(
      .bitwidth(bitwidth)
    ) riscv_imm_gen_inst (
      .inst(if_id_inst),
      .imm(id_imm)
    );

    riscv_alu_decode riscv_alu_decode_inst (
      .alu_opcode(id_alu_opcode),
      .funct3(id_funct3),
      .funct7(id_funct7),
      .alu_ctl(id_alu_ctl)
    );

    riscv_reg_file #(
      .bitwidth(bitwidth)
    ) riscv_reg_file_inst (
      .clk(clk),
      .rst_n(rst_n),
      .wr_en(mem_wb_do_write),
      .rd_idx_1(id_rs1_idx),
      .rd_idx_2(id_rs2_idx),
      .wr_idx(mem_wb_rd_idx),
      .wr_data(mem_wb_wb_data),
      .rd_dout_1(reg_rd_dout_1),
      .rd_dout_2(reg_rd_dout_2)
    );

    wire id_uses_rs1 =
      if_id_valid &&
      ((id_opcode == 7'b0110011) || // R-type
       (id_opcode == 7'b0010011) || // I-type ALU
       (id_opcode == 7'b0000011) || // load
       (id_opcode == 7'b0100011) || // store base
       (id_opcode == 7'b1100011) || // branch
       (id_opcode == 7'b1100111));  // jalr

    wire id_uses_rs2 =
      if_id_valid &&
      ((id_opcode == 7'b0110011) || // R-type
       (id_opcode == 7'b0100011) || // store data
       (id_opcode == 7'b1100011));  // branch

    wire load_use_stall =
      id_ex_valid && id_ex_mem_rd_en && (id_ex_rd_idx != 5'd0) &&
      ((id_uses_rs1 && (id_rs1_idx == id_ex_rd_idx)) ||
       (id_uses_rs2 && (id_rs2_idx == id_ex_rd_idx)));

    wire ex_mem_can_forward =
      ex_mem_valid && ex_mem_reg_wr_en && (ex_mem_rd_idx != 5'd0) &&
      (ex_mem_reg_wr_src != REG_SRC_MEM);

    wire [bitwidth-1:0] ex_rs1_fwd =
      (id_ex_rs1_idx == 5'd0) ? {bitwidth{1'b0}} :
      ((ex_mem_can_forward && (ex_mem_rd_idx == id_ex_rs1_idx)) ? ex_mem_wb_data :
      ((mem_wb_do_write && (mem_wb_rd_idx == id_ex_rs1_idx)) ? mem_wb_wb_data : id_ex_rs1_data));

    wire [bitwidth-1:0] ex_rs2_fwd =
      (id_ex_rs2_idx == 5'd0) ? {bitwidth{1'b0}} :
      ((ex_mem_can_forward && (ex_mem_rd_idx == id_ex_rs2_idx)) ? ex_mem_wb_data :
      ((mem_wb_do_write && (mem_wb_rd_idx == id_ex_rs2_idx)) ? mem_wb_wb_data : id_ex_rs2_data));

    wire [bitwidth-1:0] ex_alu_din_b = id_ex_alu_src_b_is_imm ? id_ex_imm : ex_rs2_fwd;
    wire [bitwidth-1:0] ex_alu_dout;
    wire                ex_alu_zero_flag;

    riscv_alu #(
      .bitwidth(bitwidth)
    ) riscv_alu_inst (
      .ctl_in(id_ex_alu_ctl),
      .din_a(ex_rs1_fwd),
      .din_b(ex_alu_din_b),
      .dout(ex_alu_dout),
      .zero_flag(ex_alu_zero_flag)
    );

    wire signed [bitwidth-1:0] ex_rs1_signed = ex_rs1_fwd;
    wire signed [bitwidth-1:0] ex_rs2_signed = ex_rs2_fwd;
    reg branch_taken;
    always @(*) begin
      case (id_ex_funct3)
        3'b000: branch_taken = (ex_rs1_fwd == ex_rs2_fwd);       // beq
        3'b001: branch_taken = (ex_rs1_fwd != ex_rs2_fwd);       // bne
        3'b100: branch_taken = (ex_rs1_signed < ex_rs2_signed);  // blt
        3'b101: branch_taken = (ex_rs1_signed >= ex_rs2_signed); // bge
        3'b110: branch_taken = (ex_rs1_fwd < ex_rs2_fwd);        // bltu
        3'b111: branch_taken = (ex_rs1_fwd >= ex_rs2_fwd);       // bgeu
        default: branch_taken = 1'b0;
      endcase
    end

    wire ex_is_branch = id_ex_valid && (id_ex_branch_opcode[1:0] == 2'b01);
    wire ex_is_jal    = id_ex_valid && (id_ex_branch_opcode == 5'b00111);
    wire ex_is_jalr   = id_ex_valid && (id_ex_branch_opcode == 5'b00011);
    wire ex_flush     = ex_is_jal || ex_is_jalr || (ex_is_branch && branch_taken);

    wire [bitwidth-1:0] ex_branch_target =
      ex_is_jalr ? ((ex_rs1_fwd + id_ex_imm) & ~{{(bitwidth-1){1'b0}}, 1'b1}) :
                   (id_ex_pc + id_ex_imm);

    reg [bitwidth-1:0] ex_wb_data;
    always @(*) begin
      case (id_ex_reg_wr_src)
        REG_SRC_PC:  ex_wb_data = id_ex_pc_gen_src ? (id_ex_pc + id_ex_imm) : (id_ex_pc + 4);
        REG_SRC_IMM: ex_wb_data = id_ex_imm;
        REG_SRC_MEM: ex_wb_data = {bitwidth{1'b0}};
        default:     ex_wb_data = ex_alu_dout;
      endcase
    end

    reg [bitwidth-1:0] ex_store_data_aligned;
    reg [3:0]          ex_store_byte_mask;
    always @(*) begin
      ex_store_data_aligned = ex_rs2_fwd;
      ex_store_byte_mask = 4'b0000;

      case (id_ex_mem_byte_mask[3:0])
        4'b0001: begin
          case (ex_alu_dout[1:0])
            2'b00: begin
              ex_store_data_aligned = {{24{1'b0}}, ex_rs2_fwd[7:0]};
              ex_store_byte_mask = 4'b0001;
            end
            2'b01: begin
              ex_store_data_aligned = {{16{1'b0}}, ex_rs2_fwd[7:0], {8{1'b0}}};
              ex_store_byte_mask = 4'b0010;
            end
            2'b10: begin
              ex_store_data_aligned = {{8{1'b0}}, ex_rs2_fwd[7:0], {16{1'b0}}};
              ex_store_byte_mask = 4'b0100;
            end
            default: begin
              ex_store_data_aligned = {ex_rs2_fwd[7:0], {24{1'b0}}};
              ex_store_byte_mask = 4'b1000;
            end
          endcase
        end

        4'b0011: begin
          if (ex_alu_dout[1]) begin
            ex_store_data_aligned = {ex_rs2_fwd[15:0], {16{1'b0}}};
            ex_store_byte_mask = 4'b1100;
          end
          else begin
            ex_store_data_aligned = {{16{1'b0}}, ex_rs2_fwd[15:0]};
            ex_store_byte_mask = 4'b0011;
          end
        end

        4'b1111: begin
          ex_store_data_aligned = ex_rs2_fwd;
          ex_store_byte_mask = 4'b1111;
        end

        default: begin
          ex_store_data_aligned = ex_rs2_fwd;
          ex_store_byte_mask = 4'b0000;
        end
      endcase
    end

    reg [7:0]          mem_load_byte;
    reg [15:0]         mem_load_half;
    reg [bitwidth-1:0] mem_load_data;
    always @(*) begin
      case (ex_mem_addr_low)
        2'b00: mem_load_byte = data_bram_rd_data[7:0];
        2'b01: mem_load_byte = data_bram_rd_data[15:8];
        2'b10: mem_load_byte = data_bram_rd_data[23:16];
        default: mem_load_byte = data_bram_rd_data[31:24];
      endcase

      case (ex_mem_addr_low[1])
        1'b0: mem_load_half = data_bram_rd_data[15:0];
        default: mem_load_half = data_bram_rd_data[31:16];
      endcase

      case (ex_mem_mem_byte_mask[3:0])
        4'b0001: mem_load_data = ex_mem_ld_unsigned ? {{24{1'b0}}, mem_load_byte} :
                                                        {{24{mem_load_byte[7]}}, mem_load_byte};
        4'b0011: mem_load_data = ex_mem_ld_unsigned ? {{16{1'b0}}, mem_load_half} :
                                                        {{16{mem_load_half[15]}}, mem_load_half};
        4'b1111: mem_load_data = data_bram_rd_data;
        default: mem_load_data = {bitwidth{1'b0}};
      endcase
    end

    wire fetch_to_id_valid = fetch_buf_valid ? 1'b1 : imem_resp_valid;
    wire [bitwidth-1:0] fetch_to_id_pc = fetch_buf_valid ? fetch_buf_pc : imem_resp_pc;
    wire [31:0] fetch_to_id_inst = fetch_buf_valid ? fetch_buf_inst : inst;

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        pc <= {bitwidth{1'b0}};
        imem_resp_pc <= {bitwidth{1'b0}};
        imem_resp_valid <= 1'b0;
        fetch_buf_valid <= 1'b0;
        fetch_buf_pc <= {bitwidth{1'b0}};
        fetch_buf_inst <= 32'b0;

        if_id_valid <= 1'b0;
        if_id_pc <= {bitwidth{1'b0}};
        if_id_inst <= 32'b0;

        id_ex_valid <= 1'b0;
        id_ex_pc <= {bitwidth{1'b0}};
        id_ex_inst <= 32'b0;
        id_ex_rs1_idx <= 5'd0;
        id_ex_rs2_idx <= 5'd0;
        id_ex_rd_idx <= 5'd0;
        id_ex_funct3 <= 3'd0;
        id_ex_funct7 <= 7'd0;
        id_ex_alu_ctl <= 4'd0;
        id_ex_alu_src_b_is_imm <= 1'b0;
        id_ex_reg_wr_src <= 2'd0;
        id_ex_reg_wr_en <= 1'b0;
        id_ex_mem_wr_en <= 1'b0;
        id_ex_mem_rd_en <= 1'b0;
        id_ex_branch_opcode <= 5'd0;
        id_ex_pc_gen_src <= 1'b0;
        id_ex_mem_byte_mask <= 8'd0;
        id_ex_ld_unsigned <= 1'b0;
        id_ex_imm <= {bitwidth{1'b0}};
        id_ex_rs1_data <= {bitwidth{1'b0}};
        id_ex_rs2_data <= {bitwidth{1'b0}};

        ex_mem_valid <= 1'b0;
        ex_mem_rd_idx <= 5'd0;
        ex_mem_reg_wr_src <= 2'd0;
        ex_mem_reg_wr_en <= 1'b0;
        ex_mem_mem_rd_en <= 1'b0;
        ex_mem_mem_byte_mask <= 8'd0;
        ex_mem_ld_unsigned <= 1'b0;
        ex_mem_addr_low <= 2'd0;
        ex_mem_wb_data <= {bitwidth{1'b0}};

        mem_wb_valid <= 1'b0;
        mem_wb_rd_idx <= 5'd0;
        mem_wb_reg_wr_src <= 2'd0;
        mem_wb_reg_wr_en <= 1'b0;
        mem_wb_wb_data <= {bitwidth{1'b0}};
      end
      else begin
        // MEM/WB update from the previous EX/MEM stage.
        mem_wb_valid <= ex_mem_valid;
        mem_wb_rd_idx <= ex_mem_rd_idx;
        mem_wb_reg_wr_src <= ex_mem_reg_wr_src;
        mem_wb_reg_wr_en <= ex_mem_reg_wr_en;
        mem_wb_wb_data <= (ex_mem_reg_wr_src == REG_SRC_MEM) ? mem_load_data : ex_mem_wb_data;

        // EX/MEM update from the current EX stage.
        ex_mem_valid <= id_ex_valid;
        ex_mem_rd_idx <= id_ex_rd_idx;
        ex_mem_reg_wr_src <= id_ex_reg_wr_src;
        ex_mem_reg_wr_en <= id_ex_valid && id_ex_reg_wr_en;
        ex_mem_mem_rd_en <= id_ex_valid && id_ex_mem_rd_en;
        ex_mem_mem_byte_mask <= id_ex_mem_byte_mask;
        ex_mem_ld_unsigned <= id_ex_ld_unsigned;
        ex_mem_addr_low <= ex_alu_dout[1:0];
        ex_mem_wb_data <= ex_wb_data;

        if (ex_flush) begin
          pc <= ex_branch_target;
          imem_resp_pc <= pc;
          imem_resp_valid <= 1'b0;
          fetch_buf_valid <= 1'b0;

          if_id_valid <= 1'b0;

          id_ex_valid <= 1'b0;
          id_ex_reg_wr_en <= 1'b0;
          id_ex_mem_wr_en <= 1'b0;
          id_ex_mem_rd_en <= 1'b0;
          id_ex_branch_opcode <= 5'd0;
        end
        else if (load_use_stall) begin
          pc <= pc;
          imem_resp_pc <= pc;
          imem_resp_valid <= 1'b1;

          if (!fetch_buf_valid && imem_resp_valid) begin
            fetch_buf_valid <= 1'b1;
            fetch_buf_pc <= imem_resp_pc;
            fetch_buf_inst <= inst;
          end

          if_id_valid <= if_id_valid;
          if_id_pc <= if_id_pc;
          if_id_inst <= if_id_inst;

          id_ex_valid <= 1'b0;
          id_ex_reg_wr_en <= 1'b0;
          id_ex_mem_wr_en <= 1'b0;
          id_ex_mem_rd_en <= 1'b0;
          id_ex_branch_opcode <= 5'd0;
        end
        else begin
          pc <= pc + 4;
          imem_resp_pc <= pc;
          imem_resp_valid <= 1'b1;

          if (fetch_buf_valid)
            fetch_buf_valid <= 1'b0;

          if_id_valid <= fetch_to_id_valid;
          if_id_pc <= fetch_to_id_pc;
          if_id_inst <= fetch_to_id_inst;

          id_ex_valid <= if_id_valid;
          id_ex_pc <= if_id_pc;
          id_ex_inst <= if_id_inst;
          id_ex_rs1_idx <= id_rs1_idx;
          id_ex_rs2_idx <= id_rs2_idx;
          id_ex_rd_idx <= id_rd_idx;
          id_ex_funct3 <= id_funct3;
          id_ex_funct7 <= id_funct7;
          id_ex_alu_ctl <= id_alu_ctl;
          id_ex_alu_src_b_is_imm <= id_alu_src_b_is_imm;
          id_ex_reg_wr_src <= id_reg_wr_src;
          id_ex_reg_wr_en <= if_id_valid && id_reg_wr_en;
          id_ex_mem_wr_en <= if_id_valid && id_mem_wr_en;
          id_ex_mem_rd_en <= if_id_valid && id_mem_rd_en;
          id_ex_branch_opcode <= if_id_valid ? id_branch_opcode : 5'd0;
          id_ex_pc_gen_src <= id_pc_gen_src;
          id_ex_mem_byte_mask <= id_mem_byte_mask;
          id_ex_ld_unsigned <= id_ld_unsigned;
          id_ex_imm <= id_imm;
          id_ex_rs1_data <= id_rs1_data;
          id_ex_rs2_data <= id_rs2_data;
        end
      end
    end

    assign inst_bram_addr = pc;

    assign data_bram_rd_en = id_ex_valid && id_ex_mem_rd_en;
    assign data_bram_wr_en = id_ex_valid && id_ex_mem_wr_en;
    assign data_bram_addr = (data_bram_rd_en || data_bram_wr_en) ? ex_alu_dout : {bitwidth{1'b0}};
    assign data_bram_wr_data = ex_store_data_aligned;
    assign data_bram_wr_byte_mask = data_bram_wr_en ? ex_store_byte_mask : 4'b0000;

endmodule
