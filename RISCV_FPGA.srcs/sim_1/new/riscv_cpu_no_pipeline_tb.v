`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/10/03 16:37:42
// Design Name: 
// Module Name: riscv_cpu_no_pipeline_tb
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


module riscv_cpu_no_pipeline_tb;

    localparam bitwidth = 32;
    
    reg clk_cpu;
    reg dcm_locked;
    reg [31:0] inst_bram [0:65535];
    reg [7:0] data_bram [0:65535];
    wire [31:0] inst_bram_rd_data;
    wire [bitwidth-1:0] inst_bram_addr;
    reg [bitwidth-1:0] data_bram_rd_data;
    wire [bitwidth-1:0] data_bram_addr;
    wire [bitwidth-1:0] data_bram_wr_data;
    wire [3:0] data_bram_wr_byte_mask;
    wire data_bram_wr_en, data_bram_rd_en;
    
    initial begin
        inst_bram[0] = 32'h876540B7;
        inst_bram[1] = 32'h32108093;
        inst_bram[2] = 32'h02002103;
        inst_bram[3] = 32'h01811193;
        inst_bram[4] = 32'h0181D213;
        inst_bram[5] = 32'h004202B3;
        inst_bram[6] = 32'h0080036F;
        inst_bram[7] = 32'h0042D463;
        inst_bram[8] = 32'h000303E7;
        inst_bram[9] = 32'h00523433;
        inst_bram[10] = 32'h00147493;
        inst_bram[11] = 32'h0010B513;
        inst_bram[12] = 32'h0010A593;
        inst_bram[13] = 32'h0010C613;
        inst_bram[14] = 32'h00F0E693;
        inst_bram[15] = 32'h4180D713;
        inst_bram[16] = 32'h404287B3;
        inst_bram[17] = 32'h00409833;
        inst_bram[18] = 32'h0040D8B3;
        inst_bram[19] = 32'h4040D933;
        inst_bram[20] = 32'h005229B3;
        inst_bram[21] = 32'h00123A33;
        inst_bram[22] = 32'h00524AB3;
        inst_bram[23] = 32'h00526B33;
        inst_bram[24] = 32'h00527BB3;
        inst_bram[25] = 32'hFC42C0E3;
        inst_bram[26] = 32'hFA50EEE3;
        inst_bram[27] = 32'hFA12FCE3;
        inst_bram[28] = 32'h00F20663;
        inst_bram[29] = 32'h01702023;
        inst_bram[30] = 32'hFADFFC6F;
        inst_bram[31] = 32'h87654C97;
        inst_bram[32] = 32'h00102223;
        inst_bram[33] = 32'h00202423;
        inst_bram[34] = 32'h00302623;
        inst_bram[35] = 32'h00402823;
        inst_bram[36] = 32'h00502A23;
        inst_bram[37] = 32'h00602C23;
        inst_bram[38] = 32'h00702E23;
        inst_bram[39] = 32'h02802023;
        inst_bram[40] = 32'h02902223;
        inst_bram[41] = 32'h02A02423;
        inst_bram[42] = 32'h02B02623;
        inst_bram[43] = 32'h02C02823;
        inst_bram[44] = 32'h02D02A23;
        inst_bram[45] = 32'h02E02C23;
        inst_bram[46] = 32'h02F02E23;
        inst_bram[47] = 32'h05002023;
        inst_bram[48] = 32'h05102223;
        inst_bram[49] = 32'h05202423;
        inst_bram[50] = 32'h05302623;
        inst_bram[51] = 32'h05402823;
        inst_bram[52] = 32'h05502A23;
        inst_bram[53] = 32'h05602C23;
        inst_bram[54] = 32'h05702E23;
        inst_bram[55] = 32'h07802023;
        inst_bram[56] = 32'h07902223;
    end
    
    integer i, j, fp_dram, status;
    initial begin
      for (i = 0;i < 128;i = i + 1) begin
        data_bram[i*4] = i;
        data_bram[1024+i*4] = -i;
        for (j=1; j < 4; j = j + 1) begin
          data_bram[i*4+j] = i;
          data_bram[1024+i*4+j] = -i;
        end
      end
      #1000;
      fp_dram = $fopen("dram_dump.txt","w");
      for (i = 1; i < 26; i = i + 1) begin
        $fwrite(fp_dram, "x%1d=", i);
        for (j = 3; j >= 0; j = j - 1) begin
          $fwrite(fp_dram, "%2x", data_bram[i*4+j]);
        end
        $fwrite(fp_dram, ";\n");
      end
      $fclose(fp_dram);
    end
    
    initial begin
      clk_cpu = 0;
      forever #5 clk_cpu = ~clk_cpu;
    end
    
    initial begin
      dcm_locked = 0;
      #4;
      #10;
      dcm_locked = 1;
    end
    
    always @(*) begin
      if (data_bram_rd_en) begin
        data_bram_rd_data = 32'h00000000;
        for (j = 3; j >= 0; j = j - 1)
          data_bram_rd_data = (data_bram_rd_data << 8) | data_bram[data_bram_addr[15:0] + j];
        end
    end
    
    integer wr_bytes;
    always @(posedge clk_cpu) begin
      if (data_bram_wr_en) begin
        case (data_bram_wr_byte_mask)
          4'b0011: wr_bytes = 2;
          4'b0001: wr_bytes = 1;
              default: wr_bytes = 4;
        endcase
        for (j = 0; j < wr_bytes; j = j + 1)
          data_bram[data_bram_addr[15:0] + j] = (data_bram_wr_data >> (j*8)) & 8'hff;
      end
    end
    assign inst_bram_rd_data = inst_bram[inst_bram_addr[17:2]];
    riscv_cpu #(
      .bitwidth(bitwidth)
    ) riscv_cpu_inst (
      .clk(clk_cpu),
      .rst_n(dcm_locked),
      .inst(inst_bram_rd_data),
      .inst_bram_addr(inst_bram_addr),
      .data_bram_rd_data(data_bram_rd_data),
      .data_bram_addr(data_bram_addr),
      .data_bram_wr_data(data_bram_wr_data),
      .data_bram_wr_byte_mask(data_bram_wr_byte_mask),
      .data_bram_wr_en(data_bram_wr_en),
      .data_bram_rd_en(data_bram_rd_en)
    );
endmodule
