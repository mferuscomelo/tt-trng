/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// NIST SP 800-90B continuous health tests on the sampled raw stream, for an
// assumed min-entropy H = 0.5 bit/sample and false-alarm rate alpha = 2^-20:
//   Repetition Count Test:   cutoff 41  (= 1 + ceil(20 / H))
//   Adaptive Proportion Test: window 1024, cutoff 793
//                             (= 1 + CRITBINOM(1024, 2^-H, 1 - alpha))
// The counters restart whenever the tests are disabled or the configuration
// changes. FAIL is sticky until reset.
module health (
    input  wire clk,
    input  wire rst_n,
    input  wire flush,
    input  wire enable,
    input  wire in_bit,
    input  wire in_valid,
    output reg  fail
);

  // Counts include the first sample, so "count == cutoff - 1" plus one more
  // matching sample means the cutoff is reached.
  localparam [5:0] RCT_LAST = 6'd40;  // RCT cutoff 41
  localparam [9:0] APT_LAST = 10'd1023;  // APT window 1024
  localparam [9:0] APT_B_LAST = 10'd792;  // APT cutoff 793

  wire restart = flush || !enable;
  wire sample = enable && in_valid;

  // ---- Repetition Count Test
  reg       rct_last;
  reg [5:0] rct_cnt;  // 0 = no sample yet in this run

  wire rct_fail = sample && (rct_cnt != 6'd0) && (in_bit == rct_last) &&
                  (rct_cnt == RCT_LAST);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rct_last <= 1'b0;
      rct_cnt  <= 6'd0;
    end else if (restart) begin
      rct_cnt <= 6'd0;
    end else if (sample) begin
      if (rct_cnt != 6'd0 && in_bit == rct_last) begin
        if (rct_cnt != RCT_LAST) rct_cnt <= rct_cnt + 6'd1;
      end else begin
        rct_last <= in_bit;
        rct_cnt  <= 6'd1;
      end
    end
  end

  // ---- Adaptive Proportion Test
  reg        apt_a;
  reg [ 9:0] apt_n;  // samples seen in the current window, 0 = window not started
  reg [ 9:0] apt_b;  // occurrences of apt_a in the current window

  wire apt_match = (in_bit == apt_a);
  wire apt_fail = sample && (apt_n != 10'd0) && apt_match && (apt_b == APT_B_LAST);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      apt_a <= 1'b0;
      apt_n <= 10'd0;
      apt_b <= 10'd0;
    end else if (restart) begin
      apt_n <= 10'd0;
    end else if (sample) begin
      if (apt_n == 10'd0) begin
        apt_a <= in_bit;
        apt_b <= 10'd1;
        apt_n <= 10'd1;
      end else begin
        if (apt_match && apt_b != APT_B_LAST) apt_b <= apt_b + 10'd1;
        apt_n <= (apt_n == APT_LAST) ? 10'd0 : apt_n + 10'd1;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) fail <= 1'b0;
    else if (rct_fail || apt_fail) fail <= 1'b1;
  end

endmodule
