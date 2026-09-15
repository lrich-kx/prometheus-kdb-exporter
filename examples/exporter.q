// Prometheus exporter - default instrumentation only
//
// Loads the prom module and enables the built-in metrics for every .z.* event
// handler. Metrics are served on http://localhost:<port>/metrics (override the
// path with the METRICS_ENDPOINT env var).
//
// Run from the repo root (module resolved via QPATH):
//     QPATH=$PWD q examples/exporter.q -p 8080
// or, after ./install.sh has copied prom/ onto the module search path, with no QPATH:
//     q examples/exporter.q -p 8080
//
// Load order matters: define your own .z.* handlers BEFORE this point so the
// module can wrap them; handlers defined afterwards replace the instrumentation.

prom:use`prom
prom.enableInstHdlr`po`pc`wo`wc`pg`ps`ph`pp`ws`ts;

-1"prom: default instrumentation enabled, serving on port ",string[system"p"]," path /",$[count e:getenv`METRICS_ENDPOINT;e;"metrics"];
