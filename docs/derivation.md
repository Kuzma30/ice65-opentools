# How the L04 data was derived

The icestorm database of the iCE40 was built by "fuzzing": the vendor tool
compiles thousands of small designs and the changed bits are recorded. For
the iCE65 no vendor tool was used. The data comes from:

- one vendor image: the FPGA image V2.61 of the DS203 oscilloscope
  (`V261FPGA.BIN`, in the [gabonator/LA104](https://github.com/gabonator/LA104)
  repository, `tools/fpga/ds203_8mb_hwV272-V261FPGA`), built by e-Design
  with SiliconBlue / Lattice iCEcube;
- the open Verilog sources of a close relative of that design (e-Design
  FPGA 2.5, MIT licence) — they say which signal is a clock, which a RAM,
  which a counter;
- the DS203 schematic (V2.7): which FPGA pin carries which signal;
- the iCE40 databases of icestorm.

## Steps

1. **Container.** `iceunpack` (unchanged) read the image: same commands and
   CRC as the iCE40, CRAM 656 x 176 x 4 = the iCE40 LM4K geometry. Packing
   it again gave the same bytes.
2. **Tiles.** `icebox_explain` with the LM4K / 8k databases explained
   about 13800 routing and logic entries; only three kinds of bits were
   left unknown: two in the logic tile, several in the left IO column.
3. **Netlist.** `icebox_vlog` turned the image into Verilog. Undriven nets
   pointed at what was missing: carry-in from the tile below, the constant
   carry-in, and three global networks.
4. **Carry.** `B1[1]` was set exactly where the tile below ends a carry
   chain (49 of 49), `B1[0]` only at chain starts (8 of 8).
5. **RAM.** Following the ADC data into the RAM blocks and out to the bus
   (as the sources describe) worked with the iCE40 1k RAM layout and gave
   swapped ports with the 8k one.
6. **Pins.** The pins of the VQ100 run around the die in the same order as
   the IO tiles; matching the input / output direction of every pin in the
   image with the schematic fixed the pin of each IO site. The ADC bits
   came out in the order of the schematic (data bit k of channel A at bus
   bit k), which checks the result.
7. **Globals.** Which tile drives which network, and the pad of the clock
   on pin 15, came from the netlist; the rest of the table is the iCE40 1k
   one moved to the centre of the L04 grid.
8. **Left IO bank.** The extra bits were sorted by whether the pad is used
   and whether its input is used.

## Checks

- Vendor image: unpack + explain shows no unknown bits; the recovered
  netlist has no undriven or multiply driven net; clock domains, carry
  chains and RAM blocks match the sources.
- Own builds: every bitstream built by the flow is unpacked, turned into a
  netlist and simulated against the synthesized design (`flow/ice65-check`).
  This checks nextpnr and icepack against the database; it cannot find
  errors of the database where the vendor image shows nothing.
- Hardware: see [device-notes.md](device-notes.md#hardware-results).

## Helping

Any second vendor image of an iCE65 (L01, L04, L08, another package)
narrows the unknowns. Most useful:

- a design that uses the other global buffer pins (62, 89, 34, 13, 63, 33,
  90) as clocks, or many clocks from logic;
- other RAM modes (512 x 8, 1024 x 4, 2048 x 2), INIT values;
- registered or DDR IO, other IO standards in bank 3;
- any pin not wired on the DS203.

Testing on hardware what is assumed works as well: build a small design
with `ICE65_UNVERIFIED=1` that clocks a counter from one of the assumed
networks, flash it and see whether it runs.
