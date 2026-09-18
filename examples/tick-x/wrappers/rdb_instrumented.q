// examples/tick-x/wrappers/rdb_instrumented.q - instrumented RDB (writedown role)
//
// q examples/tick-x/wrappers/rdb_instrumented.q -p $RDB_PORT -tpPort $TICK_PORT -hdbPort $HDB_PORT \
//                                  -idbPort $IDB_PORT -hdbDir $HDB_DIR -idbDir $IDB_DIR \
//                                  -tplogDir $TPLOG_DIR -flushIntvMin $FLUSH_INTV_MIN -procName RDB

// 1. the real node, unmodified
system"l tick-x/src/rdb.q";

// 2. prom + shared helpers (absolute path: survives the node's `cd` into $HDB_DIR)
system"l ",getenv[`INSTR_DIR],"/common.q";

// 3. this node's custom metrics
prom.create ([name:`tickx_rdb_rows; mtype:`gauge;
              help:"rows currently held in memory, pre-flush"; labels:enlist`table]);
{[tab] prom.init[`tickx_rdb_rows;.instr.lbl[`table;string tab]]} each `energy`weather`weatherHeatIndex;
prom.create ([name:`tickx_rdb_pending_rows; mtype:`gauge;
              help:"rows inserted since the last flush (incr on upd, decr on flush)"; init:`]);
prom.create ([name:`tickx_rdb_flushes_total; mtype:`counter;
              help:"intraday flushes that wrote at least one row to the IDB staging dir"; init:`]);
prom.create ([name:`tickx_rdb_flushed_rows_total; mtype:`counter;
              help:"rows moved to IDB staging by a flush"; labels:enlist`table]);
{[tab] prom.init[`tickx_rdb_flushed_rows_total;.instr.lbl[`table;string tab]]} each `energy`weather`weatherHeatIndex;
prom.create ([name:`tickx_rdb_flush_seconds; mtype:`histogram;
              help:"intraday flush duration"; buckets:.005 .01 .05 .1 .5 1; init:`]);
prom.create ([name:`tickx_rdb_watermark_lag_seconds; mtype:`gauge;
              help:"age of the persisted flush watermark"; init:`]);
prom.create ([name:`tickx_rdb_tp_connected; mtype:`gauge;
              help:"1 if TP_H is a live handle, else 0"; init:`]);

// Domain metrics, not just operational — latest reading per sym, straight off the
// in-memory tables this process already holds (no extra wrap point needed).
prom.create ([name:`tickx_energy_consumption_kwh; mtype:`gauge;
              help:"latest energy consumption reading"; labels:enlist`sym]);
prom.create ([name:`tickx_weather_temp_celsius; mtype:`gauge;
              help:"latest weather temperature reading"; labels:enlist`sym]);

// `upd` is the kdb-tick subscriber hook — every row landing in memory is a row pending
// its next flush. Wrap it so the gauge tracks work outstanding, decremented in `.rdb.flush`.
upd_orig:upd;
upd:{[t;x]
    upd_orig[t;x];
    n:$[98h=type x;count x;count first x];
    if[n>0; prom.incr[`tickx_rdb_pending_rows;n;`]];
    };

// `.rdb.flush` has no return value worth using, so row-flushed counts come from the
// before/after row-count delta across every root table. Safe because flush and upd both
// run on the single q main thread (no `-s` secondaries in this demo) — nothing can insert
// between the "before" snapshot and the flush completing.
.rdb.flush_orig:.rdb.flush;
.rdb.flush:{[]
    tbls:tables`.;
    before:count each value each tbls;
    t0:.z.p;
    .rdb.flush_orig[];
    dur:.instr.secs t0;
    flushedByTable:before-count each value each tbls;
    {[tbl;n] if[n>0; prom.incr[`tickx_rdb_flushed_rows_total;n;.instr.lbl[`table;string tbl]]]}'[tbls;flushedByTable];
    flushedTotal:sum flushedByTable where flushedByTable>0;
    if[flushedTotal>0;
        prom.inc[`tickx_rdb_flushes_total;`];
        prom.obs[`tickx_rdb_flush_seconds;dur;`];
        prom.decr[`tickx_rdb_pending_rows;flushedTotal;`];
        ];
    };

.instr.addGauge[`tickx_rdb_rows;`table;{[] t:tables`.; (string each t)!count each value each t}];
// Mirrors `.rdb.flush`'s own `"n"$.z.p` cutoff idiom so both sides of the subtraction are
// in the same reinterpreted-timespan unit space — see rdb.q's cutoff computation.
.instr.addGauge[`tickx_rdb_watermark_lag_seconds;`;{[]
    w:.rdb.readWatermark[];
    $[null w; 0f; 1e-9*"f"$"j"$("n"$.z.p) - w]
    }];
.instr.addGauge[`tickx_rdb_tp_connected;`;{[] "f"$not null TP_H}];
// `.instr.sample` expects dict keys it can drop straight into a label value, so these
// cast the by-sym grouping's symbol keys to strings before returning (same convention
// as `tickx_rdb_rows` above, which does the same for table names).
.instr.addGauge[`tickx_energy_consumption_kwh;`sym;{[]
    $[0=count energy; ()!(); [r:exec last consumption by sym from energy; (string key r)!value r]]
    }];
.instr.addGauge[`tickx_weather_temp_celsius;`sym;{[]
    $[0=count weather; ()!(); [r:exec last temp by sym from weather; (string key r)!value r]]
    }];

// 4. enable default instrumentation - LAST, per the module's load-order rule
.instr.enable[];
