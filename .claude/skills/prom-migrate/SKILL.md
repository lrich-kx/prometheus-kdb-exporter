---
name: prom-migrate
description: >
  Migrate q code, dashboards and alerts from prometheus-kdb-exporter 1.x (the `.prom.*` globals in
  `q/exporter.q` / `q/extract.q`) to the 2.x KDB-X `prom` module. Use when a codebase calls
  `.prom.newmetric`, `.prom.addmetric`, `.prom.updval`, `.prom.init`, loads `exporter.q` or `extract.q`,
  or assigns `.prom.on_*` / `.prom.before_*` / `.prom.after_*` hooks; when a user asks to "upgrade the
  Prometheus exporter", "move to the prom module", or reports `.prom` undefined after upgrading; or when
  Grafana dashboards / Prometheus alert rules query `kdb_info` or `kdb_*_err_total`. Not for authoring new
  2.x instrumentation from scratch — use docs/reference.md for that.
---

# Migrating prometheus-kdb-exporter 1.x → 2.x

The full v1→v2 table is in [references/api-mapping.md](references/api-mapping.md). Read it before
rewriting anything. The human-facing guide is [docs/migration.md](../../../docs/migration.md).

## Procedure

Work through the steps in order. Do not skip step 1.

### 1. Confirm the target runtime

2.x needs KDB-X. Check the binary the code will run under:

```q
q)`use in key `.q     / 1b on KDB-X
q).z.K                / KDB-X reports 5+
```

If this is kdb+ 3.x/4.x, stop. Tell the user to stay on tag `1.0.1`
(https://github.com/KxSystems/prometheus-kdb-exporter/tree/1.0.1) and do not rewrite anything.

### 2. Inventory the 1.x surface

Grep the codebase, install scripts, and any dashboard/alert JSON or YAML:

```bash
grep -rn '\.prom\.' --include='*.q' --include='*.k' .
grep -rn 'exporter\.q\|extract\.q\|-noinit' .
grep -rn 'metricvals\|\.prom\.metrics' --include='*.q' .          # direct table pokes
grep -rn 'kdb_info\|_err_total\|percentile=' --include='*.json' --include='*.yml' --include='*.yaml' .
```

List every hit before editing so nothing is left half-migrated.

### 3. Rewrite loads

- `\l extract.q`, `\l exporter.q`, `system"l exporter.q"` → `` prom:use`prom ``.
- Standalone `q q/exporter.q -p N` processes → either `use` the module inside the process being
  monitored, or point the user at `examples/exporter.q` for a defaults-only runner.
- Drop `-noinit`.
- Place the `use` line **after** every `.z.*` handler the process defines. Move it if necessary.
- Add the install step: `./install.sh` (copies `prom/` onto the module search path) or `export QPATH=<repo>`.

### 4. Rewrite metric definitions

Each `newmetric` plus its `addmetric` calls becomes one `prom.create` dictionary:

- `newmetric[name;type;labelnames;help]` → `name`, `mtype`, `labels` (symbol list, omit if none), `help`.
- `addmetric` `params` → `buckets` (histogram) or `quantiles` (summary). Omit for counter/gauge.
- `addmetric` `startval` → drop it. If the metric must appear before its first update, add
  `init:`` ` `` (no labels) or `init:([k:"v";…])` (one label set), or call `prom.init` per label set.
- Delete the variable that held the `addmetric` return value; every update names the metric directly.

### 5. Rewrite updates

Map `updval[handle;op;v]` by operator and metric type, per the mapping table:

| op | counter | gauge | histogram / summary |
|---|---|---|---|
| `+` with 1 | `prom.inc[m;lbl]` | `prom.inc[m;lbl]` | — |
| `+` with n | `prom.incr[m;n;lbl]` | `prom.incr[m;n;lbl]` | — |
| `-` | not allowed | `prom.dec` / `prom.decr` | — |
| `:` | not allowed | `prom.setv[m;v;lbl]` | — |
| `,` | — | — | `prom.obs[m;v;lbl]` one value per call |

Labels: v1 positional strings → a dictionary keyed by the `labels` names from `create`. No labels →
pass `` ` ``. The label argument is mandatory everywhere. If v1 appended a list with `,`, loop `obs`.

### 6. Rewrite hooks and init

- `.prom.on_poll: …`, `.prom.on_po: …`, `.prom.before_pg: …`, `.prom.after_ts: …` etc. →
  `prom.overRideInstHdlr[`on_po;func]`. Signatures are unchanged.
- `.prom.overloadhandler[nm;ol;def]` → `prom.overLoadHdlr[nm;ol]`.
- `.prom.init[]` → `` prom.enableInstHdlr`po`pc`wo`wc`pg`ps`ph`pp`ws`ts `` listing only the handlers the
  user wants instrumented. Call it once; it is one-way.
- Direct reads/writes of `.prom.metricvals` → `prom.metrics[]` (read-only) plus update APIs.

### 7. Dashboards and alert rules

- Delete panels/rules on `kdb_info` and the six `kdb_*_err_total` series.
- Change any `percentile="…"` selector to `quantile="…"`; any `le="+inf"` to `le="+Inf"`.
- Everything else (`memory_*`, `kdb_*_total`, `*_histogram_seconds`, `*_summary_seconds`) is unchanged.

### 8. Verify

```bash
QPATH=<repo> q -p 8080 <migrated-script>.q
curl -s localhost:8080/metrics | docker run --rm -i --entrypoint promtool prom/prometheus check metrics
QPATH=<repo> q tests/t.q -q </dev/null     # from the exporter repo; silent = pass
```

In the q session: `prom.serve[]` returns text, `prom.metrics[]` shows one row per label instance,
and each rewritten hook can be set with `prom.overRideInstHdlr` without a `Provided function not
available` error.

## Before / after

```q
// 1.x
\l extract.q
.prom.newmetric[`number_tables;`gauge;`region;"number of tables"]
numtab:.prom.addmetric[`number_tables;`amer;();0f]
.prom.updval[numtab;:;count tables[]]
.prom.init[]

// 2.x
prom:use`prom                                        / after your own .z.* definitions
prom.enableInstHdlr`po`pc`pg`ps`ph;                  / optional built-in metrics
prom.create ([name:`number_tables;mtype:`gauge;labels:`region;help:"number of tables"])
prom.setv[`number_tables;"f"$count tables[];([region:"amer"])]
```

## Gotchas

- Validation now throws where 1.x accepted anything: wrong operator for the type, `<= 0` increments,
  unknown or missing label keys, duplicate `create`.
- Created-but-never-updated metrics are not served unless `init` was given or `prom.init` called.
- `enableInstHdlr` cannot be undone; a second call for the same handler throws.
- `use` replaces `.z.ph` at load; `enableInstHdlr`ph` stacks a timing wrapper on top of that.
- Define `.z.*` handlers before `use`; redefining one afterwards silently removes the instrumentation.
- Cast gauge values to float (`"f"$`) so output type stays consistent across `setv` and `incr`.
- Empty summaries serve quantiles as `0`, not as missing series.
