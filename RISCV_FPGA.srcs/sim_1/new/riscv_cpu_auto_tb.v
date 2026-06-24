`timescale 1ns / 1ps

module riscv_cpu_auto_tb;

`ifdef TEST9
    localparam [8*16-1:0] TEST_NAME = "test9";
    localparam [8*256-1:0] COE_FILE = "test9.coe";
    localparam [31:0] HALT_PC = 32'h00000064;
    localparam integer MAX_CYCLES = 1000;
`else
    localparam [8*16-1:0] TEST_NAME = "test7";
    localparam [8*256-1:0] COE_FILE = "test7_tdp.coe";
    localparam [31:0] HALT_PC = 32'h00000114;
    localparam integer MAX_CYCLES = 400;
`endif

    localparam integer MEM_WORDS = 32768;
    localparam integer PREDICT_TAKEN_PENALTY_CYCLES = 1;
    localparam integer FAST_FLUSH_PENALTY_CYCLES = 2;
    localparam integer SLOW_FLUSH_PENALTY_CYCLES = 3;
    localparam real CPU_FREQ_MHZ = 200.0;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg [31:0] ram [0:MEM_WORDS-1];

    wire [31:0] inst;
    wire [31:0] inst_bram_addr;
    reg  [31:0] inst_r = 32'd0;

    reg  [31:0] data_bram_rd_data = 32'd0;
    wire [31:0] data_bram_addr;
    wire [31:0] data_bram_wr_data;
    wire [3:0]  data_bram_wr_byte_mask;
    wire        data_bram_wr_en;
    wire        data_bram_rd_en;

    integer cycle = 0;
    integer halt_seen = 0;
    integer error_count = 0;
    reg test_done = 1'b0;
    reg test_pass = 1'b0;

    // Simulation-only performance counters. They freeze when the first halt
    // instruction completes EX, so the checker drain cycles are not measured.
    integer perf_cycles = 0;
    integer perf_instructions = 0;
    integer perf_load_use_stalls = 0;
    integer perf_mdu_stall_cycles = 0;
    integer perf_mdu_instructions = 0;
    integer perf_flushes = 0;
    integer perf_slow_flushes = 0;
    integer perf_predicted_taken_redirects = 0;
    integer perf_cond_predictions = 0;
    integer perf_cond_mispredictions = 0;
    integer perf_branch_instructions = 0;
    integer perf_taken_branches = 0;
    integer perf_jal_instructions = 0;
    integer perf_jalr_instructions = 0;
    integer perf_empty_ex_cycles = 0;
    reg     perf_frozen = 1'b0;

    wire [31:0] dbg_pc = uut.pc;
    wire [31:0] dbg_x01 = uut.riscv_reg_file_inst.x[1];
    wire [31:0] dbg_x02 = uut.riscv_reg_file_inst.x[2];
    wire [31:0] dbg_x03 = uut.riscv_reg_file_inst.x[3];
    wire [31:0] dbg_x04 = uut.riscv_reg_file_inst.x[4];
    wire [31:0] dbg_x05 = uut.riscv_reg_file_inst.x[5];
    wire [31:0] dbg_x06 = uut.riscv_reg_file_inst.x[6];
    wire [31:0] dbg_x07 = uut.riscv_reg_file_inst.x[7];
    wire [31:0] dbg_x08 = uut.riscv_reg_file_inst.x[8];
    wire [31:0] dbg_x09 = uut.riscv_reg_file_inst.x[9];
    wire [31:0] dbg_x10 = uut.riscv_reg_file_inst.x[10];
    wire [31:0] dbg_x11 = uut.riscv_reg_file_inst.x[11];
    wire [31:0] dbg_x12 = uut.riscv_reg_file_inst.x[12];
    wire [31:0] dbg_x25 = uut.riscv_reg_file_inst.x[25];
    wire [31:0] dbg_x26 = uut.riscv_reg_file_inst.x[26];
    wire [31:0] dbg_x27 = uut.riscv_reg_file_inst.x[27];
    wire [31:0] dbg_x28 = uut.riscv_reg_file_inst.x[28];
    wire [31:0] dbg_x29 = uut.riscv_reg_file_inst.x[29];
    wire [31:0] dbg_x30 = uut.riscv_reg_file_inst.x[30];
    wire [31:0] dbg_x31 = uut.riscv_reg_file_inst.x[31];

    wire perf_halt_in_ex =
      uut.id_ex_valid &&
      (uut.id_ex_pc == HALT_PC) &&
      (uut.id_ex_inst == 32'h00000f6f);
    wire perf_halt_in_id =
      uut.if_id_valid &&
      (uut.if_id_pc == HALT_PC) &&
      (uut.if_id_inst == 32'h00000f6f);
    wire perf_ex_instruction_complete =
      uut.id_ex_valid && (!uut.id_ex_is_mdu || uut.mdu_done);

    assign inst = inst_r;

    riscv_cpu #(
      .bitwidth(32)
    ) uut (
      .clk(clk),
      .rst_n(rst_n),
      .inst(inst),
      .inst_bram_addr(inst_bram_addr),
      .data_bram_rd_data(data_bram_rd_data),
      .data_bram_addr(data_bram_addr),
      .data_bram_wr_data(data_bram_wr_data),
      .data_bram_wr_byte_mask(data_bram_wr_byte_mask),
      .data_bram_wr_en(data_bram_wr_en),
      .data_bram_rd_en(data_bram_rd_en)
    );

    task clear_ram;
      integer i;
      begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
          ram[i] = 32'd0;
      end
    endtask

    task load_coe;
      input [8*256-1:0] file_name;
      integer fd;
      integer code;
      integer matched;
      integer word_count;
      reg [8*256-1:0] line;
      reg [31:0] word;
      begin
        word_count = 0;
        fd = $fopen(file_name, "r");
        if (fd == 0) begin
          $display("FAIL: cannot open COE file %0s", file_name);
          $finish;
        end

        while (!$feof(fd)) begin
          code = $fgets(line, fd);
          matched = $sscanf(line, "%h", word);
          if (matched == 1) begin
            if (word_count < MEM_WORDS)
              ram[word_count] = word;
            word_count = word_count + 1;
          end
        end
        $fclose(fd);
        $display("Loaded %0d words from %0s for %0s", word_count, file_name, TEST_NAME);
      end
    endtask

    task expect_reg;
      input integer idx;
      input [31:0] expected;
      reg [31:0] actual;
      begin
        actual = uut.riscv_reg_file_inst.x[idx];
        if (actual !== expected) begin
          $display("FAIL reg x%0d: expected %08x actual %08x", idx, expected, actual);
          error_count = error_count + 1;
        end
      end
    endtask

    task expect_mem;
      input [31:0] byte_addr;
      input [31:0] expected;
      reg [31:0] actual;
      begin
        actual = ram[byte_addr[16:2]];
        if (actual !== expected) begin
          $display("FAIL mem[%08x]: expected %08x actual %08x", byte_addr, expected, actual);
          error_count = error_count + 1;
        end
      end
    endtask

    task apply_write_mask;
      input [31:0] word_addr;
      input [31:0] data;
      input [3:0] mask;
      begin
        if (mask[0]) ram[word_addr][7:0]   = data[7:0];
        if (mask[1]) ram[word_addr][15:8]  = data[15:8];
        if (mask[2]) ram[word_addr][23:16] = data[23:16];
        if (mask[3]) ram[word_addr][31:24] = data[31:24];
      end
    endtask

    task check_test7;
      begin
        expect_reg(1,  32'h87654321);
        expect_reg(2,  32'h04040404);
        expect_reg(3,  32'h04000000);
        expect_reg(4,  32'h00000004);
        expect_reg(5,  32'h00000008);
        expect_reg(6,  32'h00000028);
        expect_reg(7,  32'h00000030);
        expect_reg(8,  32'h00000001);
        expect_reg(9,  32'h00000001);
        expect_reg(10, 32'h00000000);
        expect_reg(11, 32'h00000001);
        expect_reg(12, 32'h87654320);
        expect_reg(13, 32'h8765432f);
        expect_reg(14, 32'hffffff87);
        expect_reg(15, 32'h00000004);
        expect_reg(16, 32'h76543210);
        expect_reg(17, 32'h08765432);
        expect_reg(18, 32'hf8765432);
        expect_reg(19, 32'h00000001);
        expect_reg(20, 32'h00000001);
        expect_reg(21, 32'h0000000c);
        expect_reg(22, 32'h0000000c);
        expect_reg(23, 32'h00000000);
        expect_reg(24, 32'h00000000);
        expect_reg(25, 32'h87654088);
        expect_reg(26, 32'hffffffef);
        expect_reg(27, 32'hffffcdef);
        expect_reg(28, 32'h000000ef);
        expect_reg(29, 32'h0000cdef);
        expect_reg(30, 32'h00000118);
        expect_reg(31, 32'h00000140);

        expect_mem(32'h00000144, 32'h87654321);
        expect_mem(32'h00000148, 32'h04040404);
        expect_mem(32'h0000014c, 32'h04000000);
        expect_mem(32'h000001a4, 32'h87654088);
        expect_mem(32'h000001a8, 32'hffffffef);
        expect_mem(32'h000001ac, 32'hffffcdef);
        expect_mem(32'h000001b0, 32'h000000ef);
        expect_mem(32'h000001b4, 32'h0000cdef);
      end
    endtask

    task check_test9;
      begin
        expect_reg(1,  32'h7fffffff);
        expect_reg(2,  32'hffffffff);
        expect_reg(3,  32'h80000001);
        expect_reg(4,  32'hffffffff);
        expect_reg(5,  32'h7ffffffe);
        expect_reg(6,  32'hffffffff);
        expect_reg(7,  32'h7ffffffe);
        expect_reg(8,  32'h80000001);
        expect_reg(9,  32'h00000000);
        expect_reg(10, 32'hffffffff);
        expect_reg(11, 32'h00000002);
        expect_reg(12, 32'h00000001);
        expect_reg(30, 32'h00000068);
        expect_reg(31, 32'h00000320);

        expect_mem(32'h0000032c, 32'h80000001);
        expect_mem(32'h00000330, 32'hffffffff);
        expect_mem(32'h00000334, 32'h7ffffffe);
        expect_mem(32'h00000338, 32'hffffffff);
        expect_mem(32'h0000033c, 32'h7ffffffe);
        expect_mem(32'h00000340, 32'h80000001);
        expect_mem(32'h00000344, 32'h00000000);
        expect_mem(32'h00000348, 32'hffffffff);
        expect_mem(32'h0000034c, 32'h00000002);
        expect_mem(32'h00000350, 32'h00000001);
      end
    endtask

    task run_checks;
      begin
`ifdef TEST9
        check_test9();
`else
        check_test7();
`endif
        test_done = 1'b1;
        test_pass = (error_count == 0);
        if (error_count == 0)
          $display("PASS %0s at cycle %0d", TEST_NAME, cycle);
        else
          $display("FAIL %0s with %0d errors at cycle %0d", TEST_NAME, error_count, cycle);
      end
    endtask

    task report_performance;
      integer control_cycles;
      integer fast_flushes;
      integer tracked_cycles;
      integer residual_cycles;
      real ipc;
      real prediction_accuracy;
      begin
        fast_flushes = perf_flushes - perf_slow_flushes;
        control_cycles =
                         perf_predicted_taken_redirects * PREDICT_TAKEN_PENALTY_CYCLES +
                         fast_flushes * FAST_FLUSH_PENALTY_CYCLES +
                         perf_slow_flushes * SLOW_FLUSH_PENALTY_CYCLES;
        tracked_cycles = perf_load_use_stalls +
                         perf_mdu_stall_cycles +
                         control_cycles;
        residual_cycles = perf_cycles - perf_instructions - tracked_cycles;
        ipc = (perf_cycles != 0) ?
              (1.0 * perf_instructions / perf_cycles) : 0.0;
        prediction_accuracy = (perf_cond_predictions != 0) ?
          (100.0 * (perf_cond_predictions - perf_cond_mispredictions) /
           perf_cond_predictions) : 100.0;

        $display("PERF_BEGIN %0s", TEST_NAME);
        $display("PERF cycles=%0d instructions=%0d IPC=%0.4f CPI=%0.4f throughput=%0.2f_MIPS",
                 perf_cycles, perf_instructions, ipc,
                 1.0 * perf_cycles / perf_instructions, ipc * CPU_FREQ_MHZ);
        $display("PERF load_use_stall_cycles=%0d mdu_instructions=%0d mdu_stall_cycles=%0d predicted_taken_redirects=%0d",
                 perf_load_use_stalls, perf_mdu_instructions, perf_mdu_stall_cycles,
                 perf_predicted_taken_redirects);
        $display("PERF branch_predictions=%0d branch_mispredictions=%0d prediction_accuracy=%0.2f%% fast_recoveries=%0d slow_recoveries=%0d control_penalty_cycles=%0d",
                 perf_cond_predictions, perf_cond_mispredictions, prediction_accuracy,
                 fast_flushes, perf_slow_flushes, control_cycles);
        $display("PERF branches=%0d taken_branches=%0d jal=%0d jalr=%0d empty_ex_cycles=%0d residual_cycles=%0d",
                 perf_branch_instructions, perf_taken_branches,
                 perf_jal_instructions, perf_jalr_instructions,
                 perf_empty_ex_cycles, residual_cycles);
        $display("AMDAHL load_fraction=%0.4f max_speedup=%0.4f",
                 1.0 * perf_load_use_stalls / perf_cycles,
                 1.0 * perf_cycles / (perf_cycles - perf_load_use_stalls));
        $display("AMDAHL control_fraction=%0.4f max_speedup=%0.4f prediction_zero_bubble_speedup=%0.4f",
                 1.0 * control_cycles / perf_cycles,
                 1.0 * perf_cycles / (perf_cycles - control_cycles),
                 1.0 * perf_cycles /
                   (perf_cycles - perf_predicted_taken_redirects));
        $display("AMDAHL mdu_fraction=%0.4f max_speedup=%0.4f",
                 1.0 * perf_mdu_stall_cycles / perf_cycles,
                 1.0 * perf_cycles / (perf_cycles - perf_mdu_stall_cycles));
        $display("AMDAHL startup_or_other_fraction=%0.4f max_speedup=%0.4f",
                 1.0 * residual_cycles / perf_cycles,
                 1.0 * perf_cycles / (perf_cycles - residual_cycles));
        $display("AMDAHL all_tracked_penalties=%0d max_speedup=%0.4f",
                 tracked_cycles,
                 1.0 * perf_cycles / (perf_cycles - tracked_cycles));
        $display("PERF_END %0s", TEST_NAME);
      end
    endtask

    always @(posedge clk) begin
      inst_r <= ram[inst_bram_addr[16:2]];

      if (data_bram_wr_en && (data_bram_addr[31:20] == 12'h000))
        apply_write_mask(data_bram_addr[16:2], data_bram_wr_data, data_bram_wr_byte_mask);

      if (data_bram_addr == 32'h80000000)
        data_bram_rd_data <= 32'h87654321;
      else if (data_bram_addr[31:20] == 12'h000)
        data_bram_rd_data <= ram[data_bram_addr[16:2]];
      else
        data_bram_rd_data <= 32'd0;

      if (rst_n) begin
        cycle <= cycle + 1;

        if (!perf_frozen) begin
          perf_cycles <= perf_cycles + 1;

          if (perf_ex_instruction_complete)
            perf_instructions <= perf_instructions + 1;
          if (uut.load_use_stall)
            perf_load_use_stalls <= perf_load_use_stalls + 1;
          if (uut.mdu_stall)
            perf_mdu_stall_cycles <= perf_mdu_stall_cycles + 1;
          if (perf_ex_instruction_complete && uut.id_ex_is_mdu)
            perf_mdu_instructions <= perf_mdu_instructions + 1;
          if (uut.ex_flush && !perf_halt_in_ex)
            perf_flushes <= perf_flushes + 1;
          if (uut.ex_flush && !uut.ex_fast_redirect && !perf_halt_in_ex)
            perf_slow_flushes <= perf_slow_flushes + 1;
          if (uut.id_predict_fire && !perf_halt_in_id)
            perf_predicted_taken_redirects <= perf_predicted_taken_redirects + 1;
          if (!uut.id_ex_valid)
            perf_empty_ex_cycles <= perf_empty_ex_cycles + 1;

          if (perf_ex_instruction_complete && uut.ex_is_branch) begin
            perf_cond_predictions <= perf_cond_predictions + 1;
            if (uut.ex_flush)
              perf_cond_mispredictions <= perf_cond_mispredictions + 1;
            perf_branch_instructions <= perf_branch_instructions + 1;
            if (uut.branch_taken)
              perf_taken_branches <= perf_taken_branches + 1;
          end
          if (perf_ex_instruction_complete && uut.ex_is_jal)
            perf_jal_instructions <= perf_jal_instructions + 1;
          if (perf_ex_instruction_complete && uut.ex_is_jalr)
            perf_jalr_instructions <= perf_jalr_instructions + 1;

          if (perf_halt_in_ex)
            perf_frozen <= 1'b1;
        end

        if ((halt_seen == 0) &&
            perf_halt_in_ex)
          halt_seen <= 1;
        else if (halt_seen != 0)
          halt_seen <= halt_seen + 1;

        if (!test_done && (halt_seen == 12)) begin
          report_performance();
          run_checks();
          #20 $finish;
        end

        if (!test_done && (cycle >= MAX_CYCLES)) begin
          error_count = error_count + 1;
          $display("FAIL %0s timeout at cycle %0d pc=%08x", TEST_NAME, cycle, uut.pc);
          test_done = 1'b1;
          test_pass = 1'b0;
          #20 $finish;
        end
      end
    end

    initial begin
      clear_ram();
      load_coe(COE_FILE);
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
    end

endmodule
