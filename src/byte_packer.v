/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Packs bits MSB first (first bit received = bit 7) and pushes full bytes into
// the FIFO. When the FIFO is full the last bit of a byte cannot be accepted:
// entropy bits are dropped (OVERFLOW), the TEST source stalls via `ready`.
module byte_packer (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       flush,
    input  wire       test_mode,
    input  wire       in_bit,
    input  wire       in_valid,
    output wire       ready,
    input  wire       fifo_full,
    output wire       push,
    output wire [7:0] byte_out,
    input  wire       overflow_clr,
    output reg        overflow
);

  reg [6:0] sr;
  reg [2:0] cnt;

  assign ready    = !((cnt == 3'd7) && fifo_full);
  wire accept = in_valid && ready;
  assign push     = accept && (cnt == 3'd7);
  assign byte_out = {sr, in_bit};

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sr  <= 7'd0;
      cnt <= 3'd0;
    end else if (flush) begin
      cnt <= 3'd0;
    end else if (accept) begin
      sr  <= {sr[5:0], in_bit};
      cnt <= cnt + 3'd1;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) overflow <= 1'b0;
    else if (in_valid && !ready && !test_mode) overflow <= 1'b1;
    else if (overflow_clr) overflow <= 1'b0;
  end

endmodule
