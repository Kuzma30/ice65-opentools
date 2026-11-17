# iCE65L04 device notes

What the `l04` device of the patched icestorm / nextpnr knows about the
iCE65L04, how sure it is, and where it differs from the iCE40.

All of it was derived from one vendor image (the FPGA image V2.61 of the
DS203 oscilloscope, 68088 bytes) and the board schematic; see
[derivation.md](derivation.md). "Confirmed" means seen in that image (and,
where noted, on hardware); "assumed" means taken over from the iCE40 by
analogy.

## Summary

| Part | State | Notes |
| --- | --- | --- |
| Bitstream container | confirmed | identical to iCE40: sync word, commands, CRC |
| CRAM / BRAM size | confirmed | 4 banks of 656 x 176 / 4 banks of 80 x 128, as iCE40 LM4K |
| Tile grid | confirmed | 24 x 20 tiles + IO ring, RAM in columns 6 and 19 (20 blocks) |
| Routing, LUTs, flip-flops | confirmed | same bits as iCE40 8k / LM4K |
| Carry chain | confirmed | carry-in bits moved, see below |
| Block RAM | confirmed for 256 x 16 | tile layout of the iCE40 1k; only mode 0 seen |
| Global networks | 4 of 8 confirmed | others assumed, not offered to the placer by default |
| Column buffers | confirmed absent | no ColBufCtrl bit set in the vendor image |
| IO banks 0, 1, 2 | confirmed for LVCMOS | pull-up bit only |
| IO bank 3 (left) | confirmed for the default standard | different IO cell, see below |
| PLL, DSP, SPRAM, LVDS | absent / not supported | |
| IO latch, warm boot, DDR IO | unknown | placeholders only |
| Timing | estimate | iCE40 LP8K x 1.3, no measurements |
| Package VQ100 | 45 pins confirmed | the pins wired on the DS203, see the pin table |

## Bitstream and the device ID

The image carries no device ID, and its CRAM geometry is the one of the
iCE40 LM4K, so `iceunpack` cannot tell the two apart: `iceunpack -6`
selects the L04. `icepack` takes the device from the `.device l04` line of
the ASCII file. icepack writes a 4 byte comment header; vendor images start
with the sync word `7e aa 99 7e`, `ice65-build` removes the header. With it
or without it, `iceunpack` + `icepack` of the vendor image gives the same
bytes.

## Logic tile: carry-in

| Function | iCE40 | iCE65 L04 |
| --- | --- | --- |
| carry-in of LC0 from the tile below | `B1[49]` | `B1[1]` |
| carry-in of LC0 = constant (CarryInSet) | `B1[50]` | `B1[0]` |

`B1[1]` is set in 49 tiles of the vendor image, exactly those whose tile
below has a carry out of LC7 (49 of 49). `B1[0]` is set in 8 tiles, all of
them starts of carry chains; the value 1 is assumed. icebox_vlog and the
chip database use these bits for `l04`.

## Block RAM

The RAM tiles have the bit layout of the iCE40 **1k**, not of the 8k / LM4K:
with the 1k database the DS203 design writes on its sampling clock and
reads on the bus read strobe, as its sources say; with the 8k database the
two ports come out swapped.

Only the 256 x 16 mode (READ_MODE = WRITE_MODE = 0, bit write mask) is
seen in the vendor image: its 4096 x 18 memory is made of 18 blocks used
as 4096 x 1 (mask selects the bit, a 16:1 multiplexer reads it). The yosys
rules of this repository therefore map memories to 256 x 16 only; deeper
memories are built by hand, see `lib/ram4096_l04.v`. Initial contents (INIT)
are written like on the iCE40 1k; not compared with a vendor image.

## Global networks

The 1k arrangement, moved to the centre tiles of the L04:

| Network | Fabric input (gbufin) | Pad input (padin) | VQ100 pin |
| --- | --- | --- | --- |
| 0 | (25, 10) assumed | (25, 10, 1) assumed | 62 |
| 1 | (0, 10) assumed | (0, 10, 1) **confirmed** | 15 |
| 2 | (13, 21) assumed | (13, 21, 0) assumed | 89 |
| 3 | (13, 0) **confirmed** | (13, 0, 0) assumed | 34 |
| 4 | (0, 11) **confirmed** | (0, 11, 0) assumed | 13 |
| 5 | (25, 11) assumed | (25, 11, 0) assumed | 63 |
| 6 | (12, 0) **confirmed** | (12, 0, 1) assumed | 33 |
| 7 | (12, 21) assumed | (12, 21, 1) assumed | 90 |

