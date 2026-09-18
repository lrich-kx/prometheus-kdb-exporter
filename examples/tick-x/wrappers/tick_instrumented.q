// examples/tick-x/wrappers/tick_instrumented.q - instrumented Tickerplant
//
// q examples/tick-x/wrappers/tick_instrumented.q -p $TICK_PORT -schemaDir $SCHEMA_DIR -tplogDir $TPLOG_DIR -procName TP

// 1. the real node, unmodified
system"l tick-x/src/tick.q";

// 2. prom + shared helpers
system"l ",getenv[`INSTR_DIR],"/common.q";

// 3. this node's custom metrics
prom.create ([name:`tickx_tp_pub_rows_total; mtype:`counter;
              help:"rows published to subscribers"; labels:enlist`table]);
{[tab] prom.init[`tickx_tp_pub_rows_total;.instr.lbl[`table;string tab]]} each `energy`weather`weatherHeatIndex;
prom.create ([name:`tickx_tp_subscribers; mtype:`gauge;
              help:"active table subscriptions (one per handle per table)"; init:`]);
prom.create ([name:`tickx_tp_log_bytes; mtype:`gauge;
              help:"tickerplant log file size"; init:`]);

// `.u.pub` (u.q) fans a batch out to every subscriber of `t` — wrap it for the
// rows-published counter, keeping the original fan-out untouched.
.u.pub_orig:.u.pub;
.u.pub:{[t;x]
    n:$[98h=type x;count x;count first x];
    if[n>0; prom.incr[`tickx_tp_pub_rows_total;n;.instr.lbl[`table;string t]]];
    .u.pub_orig[t;x];
    };

// `.u.sub` (u.q) is called once per (table;handle) subscription — every RDB/CHAINED_RDB
// connect subscribes to every table, and RTE subscribes per enrichment. `inc` here pairs
// with the `dec` loop below in `.z.pc`, giving the gauge exact inc/dec symmetry.
.u.sub_orig:.u.sub;
.u.sub:{[x;y]
    res:.u.sub_orig[x;y];
    prom.inc[`tickx_tp_subscribers;`];
    res
    };

// `.z.pc` is already set by u.q (drops the closing handle from every table's subscriber
// list). Count how many tables it was actually subscribed to *before* delegating, so the
// gauge only moves for handles that really were subscribers.
.z.pc_orig:.z.pc;
.z.pc:{[h]
    removed:sum {[h;tab] h in .u.w[tab;;0]}[h] each .u.t;
    if[removed>0; prom.dec[`tickx_tp_subscribers;`] each til removed];
    .z.pc_orig[h];
    };

.instr.addGauge[`tickx_tp_log_bytes;`;{[] $[type key .u.L; hcount .u.L; 0]}];

// 4. enable default instrumentation - LAST, per the module's load-order rule
.instr.enable[];
