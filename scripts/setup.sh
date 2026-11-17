#!/usr/bin/env bash
# Builds icestorm (icepack, icebox) and nextpnr-ice40 with the iCE65 L04
# patches and installs them into $PREFIX.
#
#   scripts/setup.sh                 # into ./install
#   PREFIX=$HOME/ice65 scripts/setup.sh
#
# Variables:
#   PREFIX         install folder (default: <repo>/install)
#   WORK           source / build folder (default: <repo>/build-tools)
#   JOBS           parallel jobs (default: number of CPUs)
#   ICE40_DEVICES  chip databases built into nextpnr (default: "l04";
#                  "1k 8k l04" etc. to keep the iCE40 devices as well)
#   ICE65_UNVERIFIED=1  offer all eight global buffers of the L04 to the
#                  placer (default: only those confirmed in a vendor image)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREFIX=${PREFIX:-$ROOT/install}
WORK=${WORK:-$ROOT/build-tools}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
ICE40_DEVICES=${ICE40_DEVICES:-l04}

ICESTORM_URL=https://github.com/YosysHQ/icestorm.git
ICESTORM_COMMIT=00da9c3e6ceff056248e3451dd6fd3210d6ceec9
NEXTPNR_URL=https://github.com/YosysHQ/nextpnr.git
NEXTPNR_COMMIT=5e2718b6364e189e414c35b8eef3db4d5e3c0773

log() { printf '\n==> %s\n' "$*"; }

# fetch one commit (shallow) into $2
fetch() {
    local url=$1 dir=$2 commit=$3
    if [ ! -d "$dir/.git" ]; then
        git init -q "$dir"
        git -C "$dir" remote add origin "$url"
    fi
    if [ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$commit" ]; then
        git -C "$dir" fetch -q --depth 1 origin "$commit"
        git -C "$dir" checkout -q --force FETCH_HEAD
    fi
}

# apply a patch once
apply_patch() {
    local dir=$1 patch=$2
    if git -C "$dir" apply --reverse --check "$patch" 2>/dev/null; then
        echo "already applied: $(basename "$patch")"
    else
        git -C "$dir" apply "$patch"
        echo "applied: $(basename "$patch")"
    fi
}

for tool in git make cmake g++ python3; do
    command -v $tool >/dev/null || { echo "missing: $tool (see README, Requirements)"; exit 1; }
done
mkdir -p "$WORK" "$PREFIX"

log "icestorm $ICESTORM_COMMIT"
fetch $ICESTORM_URL "$WORK/icestorm" $ICESTORM_COMMIT
apply_patch "$WORK/icestorm" "$ROOT/patches/icestorm-ice65-l04.patch"
# only icepack and icebox are needed (iceprog would need libftdi)
make -C "$WORK/icestorm/icepack" -j"$JOBS" PREFIX="$PREFIX"
make -C "$WORK/icestorm/icebox" -j"$JOBS" PREFIX="$PREFIX"
make -C "$WORK/icestorm/icepack" install PREFIX="$PREFIX"
make -C "$WORK/icestorm/icebox" install PREFIX="$PREFIX"
# timing data for nextpnr (icetime would install it, it is not built here)
cp "$WORK/icestorm/icefuzz/"timings_*.txt "$PREFIX/share/icebox/"

log "nextpnr $NEXTPNR_COMMIT (ice40: $ICE40_DEVICES)"
fetch $NEXTPNR_URL "$WORK/nextpnr" $NEXTPNR_COMMIT
git -C "$WORK/nextpnr" submodule update -q --init --recursive --depth 1
apply_patch "$WORK/nextpnr" "$ROOT/patches/nextpnr-ice65-l04.patch"
cmake -S "$WORK/nextpnr" -B "$WORK/nextpnr/build" \
    -DARCH=ice40 -DICE40_DEVICES="$ICE40_DEVICES" \
    -DICESTORM_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DBUILD_PYTHON=OFF -DBUILD_GUI=OFF -DBUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build "$WORK/nextpnr/build" -j"$JOBS"
cmake --install "$WORK/nextpnr/build"

log "installed into $PREFIX"
# (nextpnr prints its help on stderr)
if "$PREFIX/bin/nextpnr-ice40" --help 2>&1 | grep -- "--l04" > /dev/null; then
    echo "nextpnr-ice40: --l04 available"
else
    echo "ERROR: nextpnr-ice40 has no --l04 option"; exit 1
fi
test -f "$PREFIX/share/icebox/chipdb-l04.txt" && echo "icebox: chipdb-l04.txt"
test -f "$PREFIX/share/icebox/timings_l04.txt" && echo "icebox: timings_l04.txt"
cat <<EOF

Add the tools to PATH:
    export PATH="$PREFIX/bin:\$PATH"
Yosys is not built here (any recent release, see README).
EOF
