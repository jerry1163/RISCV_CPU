`timescale 1ns / 1ps

module riscv_mdu #(
    parameter bitwidth = 32
    )(
    input clk,
    input rst_n,
    input start,
    input [2:0] op,
    input [bitwidth-1:0] din_a,
    input [bitwidth-1:0] din_b,
    output reg busy = 1'b0,
    output reg done = 1'b0,
    output reg [bitwidth-1:0] result = {bitwidth{1'b0}}
    );

    localparam OP_MUL    = 3'b000;
    localparam OP_MULH   = 3'b001;
    localparam OP_MULHSU = 3'b010;
    localparam OP_MULHU  = 3'b011;
    localparam OP_DIV    = 3'b100;
    localparam OP_DIVU   = 3'b101;
    localparam OP_REM    = 3'b110;
    localparam OP_REMU   = 3'b111;

    localparam ST_IDLE = 2'd0;
    localparam ST_MUL  = 2'd1;
    localparam ST_DIV  = 2'd2;

    reg [1:0] state = ST_IDLE;
    reg [2:0] op_r = OP_MUL;
    reg [5:0] count = 6'd0;

    reg [63:0] mul_acc = 64'd0;
    reg [63:0] mul_multiplicand = 64'd0;
    reg [31:0] mul_multiplier = 32'd0;
    reg        mul_neg = 1'b0;

    reg [31:0] div_dividend = 32'd0;
    reg [31:0] div_divisor = 32'd0;
    reg [31:0] div_quotient = 32'd0;
    reg [32:0] div_remainder = 33'd0;
    reg        div_quot_neg = 1'b0;
    reg        div_rem_neg = 1'b0;

    function [31:0] abs32;
      input [31:0] value;
      input        is_signed;
      begin
        abs32 = (is_signed && value[31]) ? (~value + 32'd1) : value;
      end
    endfunction

    wire [63:0] mul_acc_step = mul_acc + (mul_multiplier[0] ? mul_multiplicand : 64'd0);
    wire [63:0] mul_product = mul_neg ? (~mul_acc_step + 64'd1) : mul_acc_step;

    wire [32:0] div_divisor_ext = {1'b0, div_divisor};
    wire [32:0] div_remainder_shift = {div_remainder[31:0], div_dividend[31]};
    wire        div_do_subtract = (div_remainder_shift >= div_divisor_ext);
    wire [32:0] div_remainder_step =
      div_do_subtract ? (div_remainder_shift - div_divisor_ext) : div_remainder_shift;
    wire [31:0] div_quotient_step = {div_quotient[30:0], div_do_subtract};
    wire [31:0] div_quotient_signed = div_quot_neg ? (~div_quotient_step + 32'd1) : div_quotient_step;
    wire [31:0] div_remainder_signed = div_rem_neg ? (~div_remainder_step[31:0] + 32'd1) :
                                                     div_remainder_step[31:0];

    wire start_mul = start && (op[2] == 1'b0);
    wire start_signed_div = start && ((op == OP_DIV) || (op == OP_REM));
    wire start_rem = start && ((op == OP_REM) || (op == OP_REMU));
    wire start_div_by_zero = start && (din_b == 32'd0);
    wire start_div_overflow = start_signed_div && (din_a == 32'h80000000) && (din_b == 32'hffffffff);

    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        busy <= 1'b0;
        done <= 1'b0;
        result <= {bitwidth{1'b0}};
        state <= ST_IDLE;
        op_r <= OP_MUL;
        count <= 6'd0;
        mul_acc <= 64'd0;
        mul_multiplicand <= 64'd0;
        mul_multiplier <= 32'd0;
        mul_neg <= 1'b0;
        div_dividend <= 32'd0;
        div_divisor <= 32'd0;
        div_quotient <= 32'd0;
        div_remainder <= 33'd0;
        div_quot_neg <= 1'b0;
        div_rem_neg <= 1'b0;
      end
      else begin
        done <= 1'b0;

        case (state)
          ST_IDLE: begin
            busy <= 1'b0;
            if (start) begin
              op_r <= op;
              count <= 6'd0;

              if (start_mul) begin
                busy <= 1'b1;
                state <= ST_MUL;
                mul_acc <= 64'd0;
                mul_multiplicand <= {32'd0, abs32(din_a, (op == OP_MULH) || (op == OP_MULHSU))};
                mul_multiplier <= abs32(din_b, (op == OP_MULH));
                mul_neg <= (((op == OP_MULH) || (op == OP_MULHSU)) && din_a[31]) ^
                           ((op == OP_MULH) && din_b[31]);
              end
              else if (start_div_by_zero) begin
                busy <= 1'b0;
                done <= 1'b1;
                state <= ST_IDLE;
                result <= start_rem ? din_a : 32'hffffffff;
              end
              else if (start_div_overflow) begin
                busy <= 1'b0;
                done <= 1'b1;
                state <= ST_IDLE;
                result <= start_rem ? 32'd0 : 32'h80000000;
              end
              else begin
                busy <= 1'b1;
                state <= ST_DIV;
                div_dividend <= abs32(din_a, start_signed_div);
                div_divisor <= abs32(din_b, start_signed_div);
                div_quotient <= 32'd0;
                div_remainder <= 33'd0;
                div_quot_neg <= start_signed_div && (din_a[31] ^ din_b[31]);
                div_rem_neg <= start_signed_div && din_a[31];
              end
            end
          end

          ST_MUL: begin
            mul_acc <= mul_acc_step;
            mul_multiplicand <= {mul_multiplicand[62:0], 1'b0};
            mul_multiplier <= {1'b0, mul_multiplier[31:1]};

            if (count == 6'd31) begin
              busy <= 1'b0;
              done <= 1'b1;
              state <= ST_IDLE;
              result <= (op_r == OP_MUL) ? mul_product[31:0] : mul_product[63:32];
            end
            else begin
              count <= count + 6'd1;
            end
          end

          ST_DIV: begin
            div_remainder <= div_remainder_step;
            div_quotient <= div_quotient_step;
            div_dividend <= {div_dividend[30:0], 1'b0};

            if (count == 6'd31) begin
              busy <= 1'b0;
              done <= 1'b1;
              state <= ST_IDLE;
              result <= ((op_r == OP_REM) || (op_r == OP_REMU)) ? div_remainder_signed :
                                                                    div_quotient_signed;
            end
            else begin
              count <= count + 6'd1;
            end
          end

          default: begin
            busy <= 1'b0;
            done <= 1'b0;
            state <= ST_IDLE;
          end
        endcase
      end
    end

endmodule
