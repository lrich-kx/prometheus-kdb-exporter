// examples/tick-x/client/loadgen.q - randomized query load against the tick-x gateway
//
// Drives a mix of valid queries (across all four GW tiers, all three query forms the GW
// accepts, with and without a sym filter), a share of intentionally heavy ones (wide
// time windows), and a share of deliberately bad ones (unknown table/column/tier) — so
// the GW's error-rate and upper-latency-bucket panels actually have something to show.
//
// q examples/tick-x/client/loadgen.q -gwPort 5013 [-rate 20]
//   -gwPort  Gateway port (required)
//   -rate    Target queries per second (default 20)

CLI_ARGS:.Q.opt .z.x;
if[not `gwPort in key CLI_ARGS; -1"usage: q loadgen.q -gwPort <port> [-rate <qps>]"; exit 1];
GW_PORT:"I"$first CLI_ARGS`gwPort;
RATE:$[`rate in key CLI_ARGS; "I"$first CLI_ARGS`rate; 20];

h:hopen `$"::",string GW_PORT;
-1"loadgen: connected to GW on port ",string[GW_PORT]," targeting ~",string[RATE]," queries/sec";

ENERGY_SYM:`BLOWER78_1;
WEATHER_SYM:`SanDiego;
.lg.symFor:{[t] $[t=`energy; ENERGY_SYM; t in `weather`weatherHeatIndex; WEATHER_SYM; `]};

// A random (t1;t2) timespan window somewhere in the day, 1s-1hr wide.
.lg.randWindow:{[]
    t1:"n"$1000000000*rand 86400;
    t2:t1+"n"$1000000000*1+rand 3600;
    (t1;t2)
    };

.lg.strQuery:{[tab;w;sym;useSym]
    "select from ",string[tab]," where time within (",(string w 0),";",(string w 1),")",
        $[useSym; ",sym=`",string sym; ""]
    };

// ~85% valid: tier weighted toward rdb/idb (where the demo actually has data). `all`
// always uses the string form — its query TYPE must not be a general list (0h), or the
// GW's own per-tier split (`query 0/1/2`) misreads it as a 3-per-tier list; a plain
// string broadcasts identically to rdb+idb+hdb. Individual-tier queries pick freely
// across all three forms the GW accepts (string / parse-tree / function+args).
.lg.validQuery:{[]
    tier:first 1?`rdb`rdb`rdb`idb`idb`idb`hdb`hdb`all`all;
    tab:first 1?`energy`energy`weather`weather`weatherHeatIndex;
    w:.lg.randWindow[];
    sym:.lg.symFor[tab];
    useSym:(not null sym) and 0.7>rand 1f;
    // Building this as ((clause1);(clause2)) rather than
    // `enlist(within;...),enlist(=;...)` deliberately — the latter is a q precedence
    // trap: an un-parenthesized `enlist X` extends as far right as it can, so
    // `enlist(within;...),enlist(=;...)` parses as `enlist[(within;...),enlist(=;...)]`
    // (one 4-element clause), not two separate clauses — confirmed live: the GW returned
    // 'rank for every tree-form query that used a sym filter until this was fixed.
    whereClauses:$[useSym; ((within;`time;w);(=;`sym;enlist sym)); enlist(within;`time;w)];
    query:$[tier=`all;
        .lg.strQuery[tab;w;sym;useSym];
        [form:first 1?`str`tree`func;
         $[form=`str;
             .lg.strQuery[tab;w;sym;useSym];
           form=`tree;
             (?;tab;whereClauses;0b;());
           $[useSym;
               ({[t;t1;t2;s] select from t where time within (t1;t2), sym=s}; tab; w 0; w 1; sym);
               ({[t;t1;t2] select from t where time within (t1;t2)}; tab; w 0; w 1)]]
         ]
        ];
    (tier;query)
    };

// ~10% heavy: whole-day window, no sym filter, on a random tier (hdb gets a wide
// historical range rather than "today", since a short demo run never reaches EOD).
.lg.heavyQuery:{[]
    tier:first 1?`rdb`idb`hdb`all;
    tab:first 1?`energy`weather`weatherHeatIndex;
    q:$[tier=`hdb;
        "select from ",string[tab]," where date within (.z.d-7;.z.d), time within (0D00:00:00.000000000;0D23:59:59.999999999)";
        "select from ",string[tab]," where time within (0D00:00:00.000000000;0D23:59:59.999999999)"];
    (tier;q)
    };

// ~5% faulty: unknown table, unknown column, unknown tier — each caught by the GW and
// returned as an `error`msg! dict rather than thrown.
.lg.faultyQuery:{[]
    first 1?(
        (`rdb; "select from nosuchtable");
        (`hdb; "select badcolumn from energy");
        (`bogus; "select from energy"))
    };

.lg.stats:`sent`ok`error!0 0 0;

.lg.fire:{[]
    r:rand 1f;
    tq:$[r<0.05; .lg.faultyQuery[]; r<0.15; .lg.heavyQuery[]; .lg.validQuery[]];
    res:@[h; (`.kxgw.query;tq 0;tq 1); {[e] `error`msg!("client send failed";e)}];
    // `and` isn't short-circuiting, and `key` on a plain (unkeyed) table throws 'type —
    // nest the `$[]` so the second test only runs when res IS a dict (see the same fix
    // in wrappers/gw_instrumented.q).
    isErr:$[99h=type res; `error in key res; 0b];
    .lg.stats[`sent]+:1;
    .lg.stats[$[isErr;`error;`ok]]+:1;
    };

// 20 ticks/sec is a reliable timer resolution; fire enough queries per tick to
// approximate the requested rate rather than trying for a sub-50ms tick interval.
PER_TICK:1|`long$RATE%20;
TICKS_PER_SUMMARY:100; / ~5s at 20 ticks/sec
.lg.tickCount:0;
.z.ts:{[]
    {@[.lg.fire;(::);{[e] -1"loadgen: fire error: ",e}]} each til PER_TICK;
    .lg.tickCount+:1;
    if[0=.lg.tickCount mod TICKS_PER_SUMMARY;
        -1"loadgen: sent=",string[.lg.stats`sent]," ok=",string[.lg.stats`ok]," error=",string .lg.stats`error;
        ];
    };
system"t 50";
