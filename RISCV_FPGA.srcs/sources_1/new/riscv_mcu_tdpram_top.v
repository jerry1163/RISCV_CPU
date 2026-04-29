`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/09/27 15:59:44
// Design Name: 
// Module Name: riscv_mcu_top
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


module riscv_mcu_tdpram_top#(
    parameter bitwidth = 32
    )(
    input CLK_FPGA,
    inout [31:0] PA
    );
    
    wire clk_cpu, dcm_locked;
    clk_wiz_sys clk_wiz_sys_inst(
      // Clock out ports
      .clk_cpu(clk_cpu),     // output clk_cpu
      // Status and control signals
      .locked(dcm_locked),       // output locked
     // Clock in ports
      .clk_in1(CLK_FPGA)     // input clk_in1
    );
    
    wire [bitwidth-1:0] inst_bram_rd_data;
    wire [bitwidth-1:0] inst_bram_addr;
    reg [bitwidth-1:0] data_bram_rd_data;
    wire [bitwidth-1:0] data_bram_addr;
    wire [bitwidth-1:0] data_bram_wr_data;
    wire [3:0] data_bram_wr_byte_mask, data_bram_wr_byte_mask_mux;
    wire data_bram_wr_en, data_bram_rd_en;
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
    wire data_bram_addr_is_ram = (data_bram_addr[bitwidth-1:20] == 12'h000);
    assign data_bram_wr_byte_mask_mux = data_bram_addr_is_ram ? data_bram_wr_byte_mask : 4'b0000;
    wire inst_bram_wr_en;
    wire [31:0] inst_wr_data;
    wire [bitwidth-1:0] data_bram_dout;
    assign inst_bram_wr_en = 0;
    assign inst_wr_data = 32'b0;
    
    tdp_bram tdp_bram_inst (
      .clka(clk_cpu),    // input wire clka
      .ena(1'b1),      // input wire ena
      .wea({4{inst_bram_wr_en}}),      // input wire [3 : 0] wea
      .addra(inst_bram_addr[16:2]),  // input wire [14 : 0] addra
      .dina(inst_wr_data),    // input wire [31 : 0] dina
      .douta(inst_bram_rd_data),  // output wire [31 : 0] douta
      .clkb(clk_cpu),    // input wire clkb
      .enb(1'b1),      // input wire enb
      .web(data_bram_wr_byte_mask_mux),      // input wire [3 : 0] web
      .addrb(data_bram_addr[16:2]),  // input wire [14 : 0] addrb
      .dinb(data_bram_wr_data),    // input wire [31 : 0] dinb
      .doutb(data_bram_dout)  // output wire [31 : 0] doutb
    );
    
    reg [bitwidth-1:0] data_bram_addr_r1 = 0;
    reg data_bram_rd_en_r1 = 0;
    reg [bitwidth-1:0] pout = 0, pa_t = 32'hffffffff;
    always @(posedge clk_cpu) begin
      data_bram_addr_r1 <= data_bram_addr;
      data_bram_rd_en_r1 <= data_bram_rd_en;
    end
    always @(posedge clk_cpu) begin
      if (data_bram_wr_en && (data_bram_addr == 32'h80000000)) pout <= data_bram_wr_data[31:0];
      else pout <= pout;
    end
    always @(posedge clk_cpu) begin
      if (data_bram_wr_en && (data_bram_addr == 32'h80000001)) pa_t <= data_bram_wr_data[31:0];
      else pa_t <= pa_t;
    end
    
    genvar i;
    generate
      for (i = 0; i < bitwidth; i = i + 1) begin: port_loop
        assign PA[i] = pa_t[i] ? 1'bz : pout[i];
      end
    endgenerate
    
    reg [bitwidth-1:0] pin_r = 0;
    always @(posedge clk_cpu) begin
      pin_r <= PA;
    end
    always @(*) begin
      if (data_bram_rd_en_r1 && (data_bram_addr_r1 == 32'h80000000)) data_bram_rd_data = pin_r;
      else data_bram_rd_data = data_bram_dout;
    end
endmodule
