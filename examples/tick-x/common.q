// examples/tick-x/common.q - shared prom instrumentation helpers for the tick-x demo
//
// Loaded by every wrapper in wrappers/ *after* the real tick-x node (see README.md for
// the four-section wrapper pattern). Defines helpers but enables nothing itself — each
// wrapper calls `.instr.enable[]` explicitly, as the last thing it does, once its own
// custom metrics and wrap points are in place. That keeps the module's documented rule
// ("define your own .z.* handlers before enabling instrumentation") visible in every
// wrapper instead of hidden in here.
//
// Loaded via an absolute path (INSTR_DIR, exported by startup.sh), because by the time
// a wrapper reaches this line the node it just loaded may already have `cd`'d into its
// HDB/IDB root — a relative `system"l"` would resolve against the wrong directory.

prom:use`prom;

.instr.proc:first CLI_ARGS[`procName];

// @desc Build a one-key label dict — the shape every prom.* update function expects.
//
// @param k       {symbol}    Label key
// @param v       {string}    Label value
//
// @return        {dict}      (enlist k)!enlist v
.instr.lbl:{[k;v] (enlist k)!enlist v};

// @desc Seconds elapsed since `t0` (a `.z.p` timestamp), for `prom.obs`.
//
// @param t0      {timestamp} Start time, from `.z.p`
//
// @return        {float}     Elapsed seconds
.instr.secs:{[t0] 1e-9*.z.p-t0};

// @desc Registry of scrape-time gauge samplers, filled in by `.instr.addGauge` and run by
// `.instr.sample` on every /metrics poll (wired up by `.instr.enable`'s `on_poll` override).
.instr.gauges:()!();

// @desc Register a niladic sampler to run on every scrape.
//
// @param name    {symbol}    A gauge already `prom.create`d by the caller
// @param labelKey {symbol}   `` ` `` for an unlabelled gauge, else the single label key
//                             `fn` reports against (e.g. `` `table ``, `` `proc ``)
// @param fn       {function} Niladic. Returns a plain number when `labelKey` is `` ` ``,
//                             else a dict labelValue!number — one `setv` per key.
.instr.addGauge:{[name;labelKey;fn] .instr.gauges[name]:(labelKey;fn)};

// @desc Run every registered sampler and `setv` its result(s) onto the matching gauge.
// A sampler that throws is caught and logged so one bad gauge can't fail the whole scrape.
.instr.sample:{[]
    {[name]
        spec:.instr.gauges name;
        labelKey:spec 0; fn:spec 1;
        @[{[name;labelKey;fn]
            v:fn[];
            $[labelKey~`;
                prom.setv[name;"f"$v;`];
                {[name;labelKey;k;v] prom.setv[name;"f"$v;.instr.lbl[labelKey;k]]}[name;labelKey]'[key v;value v]
             ];
          }[name;labelKey;fn];
          ::;
          {[name;e] -1 "instr: gauge sampler for ",string[name]," failed: ",e}[name]]
        } each key .instr.gauges;
    };

// Same names evhdlr.q's own default `on_poll` sets from `.Q.w[]`, in `.Q.w[]`'s own key
// order. A plain global, not a local of `.instr.enable` below — a lambda body resolves a
// free name dynamically against its *defining* namespace, never against an enclosing
// function's locals (q has no lexical closures over locals), so `on_poll`'s override
// lambda needs this reachable as a real global, not captured from a call-time scope.
.instr.memmetrics:`memory_usage_bytes`memory_heap_bytes`memory_heap_peak_bytes`memory_heap_limit_bytes`memory_mapped_bytes`memory_physical_bytes`kdb_syms_total`kdb_syms_memory_bytes;

// @desc Install the on_poll override (default memory gauges + every registered custom
// gauge) and enable default instrumentation on all ten handlers. Call this LAST, once a
// wrapper's own `prom.create`/wrap/`addGauge` calls are all in place.
//
// An `overRideInstHdlr` REPLACES the default hook rather than chaining it, so the eight
// `.Q.w[]` memory gauges are re-emitted here explicitly, else the memory panels on the
// dashboard go stale the moment any wrapper registers its first custom gauge.
.instr.enable:{[]
    prom.overRideInstHdlr[`on_poll;{[msg]
        prom.setv[;;`]'[.instr.memmetrics;value"f"$.Q.w[]];
        .instr.sample[];
        }];
    prom.enableInstHdlr`po`pc`wo`wc`pg`ps`ph`pp`ws`ts;
    };
