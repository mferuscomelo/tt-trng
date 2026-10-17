/*
 * Copyright (c) 2026 Milan Ferus-Comelo
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Free-running ring oscillator: one NAND2 (enable) followed by STAGES-1
// inverters. STAGES must be odd. The cells are instantiated by name so that
// synthesis keeps the loop exactly as written.
module ring_osc #(
    parameter STAGES = 5
) (
    input  wire clk,    // used only by the simulation stand-in
    input  wire rst_n,  // used only by the simulation stand-in
    input  wire en,     // 1 = run, 0 = stop (NAND output sticks at 1)
    output wire out
);

`ifdef SIM
  // RTL stand-in: a random bit per clock. A zero-delay loop would hang the simulator.
  reg sim_out;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sim_out <= 1'b1;
    else if (!en) sim_out <= 1'b1;
    else sim_out <= $random;
  end
  assign out = sim_out;
`else
  /* verilator lint_off UNOPTFLAT */
  (* keep *) wire [STAGES-1:0] chain;
  /* verilator lint_on UNOPTFLAT */

  /* verilator lint_off PINMISSING */
  (* keep *)
  sky130_fd_sc_hd__nand2_1 u_nand (
      .A(chain[STAGES-1]),
      .B(en),
      .Y(chain[0])
  );

  genvar i;
  generate
    for (i = 1; i < STAGES; i = i + 1) begin : g_inv
      (* keep *)
      sky130_fd_sc_hd__inv_1 u_inv (
          .A(chain[i-1]),
          .Y(chain[i])
      );
    end
  endgenerate
  /* verilator lint_on PINMISSING */

  assign out = chain[0];

  wire _unused = &{clk, rst_n, 1'b0};
`endif

endmodule
