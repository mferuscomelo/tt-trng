# SPDX-FileCopyrightText: © 2026 Milan Ferus-Comelo
# SPDX-License-Identifier: Apache-2.0

import os

import cocotb
import cocotb.utils
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

CLK_NS = 20  # 50 MHz
SPI_HALF_NS = 4 * CLK_NS  # SCK = clk/8
GATES = os.environ.get("GATES") == "yes"

# uo_out bits
FIFO_READY = 0
HEALTH_FAIL = 1
UNDERRUN = 2
RAW_BIT = 3
RAW_STROBE = 4
RO_DIV = 5
OVERFLOW = 6

# uio bits
CS_N = 0
MOSI = 1
MISO = 2
SCK = 3


def lfsr_bytes(n):
    """Reference model of the TEST-mode LFSR, packed MSB first."""
    lfsr = 0xACE1
    out = []
    for _ in range(n):
        v = 0
        for _ in range(8):
            v = (v << 1) | (lfsr & 1)
            fb = (lfsr ^ (lfsr >> 2) ^ (lfsr >> 3) ^ (lfsr >> 5)) & 1
            lfsr = (lfsr >> 1) | (fb << 15)
        out.append(v)
    return out


def bit(sig, n):
    return (int(sig.value) >> n) & 1


def cfg_ui(ro_en=0, whiten=0, test=0, sample_div=0, single_ro=0, decim=0):
    return (
        ro_en
        | (whiten << 1)
        | (test << 2)
        | (sample_div << 3)
        | (single_ro << 5)
        | (decim << 6)
    )


class Tb:
    def __init__(self, dut):
        self.dut = dut
        self.uio = (1 << CS_N)  # CS high, SCK low, MOSI low
        self.ro_sel = 0
        self.div_en = 0

    def _drive_uio(self):
        self.dut.uio_in.value = self.uio | (self.ro_sel << 4) | (self.div_en << 7)

    def set_pin(self, n, v):
        self.uio = (self.uio & ~(1 << n)) | (v << n)
        self._drive_uio()

    async def start(self, **cfg):
        dut = self.dut
        cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
        dut.ena.value = 1
        dut.ui_in.value = 0
        self._drive_uio()
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 10)
        dut.rst_n.value = 1
        await ClockCycles(dut.clk, 5)
        await self.configure(**cfg)

    async def configure(self, ro_sel=0, **cfg):
        self.ro_sel = ro_sel
        self._drive_uio()
        self.dut.ui_in.value = cfg_ui(**cfg)
        await ClockCycles(self.dut.clk, 5)  # sync + flush

    def uo(self, n):
        return bit(self.dut.uo_out, n)

    async def wait_ready(self, timeout_cycles=200000):
        for _ in range(timeout_cycles):
            if self.uo(FIFO_READY):
                return
            await RisingEdge(self.dut.clk)
        assert False, "timeout waiting for FIFO_READY"

    async def spi_read(self, nbytes=1, check_oe=True):
        """Mode 0 read of nbytes in one CS window."""
        self.set_pin(CS_N, 0)
        await Timer(120, unit="ns")
        if check_oe:
            assert bit(self.dut.uio_oe, MISO) == 1, "MISO not driven while CS low"
        data = []
        for _ in range(nbytes):
            v = 0
            for _ in range(8):
                await Timer(SPI_HALF_NS, unit="ns")
                v = (v << 1) | bit(self.dut.uio_out, MISO)  # sample at rising edge
                self.set_pin(SCK, 1)
                await Timer(SPI_HALF_NS, unit="ns")
                self.set_pin(SCK, 0)
            data.append(v)
        await Timer(SPI_HALF_NS, unit="ns")
        self.set_pin(CS_N, 1)
        await ClockCycles(self.dut.clk, 5)
        return data

    async def read_bytes(self, n):
        """Read n bytes one at a time, waiting for FIFO_READY before each."""
        out = []
        for _ in range(n):
            await self.wait_ready()
            out += await self.spi_read(1)
            assert self.uo(UNDERRUN) == 0, "unexpected UNDERRUN"
        return out


