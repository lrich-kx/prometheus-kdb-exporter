// examples/tick-x/wrappers/gw_instrumented.q - instrumented Gateway
//
// q examples/tick-x/wrappers/gw_instrumented.q -p $GW_PORT -rdbPort $CHAINED_RDB_PORT -idbPort $IDB_PORT \
//                                 -hdbPort $HDB_PORT -analyticsDir $ANALYTIC_DIR -procName GW
//
// gw.q's own `.rest.init enlist[`autoBind]!enlist[1b]` (kx.rest) owns `.z.ph` first; prom
// is loaded afterwards (section 2) so its `.z.ph_orig` captures the rest router and every
// non-/metrics path still falls through to it. Verified live: kx.rest's registered
// endpoints (e.g. /energy/meta) keep responding once /metrics is also being served.

// 1. the real node, unmodified
system"l tick-x/src/gw.q";

// 2. prom + shared helpers
system"l ",getenv[`INSTR_DIR],"/common.q";

// 3. this node's custom metrics
prom.create ([name:`tickx_gw_queries_total; mtype:`counter;
              help:"gateway queries by tier and outcome"; labels:`tier`status]);
prom.create ([name:`tickx_gw_query_seconds; mtype:`histogram;
              help:"gateway query duration"; labels:enlist`tier; buckets:.005 .01 .05 .1 .5 1 5]);
prom.create ([name:`tickx_gw_query_latency_seconds; mtype:`summary;
              help:"gateway query duration"; labels:enlist`tier; quantiles:.5 .9 .99; cacheLength:1000]);
prom.create ([name:`tickx_gw_result_rows; mtype:`summary;
              help:"rows returned by a tier query, where the result is a table"; labels:enlist`tier; quantiles:.5 .9 .99]);
prom.create ([name:`tickx_gw_tier_up; mtype:`gauge;
              help:"1 if a backend connection is live, else 0"; labels:enlist`proc]);
prom.create ([name:`tickx_gw_sync_by_fn_seconds; mtype:`summary;
              help:"sync request latency by first-token function name"; labels:enlist`fn; quantiles:.5 .9 .99]);

{[t]
    {[t;s] prom.init[`tickx_gw_queries_total;`tier`status!(string t;string s)]}[t] each `ok`error;
    prom.init[`tickx_gw_query_seconds;.instr.lbl[`tier;string t]];
    prom.init[`tickx_gw_query_latency_seconds;.instr.lbl[`tier;string t]];
    prom.init[`tickx_gw_result_rows;.instr.lbl[`tier;string t]];
    } each `rdb`idb`hdb`all;

// `.kxgw.query` is the single dispatch point for every tier — q-IPC clients and every
// REST analytic handler (via `.restgw.query`, an alias to the same function) go through
// it, so wrapping it here covers both traffic sources with one wrap.
.kxgw.query_orig:.kxgw.query;
.kxgw.query:{[target;query]
    t0:.z.p;
    res:.kxgw.query_orig[target;query];
    dur:.instr.secs t0;
    lbl:.instr.lbl[`tier;string target];
    prom.obs[`tickx_gw_query_seconds;dur;lbl];
    prom.obs[`tickx_gw_query_latency_seconds;dur;lbl];
    // `and` is q's (non-short-circuiting) elementwise min, so `` `error in key res``
    // would evaluate even when res isn't a dict — and `key` on a plain table throws
    // 'type. Nest the `$[]` instead so the second test only runs when res IS a dict.
    status:$[99h=type res; $[`error in key res;`error;`ok]; `ok];
    prom.inc[`tickx_gw_queries_total;`tier`status!(string target;string status)];
    // `obs` requires a value > 0 (see prom.q's validateOp) — an empty result table is
    // common and legitimate, so skip the observation rather than crashing on count=0.
    if[(98h=type res) and 0<count res; prom.obs[`tickx_gw_result_rows;"f"$count res;lbl]];
    res
    };
.restgw.query:.kxgw.query;

// Per-function sync latency, via the module's other override hook (triadic: after_pg
// gets [tmp;msg;res]) — same idea as the doc example in docs/event-handlers.md. An
// override REPLACES the hook (there is no supported way to read the previous one back
// from outside the module — `.z.m` only resolves while module code is already on the
// call stack), so the default `kdb_sync_histogram_seconds`/`_summary_seconds` observations
// are re-issued here through the same public `prom.obs` the default hook itself uses —
// every node in this demo keeps the full default set, with no exceptions for the one
// node that also uses this hook.
prom.overRideInstHdlr[`after_pg;{[tmp;msg;res]
    tm:.instr.secs tmp;
    prom.obs[`kdb_sync_histogram_seconds;tm;`];
    prom.obs[`kdb_sync_summary_seconds;tm;`];
    fn:$[10h=type msg; first" "vs msg; string first msg];
    prom.obs[`tickx_gw_sync_by_fn_seconds;tm;.instr.lbl[`fn;fn]];
    }];

.instr.addGauge[`tickx_gw_tier_up;`proc;{[] exec (string proc)!"f"$alive from CONNECTIONS}];

// 4. enable default instrumentation - LAST, per the module's load-order rule
.instr.enable[];