nextpnr offers only the confirmed ones: fabric inputs 3, 4, 6 and the pad
of network 1 (pin 15). Network 1 exists as a pad-only buffer: a clock on
pin 15 reaches it through `SB_GB_IO`. With fewer than 8 buffers the packer
keeps them for clocks (no promotion of resets / enables). Building the chip
database with `ICE65_UNVERIFIED=1` in the environment offers all eight.

The enable bits of the pad inputs (extra bits): only `(0, 655, 175)` =
padin of network 1 is confirmed.

## IO

Banks 0, 1 and 2 (top, right, bottom): the iCE40 IO tile, except that the
input-enable bits are never set; a pad z of a tile uses `REN_(1-z)` of the
same tile (pull-up off when set), seen on 22 tiles.

Bank 3 (left side) has a different IO cell. The bits the iCE40 database
calls IE / REN / PLLCONFIG mean:

| Bits | Meaning (as seen) |
| --- | --- |
| `B6[2] B6[3] B9[3]` | pad 0 used |
| `B0[3] B2[2] B3[3]` | pad 1 used |
| `B8[3]` | pad 0 input not used |
| `B5[3]` | pad 1 input not used |

The three "used" bits probably select the IO standard; only the
combination written by the vendor tool for its default is known, and it is
the one nextpnr writes. Pull-ups in bank 3 are not supported (warning).

## VQ100 pins

Pad of every pin used by the DS203 design (tile x, y, pad z), from the
order of the pins around the die and their directions. The IO and supply
pin numbers match the iCE40HX1K-VQ100.

| Side | Pins (pin: x, y, z) |
| --- | --- |
| left | 2: 0,20,0 · 15: 0,10,1 · 20: 0,4,1 · 24: 0,2,1 · 25: 0,2,0 |
| bottom | 27: 3,0,0 · 29: 4,0,0 · 30: 4,0,1 · 33: 12,0,1 · 34: 13,0,0 · 36: 19,0,0 · 37: 19,0,1 · 40: 21,0,1 · 41: 22,0,0 · 42: 22,0,1 |
| right | 51: 25,1,0 · 52: 25,1,1 · 53: 25,2,0 · 54: 25,2,1 · 56: 25,3,0 · 57: 25,3,1 · 59: 25,4,0 · 62: 25,10,1 · 64: 25,16,0 · 65: 25,16,1 · 66: 25,17,0 · 68: 25,18,0 |
| top | 78: 24,21,1 · 79: 23,21,1 · 80: 23,21,0 · 81: 22,21,0 · 82: 21,21,1 · 83: 21,21,0 · 85: 20,21,1 · 86: 20,21,0 · 87: 19,21,1 · 90: 12,21,1 · 91: 6,21,1 · 93: 6,21,0 · 94: 5,21,1 · 95: 5,21,0 · 96: 4,21,1 · 97: 4,21,0 · 99: 3,21,0 · 100: 2,21,0 |

Placed by pin order, not seen in an image: 1 (0,20,1), 13 (0,11,0),
28 (3,0,1), 63 (25,11,0), 89 (13,21,0). Every other pin: unknown, a design
that uses it is refused by nextpnr.

## Timing

There is no timing data for the iCE65. `timings_l04.txt` is the iCE40 LP8K
model scaled by 1.3, and nextpnr uses the LP timing class for it. Compare
reported numbers between builds, not with the clock you need: the stock
DS203 design gets 51 MHz from this model and runs at 72 MHz on the chip, so
the estimate is pessimistic by a factor of about 1.4 for that design.

## Hardware results

DS203 HW 2.7 (iCE65L04F-TVQ100C), FPGA image 2.64 built with this flow
(3122 of 3520 logic cells, 18 of 20 RAM blocks, 45 pins, 4 global
networks): the image loads, the oscilloscope works, the edge counters of
CH_C count exactly up to 6 MHz (100000 pulses exactly; square bursts
1 kHz ... 6 MHz with equal rising and falling counts).
