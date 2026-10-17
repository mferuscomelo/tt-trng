// SPDX-FileCopyrightText: © 2026 Milan Ferus-Comelo
// SPDX-License-Identifier: Apache-2.0

// Gate-level simulation only. The sky130 functional models give combinational
// cells zero delay, so a ring oscillator would loop forever at one time step.
// The Makefile swaps the ring cells (instances named trng_ro*) for these
// copies with a 1 ns delay. The rings then oscillate deterministically with a
// period of 2 * stages * 1 ns; this checks connectivity, not randomness.

`timescale 1ns / 1ps

module gl_ring_inv_1 (
    input  wire A,
    input  wire VGND,
    input  wire VNB,
    input  wire VPB,
    input  wire VPWR,
    output wire Y
);
  assign #1 Y = ~A;
endmodule

module gl_ring_nand2_1 (
    input  wire A,
    input  wire B,
    input  wire VGND,
    input  wire VNB,
    input  wire VPB,
    input  wire VPWR,
    output wire Y
);
  assign #1 Y = ~(A & B);
endmodule
