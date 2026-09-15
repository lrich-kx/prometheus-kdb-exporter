<!-- KEEP IN SYNC: this table is duplicated in docs/migration.md (GitHub renders no includes). Edit both. -->

# prometheus-kdb-exporter: v1.x → v2.x API mapping

v1 exposed `.prom.*` globals from `q/exporter.q` and `q/extract.q`. v2 is a KDB-X module loaded with
`` prom:use`prom `` and reached through that variable.

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

## Label conventions

| v1 | v2 |
|---|---|
| `labelnames` passed to `newmetric` as symbol or symbol list; `labelvals` passed to `addmetric` as strings in the same order | `labels` in `create` is a symbol list of label keys. Every update takes a dictionary keyed by those names, e.g. `([method:"GET";handler:"/db"])`. Order does not matter; missing or extra keys throw. |
| No labels: pass `()` | No labels: pass `` ` `` (null symbol). The labels argument is mandatory on every update API. |

## Metric type changes in the default set

| Metric | v1 type | v2 type |
|---|---|---|
| `kdb_syms_total` | counter | gauge |
| `kdb_syms_memory_bytes` | counter | gauge |
| summary quantile label | `quantile="0.5"` | `quantile="0.5"` (v2.0.0; pre-release builds emitted `percentile=`) |
| histogram overflow bucket | `le="+Inf"` | `le="+Inf"` (v2.0.0; pre-release builds emitted `+inf`) |
