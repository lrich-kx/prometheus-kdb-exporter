# Prometheus metric event handlers

The module can instrument the process's `.z.*` event handlers to produce a standard set of metrics (connection counts, request counts and durations, memory) without any code changes in the application. Instrumentation is **opt-in per handler** and is enabled after the module is loaded.

`prom.`   **event handler APIs**<br>
[`enableInstHdlr`](#promenableinsthdlr)     Enable the default instrumentation for a list of handlers<br>
[`overRideInstHdlr`](#promoverrideinsthdlr) Replace the logic run inside an instrumented handler<br>
[`overLoadHdlr`](#promoverloadhdlr)         Stack arbitrary logic on any `.z.*` handler

[Default metrics](#default-metrics)<br>
[Hook signatures](#hook-signatures)

:point_right:
[Example usage](../examples/kdb_user_example.q)

:warning:
Load the module and call `prom.enableInstHdlr` **after** all of your own `.z.*` definitions. Assigning `.z.pg`, `.z.ph`, etc. afterwards replaces the exporter's wrapper and the corresponding metrics stop updating. This is the same rule as `.prom.init` in v1.

---

## `prom.enableInstHdlr`

_Enable the default instrumentation for a list of handlers_

```txt
prom.enableInstHdlr[hdlrs]
```

Where `hdlrs` is a symbol or list of symbols from

```txt
po pc wo wc pg ps ph pp ws ts
```

each corresponding to `.z.po`, `.z.pc`, `.z.wo`, `.z.wc`, `.z.pg`, `.z.ps`, `.z.ph`, `.z.pp`, `.z.ws`, `.z.ts`.

For each handler named, the current definition (or the q default if none is defined) is wrapped so that the hooks listed under [Hook signatures](#hook-signatures) run before and after it. The first call also creates every metric in the [default metrics](#default-metrics) table, so they are served as zero immediately.

```q
q)prom:use`prom
q)prom.enableInstHdlr`po`pc`wo`wc`pg`ps`ph`pp`ws`ts   / everything
q)prom.enableInstHdlr`pg`ps                          / or just IPC requests
```

-   Enabling is one-way; there is no `disable`.
-   Throws `Handle(s) already customized` if any handler in the list has already been enabled, and `Handler override non-existent` for an unknown name.
-   `ph`: the module already takes over `.z.ph` at `use` time to serve `/METRICS_ENDPOINT`. Enabling `ph` additionally counts and times HTTP GET requests. Because the endpoint request itself is timed, the first scrape shows `kdb_http_get_total` one ahead of `kdb_http_get_histogram_seconds_count`; they agree from the second scrape on.
-   `po`: handles opened before `po` was enabled are not counted in `kdb_ipc_opened_total`, but `kdb_handles_total` is set from `count .z.W` and so is always correct after the next open/close.
-   Memory and symbol gauges are refreshed on every scrape by the `on_poll` hook, not by a timer.


## `prom.overRideInstHdlr`

_Replace the logic run inside an instrumented handler_

```txt
prom.overRideInstHdlr[hook;func]
```

Where

-   `hook` is one of the hook names listed under [Hook signatures](#hook-signatures)
-   `func` is a function with the arity of that hook

replaces the default logic for that hook. The handler wrapper installed by `enableInstHdlr` picks up the new definition immediately. Throws `Provided function not available for override` for an unknown hook name.

Use this to change *what is measured* while keeping the wrapping. For example, to label sync-request durations by the first token of the query:

```q
prom.create ([name:`kdb_sync_by_fn_seconds;mtype:`summary;help:"sync duration by function";labels:enlist`fn])
prom.enableInstHdlr`pg
prom.overRideInstHdlr[`after_pg;{[tmp;msg;res]
  fn:$[10h=type msg;first" "vs msg;string first msg];
  prom.obs[`kdb_sync_by_fn_seconds;1e-9*.z.p-tmp;(enlist`fn)!enlist fn]}]
```

Note that the replaced default no longer runs, so in the example above `kdb_sync_histogram_seconds` and `kdb_sync_summary_seconds` stop being observed unless the new function also calls `prom.obs` on them. `before_pg` still increments `kdb_sync_total` and returns the start timestamp.


## `prom.overLoadHdlr`

_Stack arbitrary logic on any `.z.*` handler_

```txt
prom.overLoadHdlr[hdlr;olFunc]
```

Where

-   `hdlr` is the handler name as a symbol, e.g. `` `.z.ps ``
-   `olFunc` is a dyadic function `{[f;arg] ... }` where `f` is the existing handler (or the q default if none is defined) and `arg` is the handler's argument

sets `hdlr` to `olFunc[f;]`. This is the primitive that `enableInstHdlr` uses internally; call it directly to add your own metrics to a handler that the defaults do not cover, or to stack extra logic on top of the defaults.

`olFunc` **must** call `f arg`, and for `.z.pg`, `.z.ps`, `.z.ph`, `.z.pp` and `.z.ws` must return its result. `arg` is a handle for `po`/`pc`/`wo`/`wc`, a message for `pg`/`ps`/`ws`, `(requestText;headers)` for `ph`/`pp`, and a timestamp for `ts`.

```q
prom.create ([name:`app_async_bytes_total;mtype:`counter;help:"bytes received on async handles";init:`])
prom.overLoadHdlr[`.z.ps;{[f;msg] prom.incr[`app_async_bytes_total;count -8!msg;`]; f msg}]
```

Can be called repeatedly on the same handler; each call wraps the previous definition.


## Default metrics

Created by the first call to `enableInstHdlr`, all without labels. Which of them move depends on which handlers are enabled.

| metric                            | type      | updated by | help                                        |
| --------------------------------- | --------- | ---------- | ------------------------------------------- |
| `kdb_handles_total`               | gauge     | po pc wo wc | number of open handles (ipc and websocket) |
| `kdb_ipc_opened_total`            | counter   | po         | number of ipc sockets opened                |
| `kdb_ipc_closed_total`            | counter   | pc         | number of ipc sockets closed                |
| `kdb_ws_opened_total`             | counter   | wo         | number of websockets opened                 |
| `kdb_ws_closed_total`             | counter   | wc         | number of websockets closed                 |
| `kdb_sync_total`                  | counter   | pg         | number of sync requests                     |
| `kdb_async_total`                 | counter   | ps         | number of async requests                    |
| `kdb_http_get_total`              | counter   | ph         | number of http get requests                 |
| `kdb_http_post_total`             | counter   | pp         | number of http post requests                |
| `kdb_ws_total`                    | counter   | ws         | number of websocket messages                |
| `kdb_ts_total`                    | counter   | ts         | number of timer calls                       |
| `kdb_sync_histogram_seconds`      | histogram | pg         | duration of sync requests                   |
| `kdb_async_histogram_seconds`     | histogram | ps         | duration of async requests                  |
| `kdb_http_get_histogram_seconds`  | histogram | ph         | duration of http get requests               |
| `kdb_http_post_histogram_seconds` | histogram | pp         | duration of http post requests              |
| `kdb_ws_histogram_seconds`        | histogram | ws         | duration of websocket messages              |
| `kdb_ts_histogram_seconds`        | histogram | ts         | duration of timer calls                     |
| `kdb_sync_summary_seconds`        | summary   | pg         | duration of sync requests                   |
| `kdb_async_summary_seconds`       | summary   | ps         | duration of async requests                  |
| `kdb_http_get_summary_seconds`    | summary   | ph         | duration of http get requests               |
| `kdb_http_post_summary_seconds`   | summary   | pp         | duration of http post requests              |
| `kdb_ws_summary_seconds`          | summary   | ws         | duration of websocket messages              |
| `kdb_ts_summary_seconds`          | summary   | ts         | duration of timer calls                     |
| `memory_usage_bytes`              | gauge     | on_poll    | memory allocated (`.Q.w[]` `used`)          |
| `memory_heap_bytes`               | gauge     | on_poll    | memory available in the heap (`heap`)       |
| `memory_heap_peak_bytes`          | gauge     | on_poll    | maximum heap size so far (`peak`)           |
| `memory_heap_limit_bytes`         | gauge     | on_poll    | limit on thread heap size (`wmax`)          |
| `memory_mapped_bytes`             | gauge     | on_poll    | mapped memory (`mmap`)                      |
| `memory_physical_bytes`           | gauge     | on_poll    | physical memory available (`mphy`)          |
| `kdb_syms_total`                  | gauge     | on_poll    | number of symbols (`syms`)                  |
| `kdb_syms_memory_bytes`           | gauge     | on_poll    | memory use of symbols (`symw`)              |

Histograms use buckets `0.25 0.5 1 5 10` seconds; summaries use quantiles `0.25 0.5 0.75` over a window of `CACHELENGTH` observations.

Not emitted in v2 (present in v1): `kdb_info` and the six `kdb_*_err_total` counters. The v1 error counters incremented on every request and decremented on completion rather than counting errors, so they were not meaningful; remove any dashboard panels or alerts that reference them.


## Hook signatures

These are the functions run inside the wrapped handlers. Replace them with [`prom.overRideInstHdlr`](#promoverrideinsthdlr). Signatures are unchanged from v1.

| hook        | arity | signature                                      | default behaviour                                                       |
| ----------- | ----- | ---------------------------------------------- | ----------------------------------------------------------------------- |
| `on_poll`   | 1     | `on_poll (requestText;headers)`                | set the memory/symbol gauges from `.Q.w[]`                              |
| `on_po`     | 1     | `on_po hdl`                                    | `inc kdb_ipc_opened_total`; `setv kdb_handles_total`                    |
| `on_pc`     | 1     | `on_pc hdl`                                    | `inc kdb_ipc_closed_total`; `setv kdb_handles_total`                    |
| `on_wo`     | 1     | `on_wo hdl`                                    | `inc kdb_ws_opened_total`; `setv kdb_handles_total`                     |
| `on_wc`     | 1     | `on_wc hdl`                                    | `inc kdb_ws_closed_total`; `setv kdb_handles_total`                     |
| `before_pg` | 1     | `before_pg msg`                                | `inc kdb_sync_total`; return `.z.p`                                     |
| `after_pg`  | 3     | `after_pg[tmp;msg;res]`                        | `obs` elapsed seconds on `kdb_sync_histogram_seconds` and `_summary_`   |
| `before_ps` | 1     | `before_ps msg`                                | as `before_pg` for `kdb_async_total`                                    |
| `after_ps`  | 3     | `after_ps[tmp;msg;res]`                        | as `after_pg` for `kdb_async_*`                                         |
| `before_ph` | 1     | `before_ph (requestText;headers)`              | as `before_pg` for `kdb_http_get_total`                                 |
| `after_ph`  | 3     | `after_ph[tmp;(requestText;headers);res]`      | as `after_pg` for `kdb_http_get_*`                                      |
| `before_pp` | 1     | `before_pp (requestText;headers)`              | as `before_pg` for `kdb_http_post_total`                                |
| `after_pp`  | 3     | `after_pp[tmp;(requestText;headers);res]`      | as `after_pg` for `kdb_http_post_*`                                     |
| `before_ws` | 1     | `before_ws msg`                                | as `before_pg` for `kdb_ws_total`                                       |
| `after_ws`  | 3     | `after_ws[tmp;msg;res]`                        | as `after_pg` for `kdb_ws_*`                                            |
| `before_ts` | 1     | `before_ts dtm`                                | as `before_pg` for `kdb_ts_total`                                       |
| `after_ts`  | 3     | `after_ts[tmp;dtm;res]`                        | as `after_pg` for `kdb_ts_*`                                            |

Where

-   `tmp` is whatever the matching `before_*` hook returned (a timestamp by default)
-   `msg` / `(requestText;headers)` / `dtm` is the handler argument
-   `res` is the value returned by the wrapped handler
-   `hdl` is the connection handle
