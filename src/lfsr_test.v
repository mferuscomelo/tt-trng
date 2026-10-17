/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Known-answer source for TEST mode. 16-bit Fibonacci LFSR, period 65535.
// Advances only when its current bit is accepted (`step`).
module lfsr_test (
    input  wire clk,
    input  wire rst_n,
    input  wire flush,
    input  wire step,
    output wire out_bit
);

  localparam [15:0] SEED = 16'hACE1;

  reg [15:0] l;
  wire fb = l[0] ^ l[2] ^ l[3] ^ l[5];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) l <= SEED;
    else if (flush) l <= SEED;
    else if (step) l <= {fb, l[15:1]};
  end

  assign out_bit = l[0];

endmodule
