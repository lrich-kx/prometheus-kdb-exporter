// examples/tick-x/wrappers/rte_instrumented.q - instrumented Real-Time Engine
//
// q examples/tick-x/wrappers/rte_instrumented.q -p $RTE_PORT -tpPort $TICK_PORT -enrichFile $RTE_ENRICH_FILE -procName RTE

// 1. the real node, unmodified
system"l tick-x/src/rte.q";

// 2. prom + shared helpers
system"l ",getenv[`INSTR_DIR],"/common.q";

// 3. this node's custom metrics
prom.create ([name:`tickx_rte_rows_in_total; mtype:`counter;
              help:"rows received from the tickerplant"; labels:enlist`table]);
prom.create ([name:`tickx_rte_enrich_seconds; mtype:`histogram;
              help:"enrichment function duration"; labels:enlist`analytic; buckets:.001 .005 .01 .05 .1]);
prom.create ([name:`tickx_rte_enrich_errors_total; mtype:`counter;
              help:"enrichment function errors"; labels:enlist`analytic]);
prom.create ([name:`tickx_rte_pub_rows_total; mtype:`counter;
              help:"rows published back to the tickerplant"; labels:enlist`table]);
// Known ahead of time from the sample enrichment file (enrich-sample.q registers
// addHeatIndex against weather) — seed it so the panels aren't empty before traffic.
{[f] prom.init[`tickx_rte_enrich_seconds;.instr.lbl[`analytic;string f]];
     prom.init[`tickx_rte_enrich_errors_total;.instr.lbl[`analytic;string f]]
     } each key .rte.enrichmentDict;

// `.rte.pub` is the leaf every enrichment function calls to publish its result — a clean
// wrap point for rows-out, independent of which/how-many enrichments are registered.
.rte.pub_orig:.rte.pub;
.rte.pub:{[t;x]
    n:$[98h=type x;count x;count first x];
    if[n>0; prom.incr[`tickx_rte_pub_rows_total;n;.instr.lbl[`table;string t]]];
    .rte.pub_orig[t;x];
    };

// `upd` (rte.q) is reimplemented rather than wrapped: per-analytic timing/error metrics
// need the boundary around each *individual* registered function, which the original's
// own dispatch loop doesn't expose as a call we could wrap from outside. This mirrors
// the original's logic line for line, with `.log.*` calls kept as-is and only the prom
// observations added — see rte.q's own `upd` for the un-instrumented version.
upd:{[t;x]
    .log.debug[("[FLOW RTE] upd received | table=%s rows=%d"; string t; $[98h=type x; count x; count first x])];
    n:$[98h=type x; count x; count first x];
    if[n>0; prom.incr[`tickx_rte_rows_in_total;n;.instr.lbl[`table;string t]]];
    if[not t in value[.rte.enrichmentDict];
        .log.warn[("No enrichment function registered for table [%s]"; string t)];
        :()
        ];
    enrichmentFuncs: where .rte.enrichmentDict = t;
    .log.debug[("Enrichment functions for table [%s]: [%s]"; string[t]; ", " sv string enrichmentFuncs)];
    {[f;t;x]
        lbl:.instr.lbl[`analytic;string f];
        t0:.z.p;
        .log.debug[("Running enrichment function [%s] for table [%s]"; string f; string t)];
        @[value[f]; x; {[f;t;lbl;e] prom.inc[`tickx_rte_enrich_errors_total;lbl]; .log.error[("Enrichment function [%s] failed for table [%s]: %s"; string f; string t; e)]}[f;t;lbl]];
        prom.obs[`tickx_rte_enrich_seconds;.instr.secs t0;lbl];
        }[;t;x] each enrichmentFuncs;
    };

// 4. enable default instrumentation - LAST, per the module's load-order rule
.instr.enable[];
