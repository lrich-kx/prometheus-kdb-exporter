# tick-x + prom: a worked multi-process example

Instruments every node of the
[kdbx-tick-reference-architecture](https://github.com/KxSystems/kdbx-tick-reference-architecture)
`tick-x` stack with the `prom` module — default metrics everywhere, custom operational and
domain metrics on the gateway, RDB, IDB, HDB and RTE — plus a Grafana dashboard and a
randomized load generator. Where `examples/exporter.q` shows the module against one
process, this shows it against eight cooperating ones.

**Nothing in the tick-x repo is modified.** Every node is started from a thin wrapper here
that loads the real tick-x source unchanged, then adds instrumentation on top by wrapping
(never replacing) the functions and `.z.*` handlers it cares about.

## Layout

```
examples/tick-x/
├── env                  demo-tuning overrides, sourced after tick-x's own samples/sample_env
├── startup.sh           launches all 8 instrumented nodes
├── shutdown.sh          delegates to tick-x's own shutdown.sh
├── common.q             shared prom helpers: .instr.addGauge / .instr.sample / .instr.enable
├── wrappers/             one file per node — see "How a wrapper works" below
│   ├── tick_instrumented.q
│   ├── fh_instrumented.q
│   ├── rdb_instrumented.q
│   ├── chainedrdb_instrumented.q
│   ├── idb_instrumented.q
│   ├── hdb_instrumented.q
│   ├── rte_instrumented.q
│   └── gw_instrumented.q
├── client/loadgen.q     randomized query load against the gateway, with fault injection
├── verify.q             standalone prom API smoke test (no tick-x node needed)
└── dashboard/
    ├── docker-compose.yml
    ├── prometheus/prometheus.yml   (8 scrape targets, one per node, labeled `proc`)
    └── grafana/provisioning/...   (datasource + the "Tick-X (Instrumented)" dashboard)
```

## Prerequisites

- A KDB-X `q` with a licence, and this repo's `prom` module resolvable via `use\`prom`.
- A local clone of
  [kdbx-tick-reference-architecture](https://github.com/KxSystems/kdbx-tick-reference-architecture)
  (referred to below as `$TICKX_ROOT`).
- `docker` + `docker compose`, for the dashboard.

## Run it

```bash
# 1. start the 8 instrumented nodes
./examples/tick-x/startup.sh -t $TICKX_ROOT

# 2. drive some load through the gateway
q examples/tick-x/client/loadgen.q -gwPort 5013 -rate 30

# 3. bring up Prometheus + Grafana
docker compose -f examples/tick-x/dashboard/docker-compose.yml up -d
# Prometheus: http://localhost:9090  (Status > Targets should show 8 "tickx" targets up)
# Grafana:    http://localhost:3000  (admin / pass) — "Tick-X (Instrumented)" dashboard

# 4. tear down
./examples/tick-x/shutdown.sh -t $TICKX_ROOT
docker compose -f examples/tick-x/dashboard/docker-compose.yml down
```

Every wrapper is launched with the exact same `-p`/`-procName`/etc. tick-x's own
`startup.sh` would use, so tick-x's own `restart.sh <procName>` and `shutdown.sh` work
against this stack unmodified — `shutdown.sh` here just delegates to the latter.

`env` speeds the demo up relative to tick-x's own defaults: `FH_TIMER=1000` (vs `60000`,
so the feed publishes roughly once a second instead of once a minute) and
`FLUSH_INTV_MIN=1` (vs `5`, so an RDB→IDB writedown is visible within the first couple of
minutes). It also passes `-enrichFile $RTE_ENRICH_FILE` to the RTE — tick-x's own
`startup.sh` exports that variable but never passes it, so the sample heat-index
enrichment is idle out of the box; here it runs, which is what makes the RTE metrics (and
the `weatherHeatIndex` table) mean anything.

## How a wrapper works

Every file in `wrappers/` reads top-to-bottom in four sections — see any of them for the
full pattern, e.g. `wrappers/gw_instrumented.q`:

```q
// 1. the real node, unmodified
system"l tick-x/src/gw.q";

// 2. prom + shared helpers
system"l ",getenv[`INSTR_DIR],"/common.q";

// 3. this node's custom metrics — prom.create, then wrap this node's own functions by
//    redefinition (f_orig:f; f:{... f_orig[x] ...}), the same chaining discipline prom
//    itself uses for .z.* handlers.
...

