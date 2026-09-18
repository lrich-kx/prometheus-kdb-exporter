// examples/tick-x/wrappers/fh_instrumented.q - instrumented Feedhandler
//
// q examples/tick-x/wrappers/fh_instrumented.q -p $FH_PORT -tpPort $TICK_PORT -fhTimer $FH_TIMER -procName FH

// 1. the real node, unmodified
system"l tick-x/src/fh.q";

// 2. prom + shared helpers
system"l ",getenv[`INSTR_DIR],"/common.q";

// 3. this node's custom metrics
prom.create ([name:`tickx_fh_rows_published_total; mtype:`counter;
              help:"rows published to the tickerplant"; labels:enlist`table]);
{[tab] prom.init[`tickx_fh_rows_published_total;.instr.lbl[`table;string tab]]} each `energy`weather;
prom.create ([name:`tickx_fh_publish_seconds; mtype:`histogram;
              help:"time to publish one timer tick's batch to the TP"; buckets:.001 .005 .01 .05 .1; init:`]);

// `.timer.funcs[`fhUpsert]` is the whole feed: one row to `energy`, one to `weather`,
// every tick. Wrap the registered entry rather than editing fh.q's own definition.
.instr.fhUpsert_orig:.timer.funcs[`fhUpsert];
.timer.funcs[`fhUpsert]:{[]
    t0:.z.p;
    .instr.fhUpsert_orig[];
    prom.obs[`tickx_fh_publish_seconds;.instr.secs t0;`];
    prom.inc[`tickx_fh_rows_published_total;.instr.lbl[`table;"energy"]];
    prom.inc[`tickx_fh_rows_published_total;.instr.lbl[`table;"weather"]];
    };

// 4. enable default instrumentation - LAST, per the module's load-order rule
.instr.enable[];
