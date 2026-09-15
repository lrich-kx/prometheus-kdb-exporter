
// -------------------------------------------------------------------------------------- //
//                                    Default Metics                                      //
// -------------------------------------------------------------------------------------- //

initEvHdlMetrics:{
    // request/handle counter instrumentation
    / number of open handles
    create([name:`kdb_handles_total; mtype:`gauge; help:"number of open handles (ipc and websocket)";init:`]);
    / number of requests counters
    create([name:`kdb_ipc_opened_total; mtype:`counter; help:"number of ipc sockets opened";init:`]);
    create([name:`kdb_ipc_closed_total; mtype:`counter; help:"number of ipc sockets closed";init:`]);
    create([name:`kdb_ws_opened_total;mtype:`counter;help:"number of websockets opened";init:`]);
    create([name:`kdb_ws_closed_total;mtype:`counter;help:"number of websockets closed";init:`]);
    create([name:`kdb_sync_total;mtype:`counter;help:"number of sync requests";init:`]);
    create([name:`kdb_async_total;mtype:`counter;help:"number of async requests";init:`]);
    create([name:`kdb_http_get_total;mtype:`counter;help:"number of http get requests";init:`]);
    create([name:`kdb_http_post_total;mtype:`counter;help:"number of http post requests";init:`]);
    create([name:`kdb_ws_total;mtype:`counter;help:"number of websocket messages";init:`]);
    create([name:`kdb_ts_total;mtype:`counter;help:"number of timer calls";init:`]);
    / number of error counters - NOTE on fusion lib these just blindly increment on each request - disabled here
    /create([name:`kdb_sync_err_total;mtype:`counter;help:"number of errors from sync requests";init:`]);
    /create([name:`kdb_async_err_total;mtype:`counter;help:"number of errors from async requests";init:`]);
    /create([name:`kdb_http_get_err_total;mtype:`counter;help:"number of errors from http get requests";init:`]);
    /create([name:`kdb_http_post_err_total;mtype:`counter;help:"number of errors from http post requests";init:`]);
    /create([name:`kdb_ws_err_total;mtype:`counter;help:"number of errors from websocket messages";init:`]);
    /create([name:`kdb_ts_err_total;mtype:`counter;help:"number of errors from timer calls";init:`]);
    // request duration instrumentation (summary and histogram for each instrument)
    / histograms
    bucketList:(.25 .5 1 5 10);
    create([name:`kdb_sync_histogram_seconds;mtype:`histogram;buckets:bucketList;help:"duration of sync requests";init:`]);
    create([name:`kdb_async_histogram_seconds;mtype:`histogram;buckets:bucketList;help:"duration of async requests";init:`])
    create([name:`kdb_http_get_histogram_seconds;mtype:`histogram;buckets:bucketList;help:"duration of http get requests";init:`]);
    create([name:`kdb_http_post_histogram_seconds;mtype:`histogram;buckets:bucketList;help:"duration of http post requests";init:`]);
    create([name:`kdb_ws_histogram_seconds;mtype:`histogram;buckets:bucketList;help:"duration of websocket messages";init:`]);
    create([name:`kdb_ts_histogram_seconds;mtype:`histogram;buckets:bucketList;help:"duration of timer calls";init:`]);
    / summaries
    quantList:(.25 .5 .75);
    create([name:`kdb_sync_summary_seconds;mtype:`summary;quantiles:quantList; help:"duration of sync requests";init:`]);
    create([name:`kdb_async_summary_seconds;mtype:`summary;quantiles:quantList;help:"duration of async requests";init:`]);
    create([name:`kdb_http_get_summary_seconds;mtype:`summary;quantiles:quantList;help:"duration of http get requests";init:`]);
    create([name:`kdb_http_post_summary_seconds;mtype:`summary;quantiles:quantList;help:"duration of http post requests";init:`]);
    create([name:`kdb_ws_summary_seconds;mtype:`summary;quantiles:quantList;help:"duration of websocket messages";init:`]);
    create([name:`kdb_ts_summary_seconds;mtype:`summary;quantiles:quantList;help:"duration of timer calls";init:`]);
    // memory metrics gauges
    / set on polling
    create([name:`memory_usage_bytes;mtype:`gauge;help:"memory allocated";init:`]);
    create([name:`memory_heap_bytes;mtype:`gauge;help:"memory available in the heap";init:`]);
    create([name:`memory_heap_peak_bytes;mtype:`gauge;help:"maximum heap size so far";init:`]);
    create([name:`memory_heap_limit_bytes;mtype:`gauge;help:"limit on thread heap size";init:`]);
    create([name:`memory_mapped_bytes;mtype:`gauge;help:"mapped memory";init:`]);
    create([name:`memory_physical_bytes;mtype:`gauge;help:"physical memory available";init:`]);
    create([name:`kdb_syms_total;mtype:`gauge;help:"number of symbols";init:`]);
    create([name:`kdb_syms_memory_bytes;mtype:`gauge;help:"memory use of symbols";init:`]);
    }

// -------------------------------------------------------------------------------------- //
//                            Default Handler Instrumentation                             //
// -------------------------------------------------------------------------------------- //

// Default olFunc funcs are provided below which have setable customHdlrLogic function:
//  - on_po; on_pc; on_wo; on_wc; before_pg; after_pg; before_ps; after_ps; before_ph; after_pp; before_ws; after_ws; before_ts; after_ts; on_poll
//  - on_* is used to count open handles (gauge metric) and number of connections (counter metric)
//  - after_* and before_* are used to time requests (with both a summary and histogram metric)

// note po will start counting if handler instrument is enabled (via enableInstHdlr).
// if other handlers are open previous to this, [kdb_ipc_opened_total] will be < [kdb_handles_total]
po:{[f;hdl]on_po hdl;f hdl}
pc:{[f;hdl]on_pc hdl;f hdl}
wo:{[f;hdl]on_wo hdl;f hdl}
wc:{[f;hdl]on_wc hdl;f hdl}
pg:{[f;msg]tmp:before_pg msg;res:f msg;after_pg[tmp;msg;res];res}
ps:{[f;msg]tmp:before_ps msg;res:f msg;after_ps[tmp;msg;res];}
// note initial serve of metrics endpoint will only have mem states (after_ph only updated after serve)
// after_ph summaries will be available and served for subsequent endpoint polls - i.e. summary and histogram counts will be [kdb_http_get_total] -1
ph:{[f;msg]tmp:before_ph msg;if[METRICS_ENDPOINT~msg 0;on_poll[msg]];res:f msg;after_ph[tmp;msg;res];res} 
pp:{[f;msg]tmp:before_pp msg;res:f msg;after_pp[tmp;msg;res];res}                                         
ws:{[f;msg]tmp:before_ws msg;res:f msg;after_ws[tmp;msg;res];}
ts:{[f;dtm]tmp:before_ts dtm;res:f dtm;after_ts[tmp;dtm;res];}

// on metrics poll set memory metrics (.Q.w[])
memmetrics:`memory_usage_bytes`memory_heap_bytes`memory_heap_peak_bytes`memory_heap_limit_bytes`memory_mapped_bytes`memory_physical_bytes`kdb_syms_total`kdb_syms_memory_bytes
on_poll:{[msg] setv[;;`]'[memmetrics;value"f"$.Q.w[]];}

// for each handle
// - increment total handles
// - set number of open handles
on_po:{[msg]
  inc[`kdb_ipc_opened_total;`];
  setv[`kdb_handles_total;"f"$count .z.W;`];}
on_pc:{[msg]
  inc[`kdb_ipc_closed_total;`];
  setv[`kdb_handles_total;"f"$count .z.W;`];}
on_wo:{[msg]
  inc[`kdb_ws_opened_total;`];
  setv[`kdb_handles_total;"f"$count .z.W;`];}
on_wc:{[msg]
  inc[`kdb_ws_closed_total;`];
  setv[`kdb_handles_total;"f"$count .z.W;`];}

// for each before
// - increment qry counter
// - return timestamp
before:{[met;msg] inc[`$"kdb_",met,"_total";`]; .z.p};

// for each after
// - determine duration
// - add duration to summary and history observations
after:{[met;tmp;msg;res]
      tm:(10e-10)*.z.p-tmp;
      obs[`$"kdb_",met,"_histogram_seconds";tm;`];
      obs[`$"kdb_",met,"_summary_seconds";tm;`];};

// programmatically define before/afters for each handler
before_pg:before"sync"
after_pg :after"sync"
before_ps:before"async"
after_ps :after"async"
before_ph:before"http_get"
after_ph :after"http_get"
before_pp:before"http_post"
after_pp :after"http_post"
before_ws:before"ws"
after_ws :after"ws"
before_ts:before"ts"
after_ts :after"ts"

// -------------------------------------------------------------------------------------- //
//                                  Configure/Override APIS                                //
// -------------------------------------------------------------------------------------- //

// hooks available for override: on_* handlers plus before/after pairs for each request handler
instHooks:`on_poll`on_po`on_pc`on_wo`on_wc,raze{`$("before_";"after_"),\:x}each string`pg`ps`ph`pp`ws`ts

// user can set on_*, before/after_* once defaults enabled
overRideInstHdlr:{[funcName;func]
      if[not funcName in instHooks;'"Provided function not available for override"];
      .z.m[funcName]:func;
      }

// list of possible active default(s)
defaultStacks:([
    po:{overLoadHdlr[`.z.po;po]};
    pc:{overLoadHdlr[`.z.pc;pc]};
    wo:{overLoadHdlr[`.z.wo;wo]};
    wc:{overLoadHdlr[`.z.wc;wc]};
    pg:{overLoadHdlr[`.z.pg;pg]};
    ps:{overLoadHdlr[`.z.ps;ps]};
    ph:{overLoadHdlr[`.z.ph;ph]};
    pp:{overLoadHdlr[`.z.pp;pp]};
    ws:{overLoadHdlr[`.z.ws;ws]};
    ts:{overLoadHdlr[`.z.ts;ts]}
    ])

// user activated defaults
activeStacks:()
enableInstHdlr:{[hdlrs]
    if[not count activeStacks;initEvHdlMetrics[]];
    if[not all hdlrs in `po`pc`wo`wc`pg`ps`ph`pp`ws`ts;'"Handler override non-existent"];
    if[any hdlrs in activeStacks;'"Handle(s) already customized"];
    activeStacks,:hdlrs;
    {defaultStacks[x][]} each hdlrs;
    }