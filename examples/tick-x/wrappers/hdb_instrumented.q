// examples/tick-x/wrappers/hdb_instrumented.q - instrumented HDB
//
// q examples/tick-x/wrappers/hdb_instrumented.q -p $HDB_PORT -hdbDir $HDB_DIR -procName HDB
//
// cwd is the tick-x repo root (startup.sh cd's there), so the node's own relative
// `system"l tick-x/utils/main.q"` resolves.

// 1. the real node, unmodified
system"l tick-x/src/hdb.q";

// 2. prom + shared helpers (absolute path: survives the node's `cd` into $HDB_DIR)
system"l ",getenv[`INSTR_DIR],"/common.q";

// 3. this node's custom metrics
prom.create ([name:`tickx_hdb_reloads_total; mtype:`counter;
              help:"HDB disk reloads (initial load plus .hdb.reload calls)"; init:`]);
prom.create ([name:`tickx_hdb_reload_seconds; mtype:`summary;
              help:"HDB reload duration"; quantiles:.5 .9 .99; init:`]);
prom.create ([name:`tickx_hdb_dates; mtype:`gauge;
              help:"date partitions currently loaded"; init:`]);

// `.hdb.reload` is the one entry point that changes the on-disk view — wrap it rather
// than replace it, so reload-hdb.sh and any other IPC caller still get `` `ok`` back.
.hdb.reload_orig:.hdb.reload;
.hdb.reload:{[]
    t0:.z.p;
    res:.hdb.reload_orig[];
    prom.inc[`tickx_hdb_reloads_total;`];
    prom.obs[`tickx_hdb_reload_seconds;.instr.secs t0;`];
    res
    };

// `.Q.pv` is kdb+'s own sorted list of partition values for a loaded partitioned db —
// maintained by `system"l <dbdir>"` and refreshed by `.hdb.reload`'s `system "l ."`. It
// is only *set* once at least one date partition exists on disk, hence the guard.
.instr.addGauge[`tickx_hdb_dates;`;{[] @[{count .Q.pv};`;{0}]}];

// 4. enable default instrumentation - LAST, per the module's load-order rule
.instr.enable[];
