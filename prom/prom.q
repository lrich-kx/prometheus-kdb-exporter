
// -------------------------------------------------------------------------------------- //
//                                    Initialization                                      //
// -------------------------------------------------------------------------------------- //

// set config from env vars
if[not count METRICS_ENDPOINT:getenv`METRICS_ENDPOINT;METRICS_ENDPOINT:"metrics"];
CACHELENGTH:100000^"I"$getenv`CACHELENGTH

// endpoint
-1"NOTE: setting .z.ph for /",METRICS_ENDPOINT;
.z.ph_orig:.z.ph
.z.ph:{[msg] $[METRICS_ENDPOINT~msg 0; .h.hy[`txt] serve[]; .z.ph_orig msg]}

// init vals
metricMeta:([]);
.z.M.metrics set ([] metric:`$();mtype:`$();label:`$();total:`float$();cnt:`long$();val:());

// -------------------------------------------------------------------------------------- //
//                                         APIs                                           //
// -------------------------------------------------------------------------------------- //

// validate API args on create
validateCreate:{[args]
    if[args[`name] in key metricMeta;'"Metric already defined"];
    if[not all key[args] in `name`mtype`labels`help`quantiles`buckets`cacheLength`init;'"Unsupported keys provided"];
    if[not all `name`mtype`help in key args;'"Minimum keys missing"];
    if[not args[`mtype] in `summary`gauge`histogram`counter;'"Invalid metric type"];
    if[args[`mtype] in `gauge`counter; if[any `quantiles`buckets`cacheLength in key args;'"args not accepted for counter/gauge metric"]];
    if[`histogram~args[`mtype];
        if[any `quantiles`cacheLength in key args;'"args not accepted for histogram metric"];
        if[not `buckets in key args;args[`buckets]:(.25 .5 1 5 10)]
        ];
    if[`summary~args[`mtype];
        if[`buckets in key args;'"args not accepted for summary metric"];
        if[not `quantiles in key args;args[`quantiles]:(.25 .5 .75)];
        if[not `cacheLength in key args;args[`cacheLength]:CACHELENGTH]
        ];
    :args;
    }

// validate operation
validateOp:{[mtype;op;vl]
    op:first string[op];
    if[(not ":"~op) and vl<=0;'"value argument must be > 0"];
    if[":"~op; if[not `gauge~mtype;'"set option only available on gauge metric"]];
    if[mtype~`counter; if[not "+"~op;'"counters can only be incremented/increased - operation not allowed"]];
    if[" "~op; if[not mtype in `summary`histogram;'"observations only available on histogram or summary metric"]];
    if[(not " "~op) and mtype in `summary`histogram;'"only observations allowed on histogram/summary metric"];
    }

// return label string for downstream logic
validateLabels:{[mmeta;labels]
       useLabels:`labels in key mmeta;
       $[useLabels;if[`~labels;'"labels required"];$[not `~labels;'"labels not accepted";:`]];
       lkeys:raze mmeta`labels;
       if[count key[labels] except lkeys;'"label keys not found"];
       if[count lkeys except key labels;'"missing labels"];
       :makeLabel[raze[lkeys]!labels@lkeys]; // order labels naming as per creation order
       }

// create metric meta - all instances based against this
create:{[args]
    args:validateCreate[args];
    metricMeta[args`name]:enlist args;
    if[`init in key args; initMetric[args`name;args`init]];
    }

// delete metric class and all instances
del:{[met]
    metricMeta _: met;
    delete from .z.M.metrics where metric=met;
    }

// update metric table with initial value(s)
initMetricVals:{[mmeta;labels]
    (metric;mtype):raze mmeta[`name`mtype];
    if[mtype in `counter`gauge; initVal:enlist 0];
    if[`summary~mtype; initVal:()];
    if[`histogram~mtype;buckets:raze mmeta[`buckets]; initVal:(buckets,0W)!(count[buckets]+1)#0i];
    $[mtype in `summary`histogram;
        .z.M.metrics upsert ([metric:metric;mtype:mtype;total:0f;cnt:0;val:initVal;label:labels]);
        .z.M.metrics upsert ([metric:metric;mtype:mtype;val:initVal;label:labels])
        ]
    }

getMetric:{[metric] if[not metric in key metricMeta;'"metric not found"];:flip metricMeta[metric]}

// init a new instance of a metric
initMetric:{[met;labels]
       mmeta:getMetric[met];
       lbl:validateLabels[mmeta;labels];
       if[count select from .z.M.metrics where metric=met, label=lbl;'"metric instance already exists"]; 
       initMetricVals[mmeta;lbl];
       }

// upd functions for metrics table updates
updVal:{enlist x[z;y]}
updDict:{enlist x,k!v:(x k:key[x] where y<=key x)+1}


// generic metric upd for all mtypes - init new instance before operation (non-existent)
updMetric:{[met;vl;lbl;op]
    mmeta:getMetric[met];
    lbl:validateLabels[mmeta;lbl];
    mtype:first mmeta`mtype;
    validateOp[mtype;op;vl];
    if[not count select from .z.M.metrics where metric=met, label=lbl; initMetricVals[mmeta;lbl]]; 
    if[mtype in `summary`histogram; update total+`float$vl, cnt+1j from .z.M.metrics where metric=met, label=lbl];
    if[`histogram~mtype;update .z.m.updDict[;vl] raze val from .z.M.metrics where metric=met, label=lbl];
    if[`summary~mtype;update .z.m.updVal[,;vl;] sublist[neg[first .z.m.metricMeta[met;`cacheLength]];first val] from .z.M.metrics where metric=met, label=lbl];
    if[mtype in `gauge`counter;update .z.m.updVal[op;vl;] first val from .z.M.metrics where metric=met, label=lbl];
    }

// projections for methods
decr:{updMetric[x;y;z;-]}; incr:{updMetric[x;y;z;+]}; setv:{updMetric[x;y;z;:]}; obs:{updMetric[x;y;z;`]}; inc:incr[;1;]; dec:decr[;1;]

// -------------------------------------------------------------------------------------- //
//                                         Serving                                        //
// -------------------------------------------------------------------------------------- //

// write metric header
writeHdr:{raze each ("# HELP ";"# TYPE "),'string[x],/:" ",'(metricMeta[x;`help];string metricMeta[x;`mtype])} 

// calculate provided percentiles on poll
quantile:{[q;x]r[0]+(p-i 0)*last r:0^deltas asc[x]i:0 1+\:floor p:q*-1+count x}                                

// used for label values - adjusting for histogram
wrapstring:{"\"",$[x~"0W";"+Inf";x],"\""}                                                                     

// make the label string based on kv pairs for creating distinct instruments for a give metric
makeLabel:{`$"," sv string[key x],/'"=",/'wrapstring each string value x}                                      
                                              
// create combined metric label for each agg'd metrics (based on tag)
// tag parametrized (used `le for histogram, `quantile for summary here)
makeCombLabel:{[tag;k;v;l]                                                                                     
    metricLabel:{string[x],/:"=",/:wrapstring each string y}[tag;k];
    if[not `~l;metricLabel:string[l],/:",",'metricLabel];
    ("{",'metricLabel,\:"} "),'string v
    }

// create sum and count label for agg'd metrics (from total and cnt columns)
makeExtraLabel:{[data] ("_sum";"_count"),'{$[not `~x;"{",string[x],"} ";" "]}[data`label],/:string(data`total`cnt)}

// format each metric (each table row) for serving
fmtMetric:{[data];
    (name;mtype;label):data`metric`mtype`label;
    if[mtype~`histogram;
        d:data`val;
        :string[name],/:makeCombLabel[`le;key d;get d;label],makeExtraLabel[data]
        ];

    if[mtype~`summary;
        v:data`val;
        / init value is () - if served display this as 0
        if[not count v; v:enlist 0];
        pctl:raze metricMeta[name;`quantiles];
        :string[name],/:makeCombLabel[`quantile;pctl;quantile[pctl;v];label],makeExtraLabel[data]
        ];

    if[mtype in `gauge`counter;
        v:first data`val;
        $[not `~label;res:"{",string[label],"} ",string v;res:" ",string v];
        :enlist string[name],res
        ];
    }

// write all metrics to a servable string
// for each metric, fmt each submetric (i.e. each label) - for a single metric there can be multiple row values, one per label set and add the header
writeMetric:{[met] "\n" sv writeHdr[met],raze fmtMetric each select from .z.M.metrics where metric=met}
serve:{if[not count mets:distinct exec metric from .z.M.metrics;:""]; "\n" sv writeMetric each mets};

// -------------------------------------------------------------------------------------- //
//                         Handler Override and Packaged Defaults                          //
// -------------------------------------------------------------------------------------- //

// base event handlers (for stacking on)
baseHdlrs:([zpo:{[x]};zpc:{[x]};zwo:{[x]};zwc:{[x]};zpg:value;zps:value;zph:{[x]};zpp:{[x]};zws:{[x]};zts:{[x]}])

// NOTE these need to be set post any other .z* definition - defining .z* post overload will overide it
// this creates a new overloaded function and projects with existing, or default (baseHdlrs), handler function
//  - i.e. hdlrFunc:olFunc[existingHdlrFunc;]
// olFunc function should have:
//  - signature => olFunc[existingHdlrFunc;argToExistingHdlrFunc]
//  - at minimum needs to call existingHdlrFunc[argToExistingHdlrFunc]
//  - custom handler logic before and/or after existingHdlrFunc func call (ideally wrapped in a function for readability)
//  - when overloading pg and ps, needs to return the result of existingHdlrFunc[argToExistingHdlrFunc]
// existingFunc[argToExistingFunc] and associate argToExistingFunc are:
//   - handle    => .z.po[hdl]; .z.pc[hdl]; .z.wo[hdl]; .z.wc[hdl]
//   - message   => .z.pg[msg]; .z.ps[msg]; .z.ws[msg]; .z.ph[msg]; .z.pp[msg]
//   - timestamp => .z.ts[dtm]

overLoadHdlr:{[hdlr;olFunc]
    if[`err~hdlrDef:@[value;hdlr;`err];hdlrDef:baseHdlrs[`$ssr[string hdlr;".";""]]];
    hdlr set olFunc[hdlrDef]
    }