/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Byte FIFO. DEPTH may be any value >= 1.
module fifo #(
    parameter DEPTH = 1
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       flush,
    input  wire       push,
    input  wire [7:0] din,
    input  wire       pop,
    output wire [7:0] dout,
    output wire       empty,
    output wire       full
);

  localparam PW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam CW = $clog2(DEPTH + 1);
  localparam integer LAST_I = DEPTH - 1;
  localparam integer FULL_I = DEPTH;
  localparam [PW-1:0] LAST = LAST_I[PW-1:0];
  localparam [CW-1:0] FULL = FULL_I[CW-1:0];

  reg [7:0] mem[0:DEPTH-1];
  reg [CW-1:0] count;
  reg [PW-1:0] rd, wr;

  wire do_push = push && !full;
  wire do_pop = pop && !empty;

  assign empty = (count == {CW{1'b0}});
  assign full  = (count == FULL);
  assign dout  = mem[rd];

  integer i;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= 0;
      rd    <= 0;
      wr    <= 0;
      for (i = 0; i < DEPTH; i = i + 1) mem[i] <= 8'h00;
    end else if (flush) begin
      count <= 0;
      rd    <= 0;
      wr    <= 0;
    end else begin
      if (do_push) begin
        mem[wr] <= din;
        wr <= (wr == LAST) ? {PW{1'b0}} : wr + 1'b1;
      end
      if (do_pop) rd <= (rd == LAST) ? {PW{1'b0}} : rd + 1'b1;
      if (do_push && !do_pop) count <= count + 1'b1;
      else if (do_pop && !do_push) count <= count - 1'b1;
    end
  end

endmodule
