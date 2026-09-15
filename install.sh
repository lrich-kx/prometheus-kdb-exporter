#!/bin/bash
# Install the prom module onto the KDB-X module search path so it loads with:  prom:use`prom
#
#   ./install.sh            install into the first entry of q's default module search path
#                           (asks q for .Q.m.SP; falls back to $QHOME/mod if q is not on PATH)
#   ./install.sh <dir>      install into <dir>/prom instead
#
# To run from a checkout without installing, set QPATH to the repository root instead.

set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)/prom"
if [ ! -f "$SRC_DIR/init.q" ]; then
    echo "ERROR: '$SRC_DIR/init.q' not found; run this script from the repository root"
    exit 1
fi

MOD_DIR="$1"

if [ -z "$MOD_DIR" ] && command -v q >/dev/null 2>&1; then
    # ask q where it looks for modules; ignore licence/startup noise and keep only an absolute path
    MOD_DIR="$(echo '-1 first .Q.m.SP; exit 0' | q -q 2>/dev/null | grep -m1 '^/' || true)"
fi

if [ -z "$MOD_DIR" ]; then
    if [ -z "$QHOME" ]; then
        echo "ERROR: could not determine the module search path (q not on PATH and QHOME not set)."
        echo "       Re-run as: ./install.sh <module search dir>"
        exit 1
    fi
    MOD_DIR="$QHOME/mod"
fi

DEST_DIR="$MOD_DIR/prom"
echo "Installing prom module to $DEST_DIR ..."
mkdir -p "$DEST_DIR"
cp "$SRC_DIR"/*.q "$DEST_DIR/"

echo "Install complete. Load with:  prom:use\`prom"
exit 0
