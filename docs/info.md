<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Free-running ring oscillators made of standard cells (one NAND2 enable gate plus a chain of inverters, eight rings with odd, mostly co-prime lengths 5, 7, 11, 13, 17, 19, 23 and 29 stages) run at several hundred MHz. Their outputs are XORed (or, with SINGLE_RO, one ring is chosen by RO_SEL) and sampled by the 50 MHz system clock through a two-flop synchronizer. Each ring's phase jitter accumulates between samples, so the sampled bit is unpredictable.

Processing chain:

1. **Sampling**: one sample is kept every 16, 64, 256 or 1024 clocks (SAMPLE_DIV). Longer intervals let more jitter accumulate, which makes successive bits less correlated, at the cost of throughput.
2. **Whitening** (WHITEN = 1): first XOR-decimation (DECIM: 1, 2, 4 or 8 sampled bits are XORed into one), which reduces bias and correlation; then von Neumann debiasing (bit pairs 01 → 0, 10 → 1, 00/11 dropped), which removes the remaining bias from independent bits. Output is about one bit per 4 × DECIM samples. With WHITEN = 0 the sampled bits are passed through unchanged, which is what you want for entropy assessment.
3. **TEST mode** (TEST = 1): a 16-bit LFSR (seed 0xACE1, taps 16/14/13/11) replaces the entropy source, so the whole readout path can be checked against a known answer. The first bytes are `87 35 44 E2 EC 23 B9 C7 A8 11 4A F7`.
4. **Packing and SPI**: bits are packed MSB first into bytes, buffered in a 4-byte FIFO and read through an SPI peripheral. When the FIFO is full, new entropy bits are dropped (OVERFLOW); in TEST mode the LFSR waits instead, so the known-answer sequence never skips.

Changing any configuration input (ui[7:0], uio[6:4]) flushes everything that holds partial data, so no byte ever mixes two configurations. In TEST mode the LFSR restarts from its seed.

### Pinout

| Pin | Function |
| --- | --- |
| ui[0] | RO_EN: 1 = rings run |
| ui[1] | WHITEN: 1 = von Neumann debiasing, 0 = raw sampled bits |
| ui[2] | TEST: 1 = known-answer LFSR instead of the rings (overrides WHITEN) |
| ui[4:3] | SAMPLE_DIV: keep one sample every 16 / 64 / 256 / 1024 clocks |
| ui[5] | SINGLE_RO: 1 = sample only the ring selected by RO_SEL, 0 = XOR of all 8 |
| ui[7:6] | DECIM (WHITEN = 1 only): XOR 1 / 2 / 4 / 8 sampled bits per bit |
| uo[0] | FIFO_READY: a byte is available |
| uo[1] | HEALTH_FAIL (not implemented yet, always 0) |
| uo[2] | UNDERRUN: a byte was read while none was available (0x00 sent). Cleared at the next CS fall |
| uo[3] | Last sampled raw bit |
| uo[4] | Sample strobe, one clock wide per sample |
| uo[5] | RO ÷64 (not implemented yet, always 0) |
| uo[6] | OVERFLOW: bits were dropped because the buffer was full. Cleared at the next CS fall |
| uio[0] | SPI CS_N (input) |
| uio[1] | SPI MOSI (input, unused) |
| uio[2] | SPI MISO (output, driven only while CS_N is low) |
| uio[3] | SPI SCK (input) |
| uio[6:4] | RO_SEL: ring used by SINGLE_RO (0 = 5 stages … 7 = 29 stages) |
| uio[7] | DIV_EN (not implemented yet) |

At 50 MHz the raw rate is 3.125 Mbit/s, 781 kbit/s, 195 kbit/s or 48.8 kbit/s for SAMPLE_DIV = 0..3; whitened output is about raw / (4 × DECIM).

## How to test

SPI is mode 0 (CPOL = 0, CPHA = 0), MSB first, read only. SCK and CS_N are oversampled by the system clock, so:

- SCK must be at most clk/8 (6.25 MHz at 50 MHz).
- Wait at least 100 ns after pulling CS_N low before the first rising SCK edge.

Reading:

1. Wait for FIFO_READY (uo[0]) to be high.
2. Pull CS_N low, wait 100 ns, clock out 8 bits per byte. Several bytes can be read in one transfer.
3. Pull CS_N high. Check UNDERRUN (uo[2]): if it is set, at least one of the bytes was 0x00 filler and should be discarded. OVERFLOW (uo[6]) tells you random bits were dropped because the host read too slowly (harmless for randomness, but it shows the throughput limit).

A byte is only consumed on the first SCK rising edge of that byte, so ending a transfer never loses data.

Suggested bring-up:

1. TEST = 1: read bytes and compare with `87 35 44 E2 EC 23 B9 C7 ...`. This checks the clock, SPI wiring and timing.
2. RO_EN = 1, WHITEN = 0: capture raw bytes for each ring alone (SINGLE_RO = 1, RO_SEL = 0..7) and for the XOR of all rings, at each SAMPLE_DIV, and run the NIST SP 800-90B entropy assessment tool (<https://github.com/usnistgov/SP800-90B_EntropyAssessment>) on them.
3. Choose SAMPLE_DIV and DECIM from the results, then capture whitened output (WHITEN = 1) for statistical tests.

Simulation cannot show whether the rings produce real entropy. Only measurements on silicon can.

## External hardware

Any SPI controller, for example the RP2040 on the Tiny Tapeout demo board or a microcontroller on the bidirectional PMOD header (CS = uio[0], MOSI = uio[1], MISO = uio[2], SCK = uio[3]).
