// Load generator + custom instrumentation example (v2 module API)
//
// Connects to the exporter started with examples/exporter.q on port 8080 and
//   1. defines three custom metrics on the exporter over the handle
//   2. generates sync / async / HTTP / error traffic every second so the
//      built-in kdb_* metrics move
//   3. updates the custom metrics from this side as the load runs
//
// Run alongside the exporter:   q examples/kdb_user_example.q

h:hopen 8080

// ---------------------------------------------------------------------------
// 1. custom metric definitions on the exporter (run once, ignore "already defined")
// ---------------------------------------------------------------------------
h"N:100000; tab:([]N?1f;N?10;N?0b;N?`2;N?0p)"
defs:(
  "prom.create([name:`example_table_rows;mtype:`gauge;help:\"rows in the demo table\";labels:`table;init:([table:\"tab\"])])";
  "prom.create([name:`example_batch_rows;mtype:`histogram;help:\"rows per upsert batch\";buckets:10000 50000 100000 150000f;init:`])";
  "prom.create([name:`example_query_seconds;mtype:`summary;help:\"client side query latency\";quantiles:0.5 0.9 0.99;init:`])"
 )
{@[h;x;{-1"create skipped: ",x}]} each defs;

// ---------------------------------------------------------------------------
// 2./3. timer: pick an action by second-of-minute, then refresh custom metrics
// ---------------------------------------------------------------------------
tsplit:0 20 35 45 55_neg[count t]?t:til 60      / random split of a minute into 5 bins
md:0
.z.ts:{
  s:`ss$.z.t;
  $[s in tsplit 0;                              / upsert a random batch, observe its size
      [n:50000+rand 100000;
       h"`tab upsert([]",string[n],"?1f;",string[n],"?10;",string[n],"?0b;",string[n],"?`3;",string[n],"?0p)";
       h(`prom.obs;`example_batch_rows;"f"$n;`)];
    s in tsplit 1;                              / async delete
      neg[h]"delete from `tab where i<10000+rand 100000";
    s in tsplit 2;                              / HTTP GET or timed sync query
      $[0~md mod 2;
        (.Q.hg["http://localhost:8080/?1+1"];);
        [st:.z.p; h"select first x from tab"; h(`prom.obs;`example_query_seconds;1e-9*.z.p-st;`)]];
    s in tsplit 3;                              / sync or async error (caught server side)
      $[0~md mod 3;@[h;"1+`a";::];neg[h]"1+`a"];
    neg[h]"select first x from tab"];           / otherwise an async select
  h(`prom.setv;`example_table_rows;"f"$h"count tab";([table:"tab"]));
  if[0~md mod 30;h".Q.gc[]";.Q.gc[]];
  if[5000000<h"count tab";neg[h]"delete from `tab where i<4000000";h".Q.gc[]"];
  md+:1;
  }

-1".z.ts set to execute every second - watch http://localhost:8080/metrics";
system"t 1000"
