# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [2.0.0] - unreleased

Rewrite of the exporter as a KDB-X module. See [docs/migration.md](docs/migration.md) for the
upgrade path. Users on kdb+ 3.x/4.x should remain on [1.0.1](https://github.com/KxSystems/prometheus-kdb-exporter/releases/tag/1.0.1).

### Breaking

- Requires KDB-X. The module framework (`use`, `export`, `.z.M`) is not available in kdb+ 4.x.
- `q/exporter.q` and `q/extract.q` are removed. The exporter is now the `prom/` module, loaded with
  `` prom:use`prom `` from the process being monitored. `install.sh` / `install.bat` copy it onto
  the module search path (`.Q.m.SP`).
- The `.prom.*` global namespace is gone. Functions are reached through the variable `use` is assigned to.
- `.prom.newmetric` / `.prom.addmetric` / `.prom.updval` / `.prom.init` / `.prom.extractall` /
  `.prom.overloadhandler` are replaced by `create`, `init`, `inc`, `incr`, `dec`, `decr`, `setv`, `obs`,
  `del`, `metrics`, `metricMeta`, `serve`, `enableInstHdlr`, `overRideInstHdlr`, `overLoadHdlr`.
- Labels are dictionaries keyed by the names declared in `create`, validated on every update. The
  labels argument is mandatory; pass `` ` `` for none.
- Built-in `.z.*` instrumentation is opt-in per handler via `enableInstHdlr`; nothing is wired at load
  except the `/metrics` HTTP endpoint. The `-noinit` flag is removed.
- `addmetric` return handles and `startval` no longer exist; instances are addressed by
  `(metric;labels)` and are created on first update or via `init`.
- Operations are validated by metric type (counters only increment, gauges only `inc`/`dec`/`setv`,
  histograms and summaries only `obs`; increments must be `> 0`). `create` rejects duplicate names.
- Histograms accumulate bucket counts and `_sum`/`_count` on each observation instead of storing raw
  samples and re-binning on scrape.
- Summaries retain a bounded window of observations (`cacheLength`, default 100000, or the
  `CACHELENGTH` env var) for quantile calculation.

### Added

- `create` accepts per-metric `buckets`, `quantiles`, `cacheLength`, and `init` (initial label set).
- `del` removes a metric and all its label instances.
- `metrics[]` and `metricMeta[]` return read-only copies of the current state.
- `overRideInstHdlr` replaces any of the `on_*` / `before_*` / `after_*` hooks after defaults are enabled.
- `METRICS_ENDPOINT` env var configures the scrape path (default `metrics`).
- `tests/t.q` assertion suite (`QPATH=$PWD q tests/t.q`).
- `docs/migration.md` upgrade guide and a Claude Code skill at `.claude/skills/prom-migrate/`.
- `CHANGELOG.md`.

### Changed

- `kdb_syms_total` and `kdb_syms_memory_bytes` are gauges (were counters).
- `examples/` refreshed for the module: `examples/exporter.q` defaults runner, updated
  `kdb_user_example.q`, newer Prometheus/Grafana images, dashboard panels for removed metrics dropped.
- `install.sh` / `install.bat` install a module directory instead of loose scripts and no longer probe
  for 32/64-bit shared-library paths.
- Release tarballs package `prom/` instead of `q/`.

### Removed

- `kdb_info` gauge.
- `kdb_sync_err_total`, `kdb_async_err_total`, `kdb_http_get_err_total`, `kdb_http_post_err_total`,
  `kdb_ws_err_total`, `kdb_ts_err_total`. The 1.x implementation incremented on every request and
  decremented on success, so the values were not error counts.
- `.z.*_orig` copies of wrapped handlers (only `.z.ph_orig` remains).

### Fixed

- Summary quantile label is `quantile=` (pre-release module builds emitted the non-standard `percentile=`).
- Histogram overflow bucket is `le="+Inf"` (was `+inf`, which Prometheus does not parse as infinity).
- `overRideInstHdlr` accepted only `on_*` and the `pg` hooks and omitted `on_poll`; every documented
  hook can now be overridden and the allow-list is derived from one definition.
- Stray `` `.m.prom.metrics `` printed to the console when the module loaded.
- `setv` stored an atom where the other operations store a one-element list, so a gauge set before any
  other metric collapsed the `val` column and the next `create` (including `enableInstHdlr`'s default
  metrics) failed with `'type`.
- Histogram bucket counts initialised as ints and became longs after the first observation.
- `enableInstHdlr` echoed the handler names it set instead of returning null.
- `serve[]` output ends with a newline; `promtool check metrics` rejected the previous output with
  "unexpected end of input stream".
- Typos in user-facing error strings (`arguemnt`, `guage`, `histrogram`, `histograph`, `not allow`,
  `overwride`, `non-existant`).

## [1.0.1]

See the [1.0.1 release](https://github.com/KxSystems/prometheus-kdb-exporter/releases/tag/1.0.1).

## [1.0.0]

See the [1.0.0 release](https://github.com/KxSystems/prometheus-kdb-exporter/releases/tag/1.0.0).

[2.0.0]: https://github.com/KxSystems/prometheus-kdb-exporter/compare/1.0.1...master
[1.0.1]: https://github.com/KxSystems/prometheus-kdb-exporter/compare/1.0.0...1.0.1
[1.0.0]: https://github.com/KxSystems/prometheus-kdb-exporter/releases/tag/1.0.0
