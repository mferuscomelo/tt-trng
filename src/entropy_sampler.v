/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// XORs the ring outputs (or picks one of them), synchronizes the result into
// `clk` and keeps one sample every 16 / 64 / 256 / 1024 clocks.
module entropy_sampler #(
    parameter N_RO = 8
) (
    input  wire            clk,
    input  wire            rst_n,
    input  wire            flush,
    input  wire [N_RO-1:0] ro_out,      // asynchronous
    input  wire            single_ro,   // 1 = use only ro_out[ro_sel]
    input  wire [     2:0] ro_sel,
    input  wire [     1:0] sample_div,
    output reg             raw_bit,
    output reg             raw_valid
);

  wire ro_mix = single_ro ? ro_out[ro_sel] : ^ro_out;

  reg sync0, sync1;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sync0 <= 1'b0;
      sync1 <= 1'b0;
    end else begin
      sync0 <= ro_mix;
      sync1 <= sync0;
    end
  end

  reg [9:0] cnt;
  reg [9:0] mask;
  always @(*) begin
    mask = 10'h00f;
    case (sample_div)
      2'd0: mask = 10'h00f;
      2'd1: mask = 10'h03f;
      2'd2: mask = 10'h0ff;
      2'd3: mask = 10'h3ff;
    endcase
  end

  wire strobe = ((cnt & mask) == mask);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt       <= 10'd0;
      raw_bit   <= 1'b0;
      raw_valid <= 1'b0;
    end else if (flush) begin
      cnt       <= 10'd0;
      raw_valid <= 1'b0;
    end else begin
      cnt       <= cnt + 10'd1;
      raw_valid <= strobe;
      if (strobe) raw_bit <= sync1;
    end
  end

endmodule
