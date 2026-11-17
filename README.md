# ice65-opentools

Open-source synthesis, place and route and bitstream generation for the
**Lattice (SiliconBlue) iCE65L04** FPGA: [Yosys](https://github.com/YosysHQ/yosys),
[nextpnr-ice40](https://github.com/YosysHQ/nextpnr) and
[Project IceStorm](https://github.com/YosysHQ/icestorm), with patches that add
the device `l04` (package VQ100).

The iCE65 is the predecessor of the iCE40 and has never been supported by
the open tools. The device data here was derived without the vendor tool,
from one vendor-built image (the FPGA of the DS203 oscilloscope), the board
schematic and the iCE40 databases — see [docs/derivation.md](docs/derivation.md).

## Status

**Experimental, but working on hardware.** A complete design built with this
flow — the oscilloscope FPGA of the DS203 with added edge counters and
quadrature decoders, 3122 of 3520 logic cells, 18 RAM blocks, 4 clocks —
runs on a DS203 HW 2.7 (iCE65L04F-TVQ100C).

| Works | Limited / unknown |
| --- | --- |
| LUTs, flip-flops, carry chains, routing | timing: an estimate, not measured |
| block RAM 256 x 16 with bit write mask | other RAM modes (512 x 8 ...) not mapped |
| 45 pins of the VQ100 (those wired on the DS203) | other pins: pad not known |
| 4 global networks (pin 15 pad + 3 from logic) | 4 more assumed, off by default |
| IO banks 0–2, bank 3 with its default standard | pull-ups in bank 3, IO latch, DDR IO, LVDS |
| unpacking and analysing vendor images | other iCE65 devices (L01, L08, P04) |

Details: [docs/device-notes.md](docs/device-notes.md).

## Contents

```
patches/   icestorm-ice65-l04.patch, nextpnr-ice65-l04.patch
scripts/   setup.sh: fetch, patch, build and install icestorm + nextpnr
flow/      ice65-build (yosys -> nextpnr -> icepack), ice65-check (bitstream
           check by simulation), yosys RAM rules for the L04
lib/       ram4096_l04.v: 4096 x N memory from 256 x 16 blocks
examples/  ds203_blinky (first-light design), ds203_pins (pin file of the DS203)
tests/     run_all.sh and test designs
docs/      device notes, derivation, DS203
```

## Requirements

Linux (tested on Ubuntu 24.04) or another system with:

- git, make, CMake 3.13+, a C++17 compiler, Python 3
- Boost (filesystem, program_options, iostreams, system, thread) and Eigen 3
  for nextpnr
- Yosys, a recent release (tested: 0.71)
- Icarus Verilog 11+ for `ice65-check` and the tests

Debian / Ubuntu:

```sh
sudo apt-get install build-essential cmake git python3 python3-pip iverilog curl \
    libboost-filesystem-dev libboost-program-options-dev libboost-iostreams-dev \
    libboost-system-dev libboost-thread-dev libboost-dev libeigen3-dev
```

Yosys, one of:

- [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (has
  `yosys` and `yosys-config`; do not use its nextpnr / icestorm for the L04:
  put the patched ones first in `PATH`);
- `pip install yowasp-yosys` (command `yowasp-yosys`, found automatically);
- the distribution package, if it is recent (the flow uses the
  `synth_ice40` labels `map_ram` / `map_ffram` and `memory_libmap`).

## 1. Build the tools

```sh
git clone <this repository> ice65-opentools
cd ice65-opentools
scripts/setup.sh
export PATH="$PWD/install/bin:$PATH"
```

`setup.sh` fetches icestorm and nextpnr at the commits the patches were made
for, applies the patches, builds icepack, icebox and nextpnr-ice40 and
installs them into `./install` (about 10 minutes, nextpnr most of it).
It can be run again; finished steps are kept.

| Variable | Default | |
| --- | --- | --- |
| `PREFIX` | `./install` | install folder |
| `WORK` | `./build-tools` | sources and build files |
| `JOBS` | CPU count | parallel jobs |
| `ICE40_DEVICES` | `l04` | chip databases built into nextpnr; `"1k 5k 8k l04"` keeps the iCE40 devices as well |
| `ICE65_UNVERIFIED` | unset | `1`: offer all 8 global buffers of the L04 (4 are not confirmed) |

Check:

```sh
nextpnr-ice40 --help 2>&1 | grep l04   # --l04   set device type to iCE65L04 (experimental)
ls install/share/icebox/chipdb-l04.txt
```

<details>
<summary>The same by hand</summary>

```sh
git clone https://github.com/YosysHQ/icestorm && cd icestorm
git checkout 00da9c3e6ceff056248e3451dd6fd3210d6ceec9
git apply ../ice65-opentools/patches/icestorm-ice65-l04.patch
make -C icepack && make -C icebox
make -C icepack install PREFIX=$HOME/ice65
make -C icebox install PREFIX=$HOME/ice65
cp icefuzz/timings_*.txt $HOME/ice65/share/icebox/
cd ..
git clone --recurse-submodules https://github.com/YosysHQ/nextpnr && cd nextpnr
git checkout 5e2718b6364e189e414c35b8eef3db4d5e3c0773 && git submodule update --init --recursive
git apply ../ice65-opentools/patches/nextpnr-ice65-l04.patch
cmake -B build -DARCH=ice40 -DICE40_DEVICES=l04 -DICESTORM_INSTALL_PREFIX=$HOME/ice65 \
      -DCMAKE_INSTALL_PREFIX=$HOME/ice65 -DBUILD_PYTHON=OFF -DBUILD_GUI=OFF
cmake --build build -j4 && cmake --install build
```
</details>

## 2. Build a design

```sh
flow/ice65-build -t <top> -p <pins.pcf> -o build/<name> <sources.v ...>
```

| Option | |
| --- | --- |
| `-t top` | top module |
| `-p pcf` | pin constraints, `set_io <signal> <VQ100 pin number>` |
| `-o out` | output base name |
| `-f MHz` | clock target for nextpnr (default 72) |
| `-s seed` | placement seed (default 1); try a few when timing is tight |
| `-a` | do not stop when the (estimated) timing fails |
| `-y opts` | extra `synth_ice40` options |
| `-n opts` | extra nextpnr options |

Outputs: `<out>.bin` (the bitstream, 68088 bytes, starts with the sync word
like a vendor image), `<out>.asc` (text form), `<out>.json`, `<out>_syn.v`
(netlist after synthesis), `<out>.yosys.log`, `<out>.nextpnr.log`.
Tools are taken from `PATH`, or from `$YOSYS`, `$NEXTPNR`, `$ICEPACK`.

Example (DS203):

```sh
flow/ice65-build -t ds203_blinky -p examples/ds203_blinky/ds203_blinky.pcf \
    -o build/blinky examples/ds203_blinky/ds203_blinky.v
```

The flow is `synth_ice40` with its RAM step replaced
(`flow/synth_l04.ys.in`), then `nextpnr-ice40 --l04 --package vq100`, then
`icepack` (which takes the device from the `.device l04` line).

### Writing designs for the L04

- Primitives: the iCE40 ones without PLL, DSP, SPRAM, I2C/SPI hard IP:
  `SB_LUT4`, `SB_DFF*`, `SB_CARRY`, `SB_IO`, `SB_GB_IO`, `SB_GB`,
  `SB_RAM40_4K` in mode 0 (256 x 16). Yosys infers them as usual.
- Memories: yosys maps inferred memories to 256 x 16 blocks
  (`flow/brams_l04.txt`) and builds wider ones from several blocks. A memory
  deeper than 256 words is not split by depth automatically; use
  `lib/ram4096_l04.v` (4096 x N: one block per data bit, 4096 x 1 each) or
  write the address decoding yourself. 20 blocks in total.
- Clocks: a clock on pin 15 should enter through `SB_GB_IO`
  (`.PIN_TYPE(6'b000001)`): that is the confirmed pad-driven global network.
  Three more clocks get global networks from logic; nextpnr promotes them by
  fan-out. Anything else runs on local routing.
- Pins: only the 45 pins with a known pad (see
  [docs/device-notes.md](docs/device-notes.md#vq100-pins)); nextpnr refuses
  others.
- Bank 3 (pins 1–25): no pull-ups.
- Timing: the report uses an estimated model; compare builds with each other.
  A design that the vendor tool fits at 72 MHz may show ~50 MHz here.

## 3. Check a bitstream

```sh
flow/ice65-check -o build/blinky -t ds203_blinky \
    -p examples/ds203_blinky/ds203_blinky.pcf -c MCI,nRD
```

Unpacks the bitstream (`iceunpack -6`), counts bits not in the database,
turns it back into Verilog (`icebox_vlog`) and simulates it next to
`<out>_syn.v` with random inputs; `-c` names the clock inputs. Prints
`checked=... errors=...` and PASS / FAIL. This checks nextpnr and icepack
against the database, not the database against the silicon.

## 4. Look into vendor images

```sh
iceunpack -6 V261FPGA.BIN v261.asc         # -6: a 656 x 176 image is an L04, not an LM4K
icebox_stat v261.asc                       # resources
icebox_explain v261.asc | less             # every bit; '?' marks unknown ones
icebox_vlog -p examples/ds203_pins/ds203_l04_vq100.pcf v261.asc > v261.v
icepack v261.asc repacked.bin              # same bytes after the 4 byte header
```

Without `-6`, `iceunpack` reports the image as `lm4k` and the iCE40
databases misread the carry and RAM bits.

## 5. Tests

```sh
tests/run_all.sh
```

1. `lib/ram4096_l04.v` against a plain memory (simulation);
2. `examples/ds203_blinky`: build and `ice65-check`;
3. `tests/designs/mixed`: RAM with initial contents, carry chains, three
   clocks, tri-state bus: build and `ice65-check`;
4. the vendor image `V261FPGA.BIN` (downloaded from gabonator/LA104): no
   unknown bits, unpack + pack gives the same bytes.

The GitHub workflow in `.github/workflows/ci.yml` runs the same on every push.

## 6. Flash

Board specific. For the DS203 (image in the STM32 flash at 0x0802C000,
loaded by SYS at power up): [docs/ds203.md](docs/ds203.md).

## Troubleshooting

| Message | Cause |
| --- | --- |
| nextpnr: `unrecognised option '--l04'` | an unpatched nextpnr comes first in `PATH` |
| nextpnr: `package pin 'NN' ... not found` / unconstrained IO | pin without a known pad |
| nextpnr: `failed to route` / no global for a clock | more than 4 clocks with large fan-out; reduce clocks or build with `ICE65_UNVERIFIED=1` (untested buffers) |
| nextpnr: `LATCH_INPUT_VALUE is not supported` | IO latch location unknown |
| nextpnr: `Max frequency ... FAIL` | estimated timing; `-a` to continue, `-s` other seeds |
| yosys: `Unknown label` in `synth_ice40 -run` | yosys too old |
| icepack / iceunpack: device `lm4k` | `-6` missing, or an unpatched icestorm |
| ice65-check: `cells_sim.v not found` | set `CELLS_SIM` to `<yosys share>/ice40/cells_sim.v` |

## Publishing this repository

The files are a ready repository. To put them on GitHub:

```sh
cd ice65-opentools
git init -b main
git add .
git commit -m "iCE65L04 support for yosys / nextpnr / icestorm"
gh repo create ice65-opentools --public --source . --push
# or: create an empty repository on github.com, then
#     git remote add origin git@github.com:<user>/ice65-opentools.git
#     git push -u origin main
```

The first push starts the CI workflow (about 15 minutes; the tool build is
cached afterwards).

## Upstream

The patches are made for icestorm `00da9c3` and nextpnr `5e2718b` and keep
the iCE40 devices unchanged. They are not upstream; the data is not
complete enough for that yet ([docs/derivation.md](docs/derivation.md#helping)
lists what would help).

## Licence and credits

This repository: ISC (as icestorm and nextpnr, which the patches modify).
Project IceStorm and nextpnr: YosysHQ and contributors, ISC.
The vendor image used for the derivation is not included; the DS203 design
sources it was compared with are e-Design's FPGA 2.5 (MIT).