def ones_ratio(data):
    return sum(bin(b).count("1") for b in data) / (8 * len(data))


@cocotb.test()
async def test_reset_idle(dut):
    tb = Tb(dut)
    await tb.start()
    assert dut.uo_out.value.is_resolvable, f"X/Z on uo_out: {dut.uo_out.value}"
    assert dut.uio_out.value.is_resolvable, f"X/Z on uio_out: {dut.uio_out.value}"
    for n in (HEALTH_FAIL, UNDERRUN, OVERFLOW):
        assert tb.uo(n) == 0
    assert int(dut.uio_oe.value) == 0, "uio_oe must be 0 while CS high"
    tb.set_pin(CS_N, 0)
    await ClockCycles(dut.clk, 5)
    assert int(dut.uio_oe.value) == 0b0000_0100
    tb.set_pin(CS_N, 1)
    await ClockCycles(dut.clk, 5)
    assert int(dut.uio_oe.value) == 0


@cocotb.test()
async def test_known_answer(dut):
    tb = Tb(dut)
    await tb.start(test=1)
    expected = lfsr_bytes(32)
    assert expected[:4] == [0x87, 0x35, 0x44, 0xE2]
    got = []
    for _ in range(32):
        await tb.wait_ready()
        await ClockCycles(dut.clk, 200)  # slow host: source must stall, not skip
        got += await tb.spi_read(1)
    assert got == expected, f"{[hex(x) for x in got]}"
    assert tb.uo(OVERFLOW) == 0


@cocotb.test()
async def test_flush(dut):
    tb = Tb(dut)
    await tb.start(test=1)
    first = await tb.read_bytes(3)
    assert first == lfsr_bytes(3)
    await tb.configure(ro_en=1, whiten=1)
    await tb.configure(test=1)
    again = await tb.read_bytes(3)
    assert again == lfsr_bytes(3), "LFSR must restart after a config change"
    # FIFO_READY drops on a config change
    await tb.wait_ready()
    dut.ui_in.value = cfg_ui(ro_en=1)
    await ClockCycles(dut.clk, 5)  # 2-FF sync + flush; a new raw byte needs >= 128 clocks
    assert tb.uo(FIFO_READY) == 0


@cocotb.test(skip=GATES)
async def test_raw(dut):
    tb = Tb(dut)
    await tb.start(ro_en=1)
    data = await tb.read_bytes(64)
    r = ones_ratio(data)
    dut._log.info(f"raw ones ratio {r:.3f}")
    assert 0.35 < r < 0.65
    assert len(set(data)) > 1


@cocotb.test(skip=GATES)
async def test_whitened(dut):
    tb = Tb(dut)
    await tb.start()
    cycles = []
    for decim in range(4):
        await tb.configure(ro_en=1, whiten=1, decim=decim)
        t0 = cocotb.utils.get_sim_time("ns")
        data = await tb.read_bytes(8 if decim < 3 else 4)
        cycles.append((cocotb.utils.get_sim_time("ns") - t0) / len(data))
        r = ones_ratio(data)
        dut._log.info(f"DECIM={decim}: ones ratio {r:.3f}, {cycles[-1]:.0f} ns/byte")
        assert 0.25 < r < 0.75
        assert len(set(data)) > 1
    # each DECIM step halves the rate; allow generous slack for randomness
    assert cycles[1] > 1.3 * cycles[0]
    assert cycles[3] > 3 * cycles[1]


@cocotb.test()
async def test_single_ro_mux(dut):
    tb = Tb(dut)
    await tb.start()
    # Stopped rings all output 1: one ring reads 1, the XOR of eight reads 0.
    await tb.configure(ro_en=0, single_ro=0)
    assert await tb.read_bytes(2) == [0x00, 0x00]
    for sel in range(8):
        await tb.configure(ro_en=0, single_ro=1, ro_sel=sel)
        assert await tb.read_bytes(2) == [0xFF, 0xFF], f"RO_SEL={sel}"