// 4. enable default instrumentation — LAST, per the module's documented load-order rule
.instr.enable[];
```

Order is load-bearing: the real node loads first (so prom wraps *its* handlers, not the
other way round), and `.instr.enable[]` — which installs a scrape-time `on_poll` sampler
and calls `prom.enableInstHdlr` — runs last. `common.q` provides `.instr.addGauge` /
`.instr.sample` (register a niladic function to sample on every `/metrics` poll, rather
than on a slow timer) and `.instr.enable` (see its own comments for why an `on_poll`
override must re-emit the default memory gauges explicitly).

The one node worth calling out: `gw_instrumented.q` loads `tick-x/src/gw.q` (which sets
up `kx.rest` with `autoBind`, owning `.z.ph`) *before* loading `common.q` (which installs
prom's own `.z.ph`). prom's `.z.ph_orig` correctly captures the rest router underneath it,
so `/metrics` and every REST analytic endpoint (e.g. `/energy/meta`) keep working side by
side — verified live before this was trusted to work by inspection alone.

## Metrics

Default instrumentation (all 31 metrics from `docs/event-handlers.md`) is enabled on
every one of the 8 nodes. On top of that:

| Node | Custom metrics |
| --- | --- |
| TP | `tickx_tp_pub_rows_total{table}`, `tickx_tp_subscribers`, `tickx_tp_log_bytes` |
| FH | `tickx_fh_rows_published_total{table}`, `tickx_fh_publish_seconds` |
| RDB | `tickx_rdb_rows{table}`, `tickx_rdb_pending_rows`, `tickx_rdb_flushes_total`, `tickx_rdb_flushed_rows_total{table}`, `tickx_rdb_flush_seconds`, `tickx_rdb_watermark_lag_seconds`, `tickx_rdb_tp_connected`, `tickx_energy_consumption_kwh{sym}`, `tickx_weather_temp_celsius{sym}` |
| CHAINED_RDB | `tickx_crdb_rows{table}`, `tickx_crdb_shed_rows_total`, `tickx_crdb_async_bytes_total` |
| IDB | `tickx_idb_partitions`, `tickx_idb_rows{table}`, `tickx_idb_reloads_total`, `tickx_idb_reload_seconds` |
| HDB | `tickx_hdb_dates`, `tickx_hdb_reloads_total`, `tickx_hdb_reload_seconds` |
| RTE | `tickx_rte_rows_in_total{table}`, `tickx_rte_pub_rows_total{table}`, `tickx_rte_enrich_seconds{analytic}`, `tickx_rte_enrich_errors_total{analytic}` |
| GW | `tickx_gw_queries_total{tier,status}`, `tickx_gw_query_seconds{tier}` (histogram), `tickx_gw_query_latency_seconds{tier}` (summary), `tickx_gw_result_rows{tier}`, `tickx_gw_tier_up{proc}`, `tickx_gw_sync_by_fn_seconds{fn}` |

Between the defaults and this set, every `prom` metric type appears with every creation
option at least once (labelled/unlabelled counters and gauges, `incr`/`decr` on a gauge
that never calls `setv`, a histogram with custom `buckets`, a summary with custom
`quantiles` and `cacheLength`), and every exported function is exercised somewhere in this
example — `del`/`metrics`/`metricMeta` in `verify.q`, kept out of the live stack so a
demo dashboard never has a metric definition disappear out from under it.

## The load generator

`client/loadgen.q` connects to the gateway and fires a weighted mix every tick:

- **~85% valid** — a random tier (`rdb`/`idb`/`hdb`/`all`), table, sym filter and time
  window, mixing all three query forms the gateway accepts (string, parse-tree,
  function+args). `all` always uses the string form — its query type must not be a
  general list, or the gateway's own per-tier split misreads it as a 3-per-tier list.
- **~10% heavy** — a whole-day time window, to populate the upper latency buckets.
- **~5% faulty** — an unknown table, column or tier, each returned by the gateway as an
  `` `error`msg! `` dict rather than thrown, so `tickx_gw_queries_total{status="error"}`
  and the dashboard's error panels have something real to show.

```bash
q examples/tick-x/client/loadgen.q -gwPort 5013 -rate 30
```

## The dashboard

Eight rows, matching the sections above: stack overview, gateway, feed & tickerplant,
intraday writedown (RDB → IDB), HDB, RTE, domain (energy & weather), and per-process
resources. Every panel that breaks a series out by tier (`rdb`/`idb`/`hdb`/`all`) or
outcome (`ok`/`error`) uses a fixed color per value, consistent across every panel, rather
than whatever a panel-local palette happens to cycle to.

`prometheus.yml` scrapes all 8 node ports and labels each target `proc`, so a single
dashboard query can break results out per node (`sum by (proc) (...)`) without touching
the metric names themselves — the 31 default metrics keep their documented names and
labels on every node, per this repo's own contract.

## Verifying it end to end

```bash
# 1. prom's own unit suite is unaffected (nothing here touches the module)
QPATH=$PWD q tests/t.q -q </dev/null

# 2. this example's own API-coverage smoke test (no tick-x node needed)
QPATH=$PWD:$HOME/.kx/mod q examples/tick-x/verify.q -q

# 3. bring the stack up and confirm all 8 endpoints
./examples/tick-x/startup.sh -t $TICKX_ROOT
for p in 5010 5011 5012 5013 5014 5015 5016 5017; do
  curl -sf localhost:$p/metrics >/dev/null && echo "$p ok"
done

# 4. exposition format, on the two busiest nodes
curl -s localhost:5013/metrics | docker run --rm -i --entrypoint promtool \
  prom/prometheus:v3.5.0 check metrics
# exit 3 = lint warnings on the inherited kdb_*_histogram_seconds / kdb_*_summary_seconds /
#          kdb_handles_total names only (see this repo's CLAUDE.md, "Module boundaries")
# exit 1 = a real parse error
```

`QPATH` **replaces** the KDB-X module search path rather than extending it — it must
include `$HOME/.kx/mod` (or wherever `kx.log`/`kx.rest` are installed) alongside this
repo, or every tick-x node's own `use` calls fail. `startup.sh`/`env` set this for you;
it only matters if you're running a wrapper by hand.
