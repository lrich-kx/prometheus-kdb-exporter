# ![Prometheus Exporter](prometheus.png) Prometheus Exporter for KDB-X

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/kxsystems/prometheus-kdb-exporter?include_prereleases)](https://github.com/kxsystems/prometheus-kdb-exporter/releases)

This interface exposes metrics from a KDB-X process to [Prometheus](https://prometheus.io/). It is a
[KDB-X module](https://code.kx.com/kdb-x/modules/module-framework/overview.html) that provides:

- a Prometheus-client-style API for instrumenting your own code with `counter`, `gauge`, `histogram`
  and `summary` metrics, with labels
- opt-in instrumentation of the `.z.*` event handlers (IPC, HTTP, websocket, timer) that produces a
  standard set of request-count, request-duration and memory metrics
- a `/metrics` HTTP endpoint served from the process for Prometheus to scrape

This interface is part of the [_Fusion for kdb+_](https://code.kx.com/q/interfaces#fusion/) project.

> **Version 2 is a rewrite for KDB-X.** It replaces the `q/exporter.q` script and `.prom.*` global
> functions of 1.x with a module loaded via `use`, and changes the metric API. It requires KDB-X and
> does not run on kdb+ 4.x. The 1.x line remains available at tag
> [`1.0.1`](https://github.com/KxSystems/prometheus-kdb-exporter/tree/1.0.1). Existing users should
> read the [migration guide](docs/migration.md) before upgrading.

## New to KDB-X ?

KDB-X is the next generation of the kdb+ time-series database, with a module framework, native
Parquet support and multi-language access. To get started, visit https://developer.kx.com. For
general information, visit https://kx.com/

## What is Prometheus ?

Prometheus is an open source monitoring solution which facilitates metrics gathering, querying and
alerting for a wealth of different 3rd-party languages and applications. It also provides integration
with Kubernetes for automatic discovery of supported applications.

Visualization and querying can be done through the Prometheus built in expression browser, or more
commonly via Grafana. The repo includes [an example](examples) of this using Docker.

## Quick start

Install the module onto the KDB-X module search path. The install scripts ask `q` for its default
search path (`.Q.m.SP`, resolved relative to the KDB-X runtime) and copy the module there as `prom/`; pass a directory
to install somewhere else:

```bash
## Linux/macOS
chmod +x install.sh && ./install.sh            # or: ./install.sh /some/module/dir

## Windows
install.bat
```

Alternatively, skip the install and add this repository to the module search path:

```bash
export QPATH=/path/to/prometheus-kdb-exporter
```

Load the module in your process **after** any of your own `.z.*` handler definitions, then enable
the built-in instrumentation for the handlers you care about:

```q
q)prom:use`prom
q)prom.enableInstHdlr`po`pc`pg`ps`ph
```

Start the process with a listening port, e.g. `q myapp.q -p 8080`, and view the exposed metrics at
http://localhost:8080/metrics. The values shown are those at the time the URL is requested.

To expose the full default set without writing any code, run the supplied example:

```bash
QPATH=$PWD q examples/exporter.q -p 8080
```

## Instrumenting your own code

```q
prom:use`prom

// define once
prom.create ([name:`orders_total; mtype:`counter; help:"orders received"; labels:`venue])
prom.create ([name:`order_latency_seconds; mtype:`histogram; help:"order round trip"; buckets:.01 .05 .1 .5 1])

// update wherever it happens
prom.inc[`orders_total;([venue:"XNAS"])]
prom.obs[`order_latency_seconds;0.042;`]
```

The full API is documented in [`docs/reference.md`](docs/reference.md).

## Configuration

| Environment variable | Default   | Purpose                                                              |
| -------------------- | --------- | -------------------------------------------------------------------- |
| `METRICS_ENDPOINT`   | `metrics` | Path served by `.z.ph`, i.e. `http://host:port/<METRICS_ENDPOINT>`   |
| `CACHELENGTH`        | `100000`  | Default number of observations kept per summary metric for quantiles |

Loading the module takes over `.z.ph` to serve the endpoint. Any `.z.ph` you defined beforehand is
called for every other path.

## Unsupported functionality

This interface does not provide service discovery. Prometheus itself has support for multiple
mechanisms such as DNS, Kubernetes, EC2, file based config, etc., to discover all the KDB-X instances
within your environment.

## Documentation

:open_file_folder: [`docs`](docs)

- [API reference](docs/reference.md)
- [Event handler instrumentation](docs/event-handlers.md)
- [Docker/Grafana example](docs/examples.md)
- [Migrating from 1.x](docs/migration.md)
- [Changelog](CHANGELOG.md)

## Status

The prometheus-kdb-exporter interface is provided here under an Apache 2.0 license.

If you find issues with the interface or have feature requests please [raise an issue](../../issues).

To contribute to this project, please follow the [contribution guide](CONTRIBUTING.md).
