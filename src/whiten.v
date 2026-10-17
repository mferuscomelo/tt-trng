/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Whitening: XOR-decimation of 1 / 2 / 4 / 8 consecutive sampled bits,
// followed by von Neumann debiasing (pairs 01 -> 0, 10 -> 1, 00/11 dropped).
module whiten (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       flush,
    input  wire [1:0] decim,
    input  wire       in_bit,
    input  wire       in_valid,
    output reg        out_bit,
    output reg        out_valid
);

  // ---- XOR-decimation
  reg  [2:0] dcnt;
  reg        acc;
  wire [2:0] dlast = (decim == 2'd0) ? 3'd0 :
                     (decim == 2'd1) ? 3'd1 :
                     (decim == 2'd2) ? 3'd3 : 3'd7;
  wire       d_bit = acc ^ in_bit;
  wire       d_valid = in_valid && (dcnt == dlast);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dcnt <= 3'd0;
      acc  <= 1'b0;
    end else if (flush) begin
      dcnt <= 3'd0;
      acc  <= 1'b0;
    end else if (in_valid) begin
      if (dcnt == dlast) begin
        dcnt <= 3'd0;
        acc  <= 1'b0;
      end else begin
        dcnt <= dcnt + 3'd1;
        acc  <= d_bit;
      end
    end
  end

  // ---- von Neumann
  reg first;
  reg have_first;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      first      <= 1'b0;
      have_first <= 1'b0;
      out_bit    <= 1'b0;
      out_valid  <= 1'b0;
    end else if (flush) begin
      have_first <= 1'b0;
      out_valid  <= 1'b0;
    end else begin
      out_valid <= 1'b0;
      if (d_valid) begin
        if (!have_first) begin
          first      <= d_bit;
          have_first <= 1'b1;
        end else begin
          have_first <= 1'b0;
          if (first != d_bit) begin
            out_bit   <= first;
            out_valid <= 1'b1;
          end
        end
      end
    end
  end

endmodule
