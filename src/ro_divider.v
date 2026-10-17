/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Debug only: divides the selected ring's frequency by 64 with a ripple
// counter so it can be measured on a pin. The counter runs in the ring's own
// clock domain and drives nothing but the output pin.
module ro_divider #(
    parameter N_RO = 8
) (
    input  wire            clk,
    input  wire            rst_n,
    input  wire            div_en_async,
    input  wire [N_RO-1:0] ro_out,        // asynchronous
    input  wire [     2:0] ro_sel,        // synchronized
    output wire            div_out
);

  reg [1:0] en_s;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) en_s <= 2'b00;
    else en_s <= {en_s[0], div_en_async};
  end
  wire en = en_s[1];

  wire div_clk = en & ro_out[ro_sel];

  reg [5:0] q;

  always @(posedge div_clk or negedge rst_n) begin
    if (!rst_n) q[0] <= 1'b0;
    else q[0] <= ~q[0];
  end

  genvar i;
  generate
    for (i = 1; i < 6; i = i + 1) begin : g_stage
      always @(negedge q[i-1] or negedge rst_n) begin
        if (!rst_n) q[i] <= 1'b0;
        else q[i] <= ~q[i];
      end
    end
  endgenerate

  assign div_out = en & q[5];

endmodule
