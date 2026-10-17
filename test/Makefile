# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = project.v ring_osc.v source_select.v entropy_sampler.v whiten.v lfsr_test.v byte_packer.v fifo.v spi_peripheral.v health.v

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
COMPILE_ARGS    += -DSIM

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
COMPILE_ARGS    += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v

# this gets copied in by the GDS action workflow
GL_NETLIST = $(PWD)/gate_level_netlist.v

# The ring oscillator cells (instances trng_ro*) get a 1 ns delay so the
# zero-delay functional models do not hang the simulator. See gl_ring_cells.v.
GL_NETLIST_RINGS = $(PWD)/gate_level_netlist_rings.v
VERILOG_SOURCES += $(GL_NETLIST_RINGS)
VERILOG_SOURCES += $(PWD)/gl_ring_cells.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim

ifeq ($(GATES),yes)
$(GL_NETLIST_RINGS): $(GL_NETLIST)
	sed -E 's/^( *)sky130_fd_sc_hd__(inv_1|nand2_1) (\\trng_ro)/\1gl_ring_\2 \3/' $< > $@
	@n=$$(grep -c '^ *gl_ring_' $@); echo "ring cells given a delay: $$n"; test $$n -gt 0
endif