@cocotb.test(skip=GATES)
async def test_single_ro_raw(dut):
    tb = Tb(dut)
    await tb.start()
    for sel in (0, 7):
        await tb.configure(ro_en=1, single_ro=1, ro_sel=sel)
        data = await tb.read_bytes(16)
        r = ones_ratio(data)
        dut._log.info(f"RO_SEL={sel}: ones ratio {r:.3f}")
        assert 0.3 < r < 0.7


@cocotb.test()
async def test_rings_run(dut):
    """The sampled raw bit must change when the rings run (at gate level this
    shows that the ring cells in the real netlist oscillate)."""
    tb = Tb(dut)
    await tb.start(ro_en=1)
    values = []
    for _ in range(64):
        await RisingEdge(dut.clk)
        while not tb.uo(RAW_STROBE):
            await RisingEdge(dut.clk)
        values.append(tb.uo(RAW_BIT))
    assert 0 in values and 1 in values, "raw bit stuck with rings enabled"


@cocotb.test()
async def test_rings_off_raw(dut):
    tb = Tb(dut)
    await tb.start(ro_en=0, whiten=0)
    data = await tb.read_bytes(4)
    assert data == [0, 0, 0, 0]
    assert tb.uo(HEALTH_FAIL) == 0


@cocotb.test()
async def test_underrun(dut):
    tb = Tb(dut)
    await tb.start(ro_en=0, whiten=1)  # constant stream: von Neumann emits nothing
    await ClockCycles(dut.clk, 2000)
    assert tb.uo(FIFO_READY) == 0
    data = await tb.spi_read(1)
    assert data == [0]
    assert tb.uo(UNDERRUN) == 1
    tb.set_pin(CS_N, 0)
    await ClockCycles(dut.clk, 5)
    assert tb.uo(UNDERRUN) == 0, "UNDERRUN must clear on CS fall"
    tb.set_pin(CS_N, 1)
    await ClockCycles(dut.clk, 5)


@cocotb.test()
async def test_no_byte_lost_between_transfers(dut):
    tb = Tb(dut)
    await tb.start(test=1)
    got = []
    for _ in range(6):
        await tb.wait_ready()
        got += await tb.spi_read(1)
        assert tb.uo(UNDERRUN) == 0
    assert got == lfsr_bytes(6)


@cocotb.test()
async def test_burst(dut):
    tb = Tb(dut)
    await tb.start(test=1)
    await tb.wait_ready()
    got = await tb.spi_read(4)
    assert got == lfsr_bytes(4)
    assert tb.uo(UNDERRUN) == 0


@cocotb.test()
async def test_overflow(dut):
    tb = Tb(dut)
    await tb.start(ro_en=0, whiten=0)  # raw: one bit every 16 clocks, never stops
    await ClockCycles(dut.clk, 16 * 8 * 8)
    assert tb.uo(OVERFLOW) == 1
    tb.set_pin(CS_N, 0)
    await ClockCycles(dut.clk, 5)
    assert tb.uo(OVERFLOW) == 0, "OVERFLOW must clear on CS fall"
    tb.set_pin(CS_N, 1)
    await ClockCycles(dut.clk, 5)


@cocotb.test()
async def test_sample_interval(dut):
    tb = Tb(dut)
    await tb.start()
    for div, period in enumerate((16, 64, 256, 1024)):
        await tb.configure(sample_div=div)
        await ClockCycles(dut.clk, period)  # settle after flush
        strobes = 0
        for _ in range(4 * period):
            await RisingEdge(dut.clk)
            strobes += tb.uo(RAW_STROBE)
        assert strobes == 4, f"SAMPLE_DIV={div}: {strobes} strobes in {4 * period} clocks"
