// load prometheus library
\l ::prom.q

// load in default event handlers
\l ::evhdlr.q

// public functions
export:([
    create;inc;incr;dec;decr;setv;obs;del;init:initMetric;  // methods
    metrics:{metrics};metricMeta:{metricMeta};             // current metrics
    overLoadHdlr;                                          // overload a handler
    enableInstHdlr;overRideInstHdlr;                       // enable and customize default metrics 
    serve                                                  // what is served to poll endpoint
    ])