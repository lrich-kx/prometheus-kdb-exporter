#!/bin/bash

# Start the tick-x reference stack with prom instrumentation on all 8 nodes.
# Run from anywhere; -t (or $TICKX_ROOT) points at your kdbx-tick-reference-architecture
# clone. See examples/tick-x/README.md for the full walkthrough.
#
# Usage: ./examples/tick-x/startup.sh -t <tickxRoot> [-s secondaries] [-e envfile]
#   -t  Path to the kdbx-tick-reference-architecture clone (default: $TICKX_ROOT)
#   -s  Secondary threads per process (default: 0)
#   -e  Path to this demo's env overrides (default: examples/tick-x/env, alongside
#       this script) — sourced AFTER tick-x's own samples/sample_env, so both stay in
#       sync the same way tick-x's own -e flag works
#
# Every wrapper is launched with the exact same -p / -procName / etc. as tick-x's own
# startup.sh would use, so tick-x's own shutdown.sh / restart.sh work unmodified against
# this stack (see shutdown.sh here, which just delegates to them).

set -e

PROM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$PROM_ROOT/examples/tick-x/env"
s_flag=0

print_usage() {
  printf "Usage: ./examples/tick-x/startup.sh -t <tickxRoot> [-s secondaries] [-e envfile]\n"
}

while getopts 't:s:e:' flag; do
  case "${flag}" in
    t) TICKX_ROOT="${OPTARG}" ;;
    s) s_flag="${OPTARG}" ;;
    e) ENV_FILE="${OPTARG}" ;;
    *) print_usage; exit 1 ;;
  esac
done

if [ -z "$TICKX_ROOT" ]; then
  echo "TICKX_ROOT not set — pass -t <path-to-kdbx-tick-reference-architecture> or export TICKX_ROOT" >&2
  print_usage
  exit 1
fi
if [ ! -f "$TICKX_ROOT/samples/sample_env" ]; then
  echo "Not a kdbx-tick-reference-architecture checkout: $TICKX_ROOT/samples/sample_env not found" >&2
  exit 1
fi

export PROM_ROOT
cd "$TICKX_ROOT"

# Shared tick-x config first (ports, paths, intervals), then this demo's overrides.
. samples/sample_env
. "$ENV_FILE"

mkdir -p "$TPLOG_DIR" "$HDB_DIR" "$IDB_DIR" "$PROCESS_LOG_DIR"

echo -e "Starting instrumented Tick-X stack..."
echo -e "  tick-x root:      [$TICKX_ROOT]"
echo -e "  Secondaries:      [$s_flag]"
echo -e "  Flush interval:   [${FLUSH_INTV_MIN} min]"
echo -e "  Metrics QPATH:    [$QPATH]"
echo ""

W="$PROM_ROOT/examples/tick-x/wrappers"

###############
# Tickerplant #
###############
q "$W/tick_instrumented.q" \
  -p $TICK_PORT -s $s_flag \
  -schemaDir $SCHEMA_DIR -tplogDir $TPLOG_DIR \
  -procName TP \
  < /dev/null >> $PROCESS_LOG_DIR/startup.log 2>&1 &
echo -e "  Started TP\t\t[$TICK_PORT]"

#######
# IDB #
#######
# Start IDB before the main RDB so the first flush signal lands on a live IDB.
q "$W/idb_instrumented.q" \
  -p $IDB_PORT -s $s_flag \
  -hdbDir $HDB_DIR -idbDir $IDB_DIR \
  -procName IDB \
  < /dev/null >> $PROCESS_LOG_DIR/startup.log 2>&1 &
echo -e "  Started IDB\t\t[$IDB_PORT]"

##############################
# RDB (writedown role)       #
##############################
q "$W/rdb_instrumented.q" \
  -p $RDB_PORT -s $s_flag \
  -tplogDir $TPLOG_DIR -hdbDir $HDB_DIR -idbDir $IDB_DIR \
  -tpPort $TICK_PORT -hdbPort $HDB_PORT -idbPort $IDB_PORT \
  -flushIntvMin $FLUSH_INTV_MIN \
  -procName RDB \
  < /dev/null >> $PROCESS_LOG_DIR/startup.log 2>&1 &
echo -e "  Started RDB\t\t[$RDB_PORT]"

##############################
# CHAINED_RDB (query role)   #
##############################
q "$W/chainedrdb_instrumented.q" \
  -p $CHAINED_RDB_PORT -s $s_flag \
  -tplogDir $TPLOG_DIR -hdbDir $HDB_DIR -idbDir $IDB_DIR \
  -tpPort $TICK_PORT \
  -procName CHAINED_RDB \
  < /dev/null >> $PROCESS_LOG_DIR/startup.log 2>&1 &
echo -e "  Started CHAINED_RDB\t[$CHAINED_RDB_PORT]"

#######
# HDB #
#######
q "$W/hdb_instrumented.q" \
  -p $HDB_PORT -s $s_flag \
  -hdbDir $HDB_DIR \
  -procName HDB \
  < /dev/null >> $PROCESS_LOG_DIR/startup.log 2>&1 &
echo -e "  Started HDB\t\t[$HDB_PORT]"

###############
# Feedhandler #
###############
q "$W/fh_instrumented.q" \
  -p $FH_PORT -s $s_flag \
  -fhTimer $FH_TIMER \
  -tpPort $TICK_PORT \
  -procName FH \
  < /dev/null >> $PROCESS_LOG_DIR/startup.log 2>&1 &
echo -e "  Started FH\t\t[$FH_PORT]"

####################
# Real-time Engine #
####################
# -enrichFile is passed here (tick-x's own startup.sh exports RTE_ENRICH_FILE but never
# passes it), so the sample heat-index enrichment is actually live for this demo.
q "$W/rte_instrumented.q" \
  -p $RTE_PORT -s $s_flag \
  -tpPort $TICK_PORT \
  -enrichFile $RTE_ENRICH_FILE \
  -procName RTE \
  < /dev/null >> $PROCESS_LOG_DIR/startup.log 2>&1 &
echo -e "  Started RTE\t\t[$RTE_PORT]"

###########
# Gateway #
###########
q "$W/gw_instrumented.q" \
  -p $GW_PORT -s $s_flag \
  -rdbPort $CHAINED_RDB_PORT \
  -idbPort $IDB_PORT \
  -hdbPort $HDB_PORT \
  -analyticsDir $ANALYTIC_DIR \
  -procName GW \
  < /dev/null >> $PROCESS_LOG_DIR/startup.log 2>&1 &
echo -e "  Started GW\t\t[$GW_PORT]"

echo -e "\nStack started. Logs: $PROCESS_LOG_DIR/startup.log"
echo -e "Metrics: curl localhost:{$TICK_PORT,$RDB_PORT,$HDB_PORT,$GW_PORT,$FH_PORT,$IDB_PORT,$RTE_PORT,$CHAINED_RDB_PORT}/metrics"
