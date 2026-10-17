/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Von Neumann debiasing: bit pairs 01 -> 0, 10 -> 1, 00 and 11 are dropped.
module whiten (
    input  wire clk,
    input  wire rst_n,
    input  wire flush,
    input  wire in_bit,
    input  wire in_valid,
    output reg  out_bit,
    output reg  out_valid
);

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
      if (in_valid) begin
        if (!have_first) begin
          first      <= in_bit;
          have_first <= 1'b1;
        end else begin
          have_first <= 1'b0;
          if (first != in_bit) begin
            out_bit   <= first;
            out_valid <= 1'b1;
          end
        end
      end
    end
  end

endmodule
