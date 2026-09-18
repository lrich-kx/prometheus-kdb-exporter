// examples/tick-x/wrappers/idb_instrumented.q - instrumented IDB
//
// q examples/tick-x/wrappers/idb_instrumented.q -p $IDB_PORT -hdbDir $HDB_DIR -idbDir $IDB_DIR -procName IDB

// 1. the real node, unmodified
system"l tick-x/src/idb.q";

// 2. prom + shared helpers (absolute path: survives the node's `cd` into $HDB_DIR)
system"l ",getenv[`INSTR_DIR],"/common.q";

// 3. this node's custom metrics
prom.create ([name:`tickx_idb_reloads_total; mtype:`counter;
              help:"IDB int-partition reloads triggered by the writedown RDB"; init:`]);
prom.create ([name:`tickx_idb_reload_seconds; mtype:`histogram;
              help:"IDB reload duration"; buckets:.005 .01 .05 .1 .5; init:`]);
prom.create ([name:`tickx_idb_partitions; mtype:`gauge;
              help:"int-partitions currently staged (today/<i>/)"; init:`]);
prom.create ([name:`tickx_idb_rows; mtype:`gauge;
              help:"rows currently held per table"; labels:enlist`table]);
{[tab] prom.init[`tickx_idb_rows;.instr.lbl[`table;string tab]]} each `energy`weather`weatherHeatIndex;

// The initial `.idb.reload[]` call inside idb.q itself (before this wrapper runs) uses
// the un-instrumented original, so it isn't counted here — consistent with the rest of
// the module: a handler only reports on calls made after instrumentation is wired up.
.idb.reload_orig:.idb.reload;
.idb.reload:{[]
    t0:.z.p;
    res:.idb.reload_orig[];
    prom.inc[`tickx_idb_reloads_total;`];
    prom.obs[`tickx_idb_reload_seconds;.instr.secs t0;`];
    res
    };

.instr.addGauge[`tickx_idb_partitions;`;{[] count key .idb.dir}];
.instr.addGauge[`tickx_idb_rows;`table;{[] t:tables`.; (string each t)!count each value each t}];

// 4. enable default instrumentation - LAST, per the module's load-order rule
.instr.enable[];
