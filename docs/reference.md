# Prometheus function reference

`prom`   **Prometheus Exporter module**

Load the module<br>
[Loading](#loading)                Put the module on the search path and `use` it<br>
[Configuration](#configuration)    `METRICS_ENDPOINT` and `CACHELENGTH` environment variables

Define metrics<br>
[`prom.create`](#promcreate)       Define a metric (name, type, labels, parameters)<br>
[`prom.init`](#prominit)           Initialize an empty instance of a metric for a given label set<br>
[`prom.del`](#promdel)             Delete a metric and all of its instances

Update metric values<br>
[`prom.inc`](#prominc)             Increment a counter or gauge by 1<br>
[`prom.incr`](#promincr)           Increase a counter or gauge by an amount<br>
[`prom.dec`](#promdec)             Decrement a gauge by 1<br>
[`prom.decr`](#promdecr)           Decrease a gauge by an amount<br>
[`prom.setv`](#promsetv)           Set a gauge to a value<br>
[`prom.obs`](#promobs)             Record an observation on a histogram or summary

Inspect and serve<br>
[`prom.metrics`](#prommetrics)     Current metric instances and values<br>
[`prom.metricMeta`](#prommetricmeta)  Metric definitions<br>
[`prom.serve`](#promserve)         Render all metrics in the Prometheus text exposition format

Instrument event handlers<br>
[`prom.enableInstHdlr`](event-handlers.md#promenableinsthdlr), [`prom.overRideInstHdlr`](event-handlers.md#promoverrideinsthdlr), [`prom.overLoadHdlr`](event-handlers.md#promoverloadhdlr) are documented in [event-handlers.md](event-handlers.md).

:point_right:
[Migrating from v1.x](migration.md)

---

## Loading

The exporter is a [KDB-X module](https://code.kx.com/kdb-x/modules/module-framework/quickstart.html). It requires KDB-X; it does not load on kdb+ 4.x (use the [1.0.1 release](https://github.com/KxSystems/prometheus-kdb-exporter/releases/tag/1.0.1) there).

The `prom` directory must be on the module search path (`.Q.m.SP`, resolved relative to the KDB-X runtime, e.g. `~/.kx/mod`); `install.sh`/`install.bat` ask `q` for that path and copy the module there. Alternatively point `QPATH` at the directory that contains `prom/`, for example the repository root:

```bash
QPATH=/path/to/prometheus-kdb-exporter q -p 8080
```

```q
q)prom:use`prom
NOTE: setting .z.ph for /metrics
q)key prom
`create`inc`incr`dec`decr`setv`obs`del`init`metrics`metricMeta`overLoadHdlr`enableInstHdlr`overRideInstHdlr`serve
```

Loading the module replaces `.z.ph` so that `GET /metrics` returns [`prom.serve[]`](#promserve). Any `.z.ph` already defined is preserved and called for every other path.

:warning:
Load the module **after** all of your own `.z.*` handler definitions. Defining `.z.ph`, `.z.pg`, etc. after `use`prom` (or after [`prom.enableInstHdlr`](event-handlers.md#promenableinsthdlr)) silently discards the exporter's wrapper.

## Configuration

Read from the environment when the module loads.

| variable           | default   | description                                                                                                                 |
| ------------------ | --------- | --------------------------------------------------------------------------------------------------------------------------- |
| `METRICS_ENDPOINT` | `metrics` | HTTP path served by `.z.ph`, i.e. `http://host:port/metrics`. Set without a leading slash.                                 |
| `CACHELENGTH`      | `100000`  | default window of observations kept per `summary` instance; can be overridden per metric with `cacheLength` in `prom.create` |

---

## `prom.create`

_Define a metric_

```txt
prom.create[argDict]
```

Where `argDict` is a dictionary with the following keys

| name        | required | type                | default         | example                 | description                                                                                        |
| ----------- | -------- | ------------------- | --------------- | ----------------------- | -------------------------------------------------------------------------------------------------- |
| name        | yes      | symbol              | N/A             | kdb_metric              | name of metric - used in all other APIs                                                            |
| mtype       | yes      | symbol              | N/A             | summary                 | metric type: `counter`, `gauge`, `histogram` or `summary`                                          |
| labels      | no       | symbol[]            | N/A             | `method`status`handler  | label keys; every instance of the metric must supply exactly these keys                            |
| help        | yes      | string              | N/A             | "kdb summary metric"    | appears in the `# HELP` header                                                                     |
| quantiles   | no       | float[]             | 0.25 0.5 0.75   | 0.5 0.95 0.99           | `summary` only                                                                                     |
| buckets     | no       | float[]             | 0.25 0.5 1 5 10 | 0.1 0.5 1 2.5           | `histogram` only; upper bounds (`le`), `+Inf` is appended automatically                            |
| cacheLength | no       | integer             | `CACHELENGTH`   | 5000                    | `summary` only - number of most recent observations kept for quantile calculation                  |
| init        | no       | dict or null symbol | N/A             | ([method:"GET"]) or `   | initialize an instance for this label set at create time (see [`prom.init`](#prominit))            |

Throws if the name is already defined, a required key is missing, an unknown key is supplied, or a parameter is given for a type that does not accept it (e.g. `buckets` on a `gauge`).

```q
// summary with labels and a custom window
prom.create ([name:`metric_D;
              mtype:`summary;
              help:"some description";
              labels:`method`status`handler;
              quantiles:0.5 0.9 0.99;
              cacheLength:5000])

// unlabelled counter, served as 0 immediately
prom.create ([name:`metric_A;
              mtype:`counter;
              help:"some description";
              init:`])
```

> `summary` metrics keep a window of the last `cacheLength` observed values per instance. Quantiles are calculated over that window when Prometheus polls; `_sum` and `_count` are running totals over all observations.


## `prom.init`

_Initialize an empty instance of a metric_

```txt
prom.init[metric;labels]
```

| name   | required | type               | default | example                                                | description                                                                |
| ------ | -------- | ------------------ | ------- | ------------------------------------------------------ | -------------------------------------------------------------------------- |
| metric | yes      | symbol             | N/A     | kdb_metric                                             | name of a created metric                                                   |
| labels | yes      | symbol **OR** dict | N/A     | ([method:"GET";status:"200";handler:"/home"]) **OR** ` | dict keys must match the label keys given at create. For no labels use `   |

A metric that has been created but never updated is not served, because `prom.create` only defines it. `prom.init` creates an instance with a zero value (counter/gauge at 0, histogram buckets at 0, summary with no observations) so that it appears on the endpoint and in dashboards before the first update. Throws if the instance already exists.

The `init` key of `prom.create` does the same thing at create time.

```q
prom.init[`metric_A;`]
prom.init[`metric_B;([method:"GET";handler:"/db"])]
```


## `prom.inc`

_Increment a counter or gauge by 1_

```txt
prom.inc[metric;labels]
```

| name   | required | type               | default | example                                                | description                                                                |
| ------ | -------- | ------------------ | ------- | ------------------------------------------------------ | -------------------------------------------------------------------------- |
| metric | yes      | symbol             | N/A     | kdb_metric                                             | name of metric to update                                                   |
| labels | yes      | symbol **OR** dict | N/A     | ([method:"GET";status:"200";handler:"/home"]) **OR** ` | dict keys must match the label keys given at create. For no labels use `   |

Available on `counter` and `gauge`. The instance is initialized if it does not exist yet.

```q
prom.inc[`metric_B;([method:"GET";handler:"/db"])]
prom.inc[`metric_B;([method:"POST";handler:"/db"])]
prom.inc[`metric_C;`]
```


## `prom.incr`

_Increase a counter or gauge by an amount_

```txt
prom.incr[metric;val;labels]
```

| name   | required | type               | default | example                                                | description                                                                |
| ------ | -------- | ------------------ | ------- | ------------------------------------------------------ | -------------------------------------------------------------------------- |
| metric | yes      | symbol             | N/A     | kdb_metric                                             | name of metric to update                                                   |
| val    | yes      | numeric            | N/A     | 20                                                     | amount to add; must be > 0                                                 |
| labels | yes      | symbol **OR** dict | N/A     | ([method:"GET";status:"200";handler:"/home"]) **OR** ` | dict keys must match the label keys given at create. For no labels use `   |

Available on `counter` and `gauge`. The instance is initialized if it does not exist yet.

```q
prom.incr[`metric_B;50;([method:"GET";handler:"/db"])]
prom.incr[`metric_B;10;([method:"POST";handler:"/db"])]
prom.incr[`metric_C;15;`]
```


## `prom.dec`

_Decrement a gauge by 1_

```txt
prom.dec[metric;labels]
```

| name   | required | type               | default | example                                                | description                                                                |
| ------ | -------- | ------------------ | ------- | ------------------------------------------------------ | -------------------------------------------------------------------------- |
| metric | yes      | symbol             | N/A     | kdb_metric                                             | name of metric to update                                                   |
| labels | yes      | symbol **OR** dict | N/A     | ([method:"GET";status:"200";handler:"/home"]) **OR** ` | dict keys must match the label keys given at create. For no labels use `   |

Available on `gauge` only; throws on a `counter`. The instance is initialized if it does not exist yet.

```q
prom.dec[`metric_B;([method:"GET";handler:"/db"])]
```


## `prom.decr`

_Decrease a gauge by an amount_

```txt
prom.decr[metric;val;labels]
```

| name   | required | type               | default | example                                                | description                                                                |
| ------ | -------- | ------------------ | ------- | ------------------------------------------------------ | -------------------------------------------------------------------------- |
| metric | yes      | symbol             | N/A     | kdb_metric                                             | name of metric to update                                                   |
| val    | yes      | numeric            | N/A     | 20                                                     | amount to subtract; must be > 0                                            |
| labels | yes      | symbol **OR** dict | N/A     | ([method:"GET";status:"200";handler:"/home"]) **OR** ` | dict keys must match the label keys given at create. For no labels use `   |

Available on `gauge` only. The instance is initialized if it does not exist yet.

```q
prom.decr[`metric_B;30;([method:"GET";handler:"/db"])]
```


## `prom.setv`

_Set a gauge to a value_

```txt
prom.setv[metric;val;labels]
```

| name   | required | type               | default | example                                                | description                                                                |
| ------ | -------- | ------------------ | ------- | ------------------------------------------------------ | -------------------------------------------------------------------------- |
| metric | yes      | symbol             | N/A     | kdb_metric                                             | name of metric to update                                                   |
| val    | yes      | numeric            | N/A     | 20                                                     | value to set; may be positive or negative                                  |
| labels | yes      | symbol **OR** dict | N/A     | ([method:"GET";status:"200";handler:"/home"]) **OR** ` | dict keys must match the label keys given at create. For no labels use `   |

Available on `gauge` only. The instance is initialized if it does not exist yet.

```q
prom.setv[`metric_B;94;([method:"GET";handler:"/db"])]
prom.setv[`metric_B;-28;([method:"POST";handler:"/db"])]
prom.setv[`metric_C;12;`]
```


## `prom.obs`

_Record an observation on a histogram or summary_

```txt
prom.obs[metric;val;labels]
```

| name   | required | type               | default | example                                                | description                                                                |
| ------ | -------- | ------------------ | ------- | ------------------------------------------------------ | -------------------------------------------------------------------------- |
| metric | yes      | symbol             | N/A     | kdb_metric                                             | name of metric to update                                                   |
| val    | yes      | numeric            | N/A     | 0.2                                                    | observed value; must be > 0                                                |
| labels | yes      | symbol **OR** dict | N/A     | ([method:"GET";status:"200";handler:"/home"]) **OR** ` | dict keys must match the label keys given at create. For no labels use `   |

Available on `histogram` and `summary` only. The instance is initialized if it does not exist yet.

-   `histogram`: increments the cumulative count of every bucket whose upper bound is >= `val` (including `+Inf`), and adds to `_sum` and `_count`.
-   `summary`: appends `val` to the instance's observation window (truncated to `cacheLength`), and adds to `_sum` and `_count`. Quantiles are computed from the window when [`prom.serve`](#promserve) runs.

```q
prom.obs[`metric_C;0.2;([method:"POST"])]
prom.obs[`metric_C;0.15;([method:"GET"])]
prom.obs[`metric_F;0.32;`]
```


## `prom.del`

_Delete a metric and all of its instances_

```txt
prom.del[metric]
```

| name   | required | type   | default | example    | description              |
| ------ | -------- | ------ | ------- | ---------- | ------------------------ |
| metric | yes      | symbol | N/A     | kdb_metric | name of metric to delete |

```q
prom.del[`metric_C]
```


## `prom.metrics`

_Current metric instances and values_

```txt
prom.metrics[]
```

Returns a copy of the instance table: one row per (metric, label set). `total` and `cnt` are only populated for `histogram` and `summary`; `val` holds the current value (counter/gauge), the bucket counts keyed by upper bound (histogram) or the observation window (summary).

```q
q)prom.metrics[]
metric   mtype     label                      total cnt val
------------------------------------------------------------------------------------
metric_A counter                                        ,41
metric_D summary                              0.6   2   0.2 0.4
metric_B gauge     method="GET",handler="/db"           300
metric_C histogram method="POST"              0.2   1   (0.1;0.5;1f;2.5;0W)!(0i;1;1;1;1)
```


## `prom.metricMeta`

_Metric definitions_

```txt
prom.metricMeta[]
```

Returns a copy of the definitions created with [`prom.create`](#promcreate), keyed by metric name. Each value is the (defaulted) argument dictionary.

```q
q)prom.metricMeta[]
metric_A| +`name`mtype`help`init!(,`metric_A;,`counter;,"some description";,`)
metric_B| +`name`mtype`help`labels!(,`metric_B;,`gauge;,"some description";,`method`handler)
metric_C| +`name`mtype`help`labels`buckets!(,`metric_C;,`histogram;,"some description";,`method;,0.1 0.5 1 2.5)
metric_D| +`name`mtype`help`quantiles`cacheLength`init!(,`metric_D;,`summary;,"some description";,0.5 0.9 0.99;,5000;,`)
```


## `prom.serve`

_Render all metrics in the Prometheus text exposition format_

```txt
prom.serve[]
```

Returns the string served on `GET /METRICS_ENDPOINT`. Every metric with at least one instance is written with its `# HELP` and `# TYPE` header followed by one line per instance (or per bucket/quantile for aggregate types). Metrics that have been created but neither initialized nor updated are omitted.

```q
q)-1 prom.serve[];
# HELP metric_A some description
# TYPE metric_A counter
metric_A 41
# HELP metric_D some description
# TYPE metric_D summary
metric_D{quantile="0.5"} 0.3
metric_D{quantile="0.9"} 0.38
metric_D{quantile="0.99"} 0.398
metric_D_sum 0.6
metric_D_count 2
# HELP metric_B some description
# TYPE metric_B gauge
metric_B{method="GET",handler="/db"} 300
# HELP metric_C some description
# TYPE metric_C histogram
metric_C{method="POST",le="0.1"} 0
metric_C{method="POST",le="0.5"} 1
metric_C{method="POST",le="1"} 1
metric_C{method="POST",le="2.5"} 1
metric_C{method="POST",le="+Inf"} 1
metric_C_sum{method="POST"} 0.2
metric_C_count{method="POST"} 1
```

With the [default instrumentation](event-handlers.md) enabled the same format is used for the built-in metrics, for example:

```txt
# HELP kdb_sync_total number of sync requests
# TYPE kdb_sync_total counter
kdb_sync_total 1
# HELP kdb_sync_histogram_seconds duration of sync requests
# TYPE kdb_sync_histogram_seconds histogram
kdb_sync_histogram_seconds{le="0.25"} 1
kdb_sync_histogram_seconds{le="0.5"} 1
kdb_sync_histogram_seconds{le="1"} 1
kdb_sync_histogram_seconds{le="5"} 1
kdb_sync_histogram_seconds{le="10"} 1
kdb_sync_histogram_seconds{le="+Inf"} 1
kdb_sync_histogram_seconds_sum 0.000797174
kdb_sync_histogram_seconds_count 1
# HELP kdb_sync_summary_seconds duration of sync requests
# TYPE kdb_sync_summary_seconds summary
kdb_sync_summary_seconds{quantile="0.25"} 0.000797174
kdb_sync_summary_seconds{quantile="0.5"} 0.000797174
kdb_sync_summary_seconds{quantile="0.75"} 0.000797174
kdb_sync_summary_seconds_sum 0.000797174
kdb_sync_summary_seconds_count 1
```
