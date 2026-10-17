/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Ring-oscillator TRNG with SPI readout.
module tt_um_mferuscomelo_trng (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // ---------------------------------------------------------------- config
  wire [10:0] cfg;
  wire        flush;

  source_select #(
      .W(11)
  ) u_cfg (
      .clk      (clk),
      .rst_n    (rst_n),
      .cfg_async({uio_in[6:4], ui_in}),
      .cfg      (cfg),
      .flush    (flush)
  );

  wire       ro_en = cfg[0];
  wire       whiten_en = cfg[1];
  wire       test_mode = cfg[2];
  wire [1:0] sample_div = cfg[4:3];

  // ---------------------------------------------------------------- rings
  wire [3:0] ro_out;
  wire       ring_en = rst_n & ena & ro_en;

  ring_osc #(.STAGES(5))  trng_ro0 (.clk(clk), .rst_n(rst_n), .en(ring_en), .out(ro_out[0]));
  ring_osc #(.STAGES(7))  trng_ro1 (.clk(clk), .rst_n(rst_n), .en(ring_en), .out(ro_out[1]));
  ring_osc #(.STAGES(9))  trng_ro2 (.clk(clk), .rst_n(rst_n), .en(ring_en), .out(ro_out[2]));
  ring_osc #(.STAGES(13)) trng_ro3 (.clk(clk), .rst_n(rst_n), .en(ring_en), .out(ro_out[3]));

  // ---------------------------------------------------------------- sampling
  wire raw_bit, raw_valid;

  entropy_sampler #(
      .N_RO(4)
  ) u_sampler (
      .clk       (clk),
      .rst_n     (rst_n),
      .flush     (flush),
      .ro_out    (ro_out),
      .sample_div(sample_div),
      .raw_bit   (raw_bit),
      .raw_valid (raw_valid)
  );

  wire vn_bit, vn_valid;

  whiten u_whiten (
      .clk      (clk),
      .rst_n    (rst_n),
      .flush    (flush),
      .in_bit   (raw_bit),
      .in_valid (raw_valid),
      .out_bit  (vn_bit),
      .out_valid(vn_valid)
  );

  wire lfsr_bit;
  wire pk_ready;

  lfsr_test u_lfsr (
      .clk    (clk),
      .rst_n  (rst_n),
      .flush  (flush),
      .step   (test_mode && pk_ready),
      .out_bit(lfsr_bit)
  );

  // Source priority: TEST > WHITEN > raw
  wire src_bit = test_mode ? lfsr_bit : whiten_en ? vn_bit : raw_bit;
  wire src_valid = test_mode ? 1'b1 : whiten_en ? vn_valid : raw_valid;

  // ---------------------------------------------------------------- buffering
  wire       pk_push;
  wire [7:0] pk_byte;
  wire       overflow;
  wire       fifo_full, fifo_empty;
  wire [7:0] fifo_dout;
  wire       spi_pop;
  wire       spi_cs_fall;

  byte_packer u_packer (
      .clk         (clk),
      .rst_n       (rst_n),
      .flush       (flush),
      .test_mode   (test_mode),
      .in_bit      (src_bit),
      .in_valid    (src_valid),
      .ready       (pk_ready),
      .fifo_full   (fifo_full),
      .push        (pk_push),
      .byte_out    (pk_byte),
      .overflow_clr(spi_cs_fall),
      .overflow    (overflow)
  );

  fifo #(
      .DEPTH(1)
  ) u_fifo (
      .clk  (clk),
      .rst_n(rst_n),
      .flush(flush),
      .push (pk_push),
      .din  (pk_byte),
      .pop  (spi_pop),
      .dout (fifo_dout),
      .empty(fifo_empty),
      .full (fifo_full)
  );

  // ---------------------------------------------------------------- SPI
  wire miso, miso_oe, underrun;

  spi_peripheral u_spi (
      .clk       (clk),
      .rst_n     (rst_n),
      .flush     (flush),
      .sck_async (uio_in[3]),
      .cs_n_async(uio_in[0]),
      .fifo_dout (fifo_dout),
      .fifo_empty(fifo_empty),
      .pop       (spi_pop),
      .miso      (miso),
      .miso_oe   (miso_oe),
      .cs_fall   (spi_cs_fall),
      .underrun  (underrun)
  );

  // ---------------------------------------------------------------- outputs
  wire health_fail = 1'b0;  // phase 4
  wire ro_div = 1'b0;  // phase 5

  assign uo_out = {1'b0, overflow, ro_div, raw_valid, raw_bit, underrun, health_fail, !fifo_empty};
  assign uio_out = {5'b00000, miso, 2'b00};
  assign uio_oe = {5'b00000, miso_oe, 2'b00};

  wire _unused = &{uio_in[7], uio_in[2:1], cfg[10:5], 1'b0};

endmodule
