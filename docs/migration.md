# Migrating from prometheus-kdb-exporter 1.x to 2.x

Version 2 is a rewrite of the exporter as a [KDB-X module](https://code.kx.com/kdb-x/modules/module-framework/quickstart.html).
It is a breaking change. This page lists what changed and how to move existing code and dashboards.

Claude Code users can run the bundled [`prom-migrate` skill](../.claude/skills/prom-migrate/SKILL.md),
an automated helper that applies the steps below to a codebase.

## Who should migrate

- **You run KDB-X.** Migrate. 2.x is the only line that will receive fixes and features.
- **You run kdb+ 3.x/4.x.** Stay on 1.x. The module framework (`use`, `export`, `.z.M`) does not exist there.
  The last 1.x release is [tag `1.0.1`](https://github.com/KxSystems/prometheus-kdb-exporter/tree/1.0.1);
  its install scripts and docs are unchanged at that tag.

## What changed at a glance

| Area | 1.x | 2.x |
|---|---|---|
| Packaging | Two scripts (`q/exporter.q`, `q/extract.q`) copied into `$QHOME`, run as a standalone process or `\l`-ed | One module directory `prom/` on `QPATH`, loaded with `` prom:use`prom `` from your own process |
| Namespace | `.prom.*` globals | Private module namespace; only exported functions are visible, via the variable you assign `use` to |
| Metric definition | `newmetric` + one `addmetric` per label set, keeping the returned handle | One `create` call with a dictionary; instances are addressed by `(metric;labels)` |
| Updates | `updval[handle;operator;value]` | `inc` / `incr` / `dec` / `decr` / `setv` / `obs`, validated against the metric type |
| Labels | Positional string list | Dictionary validated against the definition |
| Histograms | Raw samples kept, re-binned on every scrape | Bucket counts and `_sum`/`_count` maintained on each `obs` |
| Summaries | Unbounded sample list | Bounded window (`cacheLength`, default 100000) |
| Built-in `kdb_*` metrics | Wired for every `.z.*` handler at load | Opt-in per handler with `enableInstHdlr` |
| Endpoint | Hard-coded `/metrics` | `METRICS_ENDPOINT` env var |

## Install and load

1x:

```bash
./install.sh            # copies q/*.q into $QHOME
q q/exporter.q -p 8080  # or \l exporter.q from your process
```

2x:

```bash
./install.sh            # copies prom/ onto the module search path (asks q for .Q.m.SP)
# or, without installing:
export QPATH=/path/to/prometheus-kdb-exporter
```

```q
// in your process, AFTER all of your own .z.* handlers are defined
prom:use`prom
prom.enableInstHdlr`po`pc`wo`wc`pg`ps`ph`pp`ws`ts   / optional: built-in kdb metrics
```

Loading the module replaces `.z.ph` immediately (chaining to any existing handler) so the endpoint is
live; nothing else is instrumented until you call `enableInstHdlr`. The load-order rule is the same as
1.x: defining a `.z.*` handler after the module has wrapped it silently drops the instrumentation.

## API mapping

<!-- KEEP IN SYNC: this table is duplicated in .claude/skills/prom-migrate/references/api-mapping.md. Edit both. -->

| v1 (`.prom` globals) | v2 (`` prom:use`prom ``) | Notes |
|---|---|---|
| `q q/exporter.q -p 8080` / `\l exporter.q` / `\l extract.q` | `` prom:use`prom `` inside your own process | No standalone script. Module must be on the module search path (`.Q.m.SP`, resolved relative to the KDB-X runtime) or on `QPATH`. See `examples/exporter.q` for a default-metrics runner. |
| `-noinit` command-line flag | not needed | v2 never wires `.z.*` handlers at load. |
| `.prom.newmetric[name;type;labelnames;help]` | `prom.create ([name:..;mtype:..;labels:..;help:..;buckets/quantiles/cacheLength:..;init:..])` | One dictionary argument. Type-specific parameters (`buckets`, `quantiles`, `cacheLength`) live on the definition, not per instance. |
| `.prom.addmetric[metric;labelvals;params;startval]` | `prom.init[metric;labelDict]`, or just update the instance | Returns nothing. Instances are addressed by `(metric;labels)`, not by a returned handle. `params` moves to `create`; `startval` is gone (instances start at 0 / empty). Instances auto-create on first update. |
| `.prom.updval[name;+;n]` | `prom.inc[m;lbl]` / `prom.incr[m;n;lbl]` | counter or gauge, `n>0`. |
| `.prom.updval[name;-;n]` | `prom.dec[m;lbl]` / `prom.decr[m;n;lbl]` | gauge only. |
| `.prom.updval[name;:;v]` | `prom.setv[m;v;lbl]` | gauge only. |
| `.prom.updval[name;,;v]` (append to summary/histogram sample list) | `prom.obs[m;v;lbl]` | Scalar observations only; call once per value. |
| — | `prom.del[metric]` | New: drop a metric and all its label instances. |
| `.prom.metrics` / `.prom.metricvals` (tables, directly editable) | `prom.metrics[]` / `prom.metricMeta[]` | Read-only copies. |
| `.prom.extractall[]` | `prom.serve[]` | Returns the exposition text. |
| `.prom.init[]` | `` prom.enableInstHdlr`po`pc`wo`wc`pg`ps`ph`pp`ws`ts `` | Opt-in per handler. The first call also creates the default `kdb_*` / `memory_*` metrics. One-way; repeating a handler throws. |
| assign `.prom.on_poll`, `.prom.on_po` … `.prom.after_ts` directly | `prom.overRideInstHdlr[`on_po;func]` | Same hook names and signatures as v1. |
| `.prom.overloadhandler[nm;ol;def]` | `prom.overLoadHdlr[`.z.ps;{[f;msg] …; f msg}]` | Default fallback handler is built in; no `def` argument. |
| hard-coded `"metrics"` path in `ph` | `METRICS_ENDPOINT` env var | Default `metrics`. Read at load time. |
| unbounded summary sample list | `CACHELENGTH` env var, or `cacheLength` per metric | Default 100000. Quantiles are computed over the retained window. |
| `kdb_info` gauge (version / os / licence labels) | **removed** | Remove dashboard panels and alerts that use it. |
| `kdb_sync_err_total`, `kdb_async_err_total`, `kdb_http_get_err_total`, `kdb_http_post_err_total`, `kdb_ws_err_total`, `kdb_ts_err_total` | **removed** | The v1 implementation incremented on every request and decremented on success, so the value was not an error count. |
| `.z.pg_orig`, `.z.ps_orig`, … saved copies | only `.z.ph_orig` | Wrapped handlers are closed over inside the module, not stored under `_orig` names. |

## Before and after

A custom gauge with one label, plus the built-in metrics.

```q
// 1.x
\l extract.q
.prom.newmetric[`number_tables;`gauge;`region;"number of tables"]
numtab:.prom.addmetric[`number_tables;`amer;();0f]
.prom.updval[numtab;:;count tables[]]
.prom.init[]
```

```q
// 2.x
prom:use`prom                                        / after your own .z.* definitions
prom.enableInstHdlr`po`pc`pg`ps`ph;                  / optional: built-in kdb metrics
prom.create ([name:`number_tables;mtype:`gauge;labels:`region;help:"number of tables"])
prom.setv[`number_tables;"f"$count tables[];([region:"amer"])]
```

The v1 `addmetric` handle disappears. Every update names the metric and the label dictionary directly,
and the instance is created on first use.

## Behavioural changes

- **No `.prom` namespace.** Only the exported functions exist, under whatever variable you assigned `use` to.
- **Nothing is instrumented at load.** `use` takes over `.z.ph` for the endpoint only. Counters and
  timings start when you call `enableInstHdlr` for each handler you want.
- **Labels are dictionaries** keyed by the names given in `create`, validated on every call. Missing or
  extra keys throw. Values are normalised to definition order in the output. Unlabelled metrics must
  pass `` ` `` explicitly; the labels argument is never optional.
- **Operations are validated by type.** Counters accept only `inc`/`incr`; gauges accept
  `inc`/`incr`/`dec`/`decr`/`setv`; histograms and summaries accept only `obs`. `incr`/`decr` reject
  values `<= 0`. v1 applied any operator to anything.
- **`create` rejects duplicate names.** v1 `newmetric` silently upserted.
- **Histograms bucket on observe.** Cumulative `le` buckets and `_sum`/`_count` are maintained per
  `obs`; nothing is recomputed at scrape time.
- **Summaries keep a bounded window** of the last `cacheLength` observations for quantiles. `_sum` and
  `_count` stay as running totals.
- **Created-but-never-updated metrics are not served** unless you pass `init` to `create` or call
  `prom.init`. v1 served every instance from `startval`.
- **Default metric types.** `kdb_syms_total` and `kdb_syms_memory_bytes` are gauges (v1: counters).
- **Endpoint path** comes from `METRICS_ENDPOINT` at load time.

## Dashboards and PromQL

Metric names and label sets for memory (`memory_*`), handles (`kdb_handles_total`,
`kdb_ipc_*`, `kdb_ws_*`), request counters (`kdb_sync_total`, `kdb_async_total`, `kdb_http_*_total`,
`kdb_ws_total`, `kdb_ts_total`), and the `*_histogram_seconds` / `*_summary_seconds` series are unchanged.
Existing queries keep working, with these exceptions:

- Remove panels and alerts on `kdb_info`.
- Remove panels and alerts on the six `kdb_*_err_total` series.
- Summary quantile selectors use `quantile="…"` as in 1.x. If you scraped a 2.0 pre-release build you may
  have `percentile="…"` selectors; change them back.
- Histogram overflow bucket is `le="+Inf"` as in 1.x.

The bundled Grafana dashboard in `examples/DockerCompose/grafana-config/` has been updated accordingly.

## Gotchas

- **Load order.** `use` and `enableInstHdlr` must run after all of your own `.z.*` definitions.
  Redefining `.z.pg` afterwards drops the wrapper without an error.
- **`enableInstHdlr` is one-way.** There is no disable, and enabling the same handler twice throws.
- **Stacked `.z.ph`.** The module wraps `.z.ph` at load, and `enableInstHdlr`ph` stacks a second
  wrapper for timing. Calling `overLoadHdlr` on `.z.ph` yourself adds a third; keep the order in mind.
- **First scrape lag.** With `ph` enabled, the HTTP GET that serves `/metrics` is itself timed after the
  response is built, so `kdb_http_get_total` runs one ahead of `kdb_http_get_histogram_seconds_count`.
- **Empty summaries** serve their quantiles as `0`, not as absent series.
- **Gauge value types.** `setv` stores whatever type you pass. Cast to float (`"f"$`) for consistent output.
- **`metrics[]` and `metricMeta[]` are copies.** Editing them does nothing; use the update APIs.
