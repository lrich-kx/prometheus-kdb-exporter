// run from the repo root: QPATH=$PWD q tests/t.q
prom:use`prom
.t.e:{if[not value x;-1 x]}

a:([name:`metric_A; mtype:`counter;   help:"some description"; init:`]);
b:([name:`metric_B; mtype:`histogram; help:"some description"; labels:`method`status`handler; buckets:0.1 0.5 1 2.5]);
c:([name:`metric_C; mtype:`gauge;     help:"some description" ]);
d:([name:`metric_D; mtype:`summary;   help:"some description"; labels:`method`status`handler; quantiles:0.5 0.9 0.99; cacheLength:5000])
b:([name:`metric_B; mtype:`histogram; help:"some description"; labels:`method`status`handler; buckets:0.1 0.5 1 2.5]);
e:([name:`metric_E; mtype:`gauge;     help:"some description"; buckets:0.1 0.5 1 2.5]);

// create, init
t)0=count prom.metricMeta`
t)0=count prom.metrics`
prom.create d;
t)1=count prom.metricMeta`
prom.create a;
t)2=count prom.metricMeta`
t)1=count prom.metrics`
prom.create each (b;c);
prom.init[`metric_B;([method:"GET";status:"200";handler:"/hist"])]
prom.init[`metric_C;`]
prom.init[`metric_D;([method:"GET";status:"200";handler:"/summ"])]
t)4=count prom.metrics`
t)0=@[prom.create;e;0]

// maths
t)0=.[prom.inc;  (`metric_B;([method:"GET"; handler:"/hist"])); 0]
t)0=.[prom.inc;  (`metric_B;([method:"GET"; status:"200"; handler:"/hist"])); 0]
prom.inc[`metric_A;]each ``;
t)2=first exec first val from prom.metrics[] where metric=`metric_A
prom.incr[`metric_C;15;`]
t)15=first exec first val from prom.metrics[] where metric=`metric_C
t)0=.[prom.dec; (`metric_A;`); 0]
prom.decr[`metric_C;5;`];
t)10=first exec first val from prom.metrics[] where metric=`metric_C

// handler overrides// serving format (Prometheus text exposition)
prom.obs[`metric_D;0.2;([method:"GET";status:"200";handler:"/summ"])]
prom.obs[`metric_B;0.2;([method:"GET";status:"200";handler:"/hist"])]
s:prom.serve[]
t)0<count ss[s;"quantile=\"0.5\""]
t)0=count ss[s;"percentile"]
t)0<count ss[s;"le=\"+Inf\""]
t)0=count ss[s;"+inf\""]
t)0<count ss[s;"metric_B_count{method=\"GET\",status=\"200\",handler=\"/hist\"} 1"]

// handler overrides - every documented hook can be overridden, unknown names rejected
hooks:`on_poll`on_po`on_pc`on_wo`on_wc,raze{`$("before_";"after_"),\:x}each string`pg`ps`ph`pp`ws`ts
noop:{$[x like "after_*";{[tmp;msg;res]};{[a]}]}                 / after_* hooks are triadic, the rest monadic
t)all {(::)~.[prom.overRideInstHdlr;(x;noop x);0b]}each hooks
t)0b~.[prom.overRideInstHdlr;(`nope;{[a]});0b]

// override takes effect on the instrumented handler
prom.enableInstHdlr`ps;
fired:0b
prom.overRideInstHdlr[`before_ps;{[msg] fired::1b; prom.inc[`kdb_async_total;`]; .z.p}]
.z.ps "1+1"
t)fired
t)1=first exec first val from prom.metrics[] where metric=`kdb_async_total

// histogram bucket counts stay long after observations (no int/long mix)
t)7h=type value first exec val from prom.metrics[] where metric=`metric_B
// enableInstHdlr is silent
t)(::)~prom.enableInstHdlr`pg

// setv must not collapse the val column (fresh gauge set first, then a counter created)
prom.create([name:`metric_S;mtype:`gauge;help:"gauge set before anything else"])
prom.setv[`metric_S;1f;`]
t)0h=type exec val from prom.metrics[]
t)(::)~@[prom.create;([name:`metric_T;mtype:`counter;help:"counter after setv";init:`]);0b]
t)1=first exec first val from prom.metrics[] where metric=`metric_S
