// examples/tick-x/verify.q - prom API coverage smoke test
//
// Standalone: does not start (or need) any tick-x node. Exercises every metric type and
// every exported prom.* function once, including `del`/`metrics`/`metricMeta`, which the
// live wrappers never call (deleting a metric mid-demo would be a bad look on a
// dashboard). Run:
//
//   QPATH=<this repo>:$HOME/.kx/mod q examples/tick-x/verify.q -q
//
// Silent output + exit 0 means pass, matching tests/t.q's own convention (here as a
// labelled boolean check rather than that file's `x)` console-dispatch trick, which only
// applies to lines typed at column 0 of a script, not to calls made from inside one).

prom:use`prom;

.t.fail:0;
.t.e:{[label;cond] if[not cond; -1 "FAIL: ",label; .t.fail+:1]};

// counter: unlabelled, init, inc/incr
prom.create ([name:`verify_counter; mtype:`counter; help:"verify counter"; init:`]);
prom.inc[`verify_counter;`];
prom.incr[`verify_counter;41;`];
.t.e["counter inc+incr";42~first exec first val from prom.metrics[] where metric=`verify_counter];

// counter: 2 labels
prom.create ([name:`verify_labelled_counter; mtype:`counter; help:"verify labelled counter"; labels:`tier`status]);
prom.inc[`verify_labelled_counter;`tier`status!("rdb";"ok")];
prom.incr[`verify_labelled_counter;4;`tier`status!("rdb";"ok")];
.t.e["labelled counter inc+incr";5~first exec first val from prom.metrics[] where metric=`verify_labelled_counter];

// gauge: setv, incr/decr (never setv)
prom.create ([name:`verify_gauge; mtype:`gauge; help:"verify gauge"; init:`]);
prom.setv[`verify_gauge;7;`];
.t.e["gauge setv";7~first exec first val from prom.metrics[] where metric=`verify_gauge];
prom.create ([name:`verify_incr_gauge; mtype:`gauge; help:"verify incr/decr gauge"; init:`]);
prom.incr[`verify_incr_gauge;5;`];
prom.dec[`verify_incr_gauge;`];
.t.e["gauge incr+dec (no setv)";4~first exec first val from prom.metrics[] where metric=`verify_incr_gauge];

// histogram: custom buckets, obs
prom.create ([name:`verify_histogram; mtype:`histogram; help:"verify histogram"; buckets:.1 .5 1; init:`]);
prom.obs[`verify_histogram;.2;`];
.t.e["histogram bucket counts stay long";7h=type value exec first val from prom.metrics[] where metric=`verify_histogram];

// summary: custom quantiles + cacheLength, obs
prom.create ([name:`verify_summary; mtype:`summary; help:"verify summary"; quantiles:.5 .9; cacheLength:10; init:`]);
prom.obs[`verify_summary;.3;`];
.t.e["summary obs";1=exec first cnt from prom.metrics[] where metric=`verify_summary];

// metricMeta round-trips what create was given
.t.e["metricMeta has verify_histogram";`verify_histogram in key prom.metricMeta[]];
.t.e["metricMeta buckets round-trip";.1 .5 1~first prom.metricMeta[][`verify_histogram;`buckets]];

// serve() - exposition format: a terminating newline, le="+Inf" on the overflow bucket
served:prom.serve[];
.t.e["serve ends with newline";"\n"~last served];
.t.e["serve includes verify_histogram";any served like "*verify_histogram*"];
.t.e["serve includes +Inf overflow bucket";any served like "*+Inf*"];

// del removes both the definition and every instance
prom.del[`verify_counter];
.t.e["del removes metricMeta entry";not `verify_counter in key prom.metricMeta[]];
.t.e["del removes every instance";0=count select from prom.metrics[] where metric=`verify_counter];

if[.t.fail=0; -1 "verify.q: all checks passed"];
exit .t.fail>0;
