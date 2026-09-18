// examples/tick-x/wrappers/chainedrdb_instrumented.q - instrumented CHAINED_RDB (query role)
//
// q examples/tick-x/wrappers/chainedrdb_instrumented.q -p $CHAINED_RDB_PORT -tpPort $TICK_PORT \
//                                         -tplogDir $TPLOG_DIR -hdbDir $HDB_DIR -idbDir $IDB_DIR -procName CHAINED_RDB

// 1. the real node, unmodified
system"l tick-x/src/chainedrdb.q";

// 2. prom + shared helpers
system"l ",getenv[`INSTR_DIR],"/common.q";

// 3. this node's custom metrics
prom.create ([name:`tickx_crdb_rows; mtype:`gauge;
              help:"rows currently held in memory (the un-flushed rdb tier)"; labels:enlist`table]);
{[tab] prom.init[`tickx_crdb_rows;.instr.lbl[`table;string tab]]} each `energy`weather`weatherHeatIndex;
prom.create ([name:`tickx_crdb_shed_rows_total; mtype:`counter;
              help:"rows dropped when the watermark advanced past them"; init:`]);
prom.create ([name:`tickx_crdb_async_bytes_total; mtype:`counter;
              help:"bytes received on async handles (TP upd + watermark pushes)"; init:`]);

// `.rdb.shedTo` is the TP-relayed push target for the writedown RDB's watermark — the
// row-count delta across a shed IS the count of rows just dropped as already-persisted.
.rdb.shedTo_orig:.rdb.shedTo;
.rdb.shedTo:{[w]
    tbls:tables`.;
    before:sum count each value each tbls;
    .rdb.shedTo_orig[w];
    shed:before-sum count each value each tbls;
    if[shed>0; prom.incr[`tickx_crdb_shed_rows_total;shed;`]];
    };

.instr.addGauge[`tickx_crdb_rows;`table;{[] t:tables`.; (string each t)!count each value each t}];

// Stack an async-byte counter directly onto `.z.ps` with `overLoadHdlr` (rather than a
// wrap-by-redefinition), demonstrating the module's other extension point. Applied BEFORE
// `.instr.enable[]` below, so prom's own default `ps` instrumentation ends up as the
// outermost layer and this one nests inside it, around chainedrdb.q's original `.z.ps`.
prom.overLoadHdlr[`.z.ps;{[f;msg]
    n:count -8!msg;
    if[n>0; prom.incr[`tickx_crdb_async_bytes_total;n;`]];
    f msg
    }];

// 4. enable default instrumentation - LAST, per the module's load-order rule
.instr.enable[];
