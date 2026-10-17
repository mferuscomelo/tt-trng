/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Synchronizes the configuration pins and pulses `flush` for one clock in the
// first cycle of any new configuration.
module source_select #(
    parameter W = 11
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [W-1:0] cfg_async,
    output wire [W-1:0] cfg,
    output wire         flush
);

  reg [W-1:0] sync0, sync1, prev;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sync0 <= {W{1'b0}};
      sync1 <= {W{1'b0}};
      prev  <= {W{1'b0}};
    end else begin
      sync0 <= cfg_async;
      sync1 <= sync0;
      prev  <= sync1;
    end
  end

  assign cfg   = sync1;
  assign flush = (sync1 != prev);

endmodule
