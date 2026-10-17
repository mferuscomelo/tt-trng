/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// SPI mode 0 peripheral, MSB first, read only. SCK and CS_N are oversampled by
// `clk` (SCK <= clk/8).
//
// The FIFO head is loaded into the shift register on CS fall and after every
// 8th SCK falling edge, so bytes can be read in bursts. The byte is only
// consumed (popped) on the first SCK rising edge of that byte, so ending a
// transfer never discards a byte. If the FIFO was empty at load time, 0x00 is
// sent and UNDERRUN is set on that rising edge; it stays set until the next
// CS fall.
module spi_peripheral (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       flush,
    input  wire       sck_async,
    input  wire       cs_n_async,
    input  wire [7:0] fifo_dout,
    input  wire       fifo_empty,
    output wire       pop,
    output wire       miso,
    output wire       miso_oe,
    output wire       cs_fall,
    output reg        underrun
);

  reg [2:0] sck_s, cs_s;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sck_s <= 3'b000;
      cs_s  <= 3'b111;
    end else begin
      sck_s <= {sck_s[1:0], sck_async};
      cs_s  <= {cs_s[1:0], cs_n_async};
    end
  end

  wire cs_low = !cs_s[1];
  assign cs_fall = !cs_s[1] && cs_s[2];
  wire sck_rise = cs_low && sck_s[1] && !sck_s[2];
  wire sck_fall = cs_low && !sck_s[1] && sck_s[2];

  reg [7:0] shreg;
  reg [2:0] bitcnt;
  reg       commit_pending;  // byte loaded, not yet consumed
  reg       loaded_valid;  // loaded byte came from the FIFO

  wire load = cs_fall || (sck_fall && (bitcnt == 3'd7));
  wire commit = sck_rise && commit_pending;
  assign pop = commit && loaded_valid;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      shreg          <= 8'h00;
      bitcnt         <= 3'd0;
      commit_pending <= 1'b0;
      loaded_valid   <= 1'b0;
      underrun       <= 1'b0;
    end else begin
      if (cs_fall) underrun <= 1'b0;

      if (load) begin
        shreg          <= fifo_empty ? 8'h00 : fifo_dout;
        loaded_valid   <= !fifo_empty;
        commit_pending <= 1'b1;
        bitcnt         <= 3'd0;
      end else if (sck_fall) begin
        shreg  <= {shreg[6:0], 1'b0};
        bitcnt <= bitcnt + 3'd1;
      end

      if (commit) begin
        commit_pending <= 1'b0;
        if (!loaded_valid) underrun <= 1'b1;
      end

      // A config change empties the FIFO: the loaded byte no longer exists there.
      if (flush) loaded_valid <= 1'b0;
    end
  end

  assign miso    = shreg[7];
  assign miso_oe = cs_low;

endmodule
