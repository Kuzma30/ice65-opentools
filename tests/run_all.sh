#!/usr/bin/env bash
# Tests of the toolchain (run after scripts/setup.sh, tools in PATH):
#   1. lib/ram4096_l04.v against a plain memory (simulation)
#   2. examples/ds203_blinky: build and check the bitstream (ice65-check)
#   3. tests/designs/mixed: RAM with init, carry, 3 clocks, tri-state bus
#   4. the vendor image V261FPGA.BIN of the DS203 (downloaded from the
#      gabonator/LA104 repository; skipped when it can not be fetched):
#      no unknown bits, unpack + pack gives the same file
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build-tests}
mkdir -p "$OUT"
FLOW=$ROOT/flow
FAIL=0
result() { if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2"; FAIL=1; fi; }

# cells_sim.v of yosys
if [ -z "${CELLS_SIM:-}" ]; then
    if command -v yosys-config >/dev/null; then
        CELLS_SIM=$(yosys-config --datdir)/ice40/cells_sim.v
    else
        CELLS_SIM=$(python3 -c "import yowasp_yosys, os; print(os.path.join(os.path.dirname(yowasp_yosys.__file__), 'share', 'ice40', 'cells_sim.v'))")
    fi
fi
export CELLS_SIM

echo "== 1. RAM4096_L04"
iverilog -g2012 -DNO_ICE40_DEFAULT_ASSIGNMENTS -s ram_tb -o "$OUT/ram.vvp" \
    "$ROOT/tests/ram4096_tb.v" "$ROOT/lib/ram4096_l04.v" "$CELLS_SIM" 2>&1 | grep -v "sorry\|warning" || true
R=$(vvp -n "$OUT/ram.vvp" | grep "ram checks")
echo "$R"
echo "$R" | grep -q "errors=0"; result $? "RAM4096_L04"

echo "== 2. examples/ds203_blinky"
set +e
"$FLOW/ice65-build" -t ds203_blinky -p "$ROOT/examples/ds203_blinky/ds203_blinky.pcf" \
    -o "$OUT/blinky/ds203_blinky" "$ROOT/examples/ds203_blinky/ds203_blinky.v" &&
"$FLOW/ice65-check" -o "$OUT/blinky/ds203_blinky" -t ds203_blinky \
    -p "$ROOT/examples/ds203_blinky/ds203_blinky.pcf" -c MCI,nRD -n 20000
result $? "ds203_blinky"

echo "== 3. tests/designs/mixed"
"$FLOW/ice65-build" -a -t mixed -p "$ROOT/tests/designs/mixed.pcf" \
    -o "$OUT/mixed/mixed" "$ROOT/tests/designs/mixed.v" &&
"$FLOW/ice65-check" -o "$OUT/mixed/mixed" -t mixed \
    -p "$ROOT/tests/designs/mixed.pcf" -c MCI,SCK,nRD -n 30000
result $? "mixed"

echo "== 4. vendor image V261FPGA.BIN"
URL=https://raw.githubusercontent.com/gabonator/LA104/master/tools/fpga/ds203_8mb_hwV272-V261FPGA/V261FPGA.BIN
SHA=72372ad74516074845a164967a2306429df7c7839bb01f034e2f46423e4e15a8
V=$OUT/V261FPGA.BIN
if [ ! -f "$V" ]; then
    curl -sSfL -o "$V" "$URL" 2>/dev/null || wget -q -O "$V" "$URL" 2>/dev/null || rm -f "$V"
fi
if [ -f "$V" ] && [ "$(sha256sum "$V" | cut -d' ' -f1)" = "$SHA" ]; then
    iceunpack -6 "$V" "$OUT/v261.asc" &&
    U=$(icebox_explain "$OUT/v261.asc" | grep -c '?') ; echo "bits not in the database: $U"
    icepack "$OUT/v261.asc" "$OUT/v261.pack.bin" && tail -c +5 "$OUT/v261.pack.bin" | cmp -s - "$V"
    SAME=$?
    [ "$U" = 0 ] && [ $SAME = 0 ]; result $? "V261FPGA.BIN: unpack, explain, pack identical"
else
    echo "SKIP V261FPGA.BIN (could not download $URL)"
fi
set -e
exit $FAIL
