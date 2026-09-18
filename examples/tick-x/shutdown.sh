#!/bin/bash

# Stop the instrumented tick-x stack. Every wrapper is launched with the same -procName
# as tick-x's own startup.sh would use, so tick-x's own shutdown.sh finds and kills them
# unmodified — this just delegates to it.
#
# Usage: ./examples/tick-x/shutdown.sh -t <tickxRoot>

while getopts 't:' flag; do
  case "${flag}" in
    t) TICKX_ROOT="${OPTARG}" ;;
    *) printf "Usage: ./examples/tick-x/shutdown.sh -t <tickxRoot>\n"; exit 1 ;;
  esac
done

if [ -z "$TICKX_ROOT" ]; then
  echo "TICKX_ROOT not set — pass -t <path-to-kdbx-tick-reference-architecture> or export TICKX_ROOT" >&2
  exit 1
fi

cd "$TICKX_ROOT" && ./tick-x/scripts/shutdown.sh
