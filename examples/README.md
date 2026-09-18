# Prometheus Exporter for KDB-X – example

The demonstration below is described in full [here](../docs/examples.md). The following is a summary.

## Requirements

- KDB-X
- Docker with Compose (Docker Desktop for Mac/Windows, or Docker Engine 20.10+ on Linux) with Internet access

## Setup

Start the exporter on port 8080 from the repository root (or drop `QPATH` if you have run `install.sh`):

```bash
QPATH=$PWD q examples/exporter.q -p 8080
```

This exposes the built-in metrics for this process at http://localhost:8080/metrics for consumption by Prometheus.

Start the pre-configured Prometheus and Grafana from the `DockerCompose` folder:

```bash
docker compose up
```

and stop them with Ctrl-C or

```bash
docker compose down
```

## Example resource utilization

`kdb_user_example.q` connects to the exporter on port 8080, generates sync/async/HTTP/error traffic on a timer, and defines and updates three custom metrics (`example_table_rows`, `example_batch_rows`, `example_query_seconds`) through the module API:

```bash
q examples/kdb_user_example.q
```

## Accessing Prometheus and Grafana

- Prometheus: http://localhost:9090 — the expression `up` should be `1` for the `kdb` job
- Grafana: http://localhost:3000 — username `admin`, password `pass`

A pre-configured dashboard named `kdb+` is provisioned. It is an example of what can be monitored and is by no means exhaustive.

![Grafana](grafana.png)

## A multi-process example

The example above is a single process. [tick-x/](tick-x/) instruments every node of a
real multi-process kdb-tick stack — the
[kdbx-tick-reference-architecture](https://github.com/KxSystems/kdbx-tick-reference-architecture)
`tick-x` variant (tickerplant, feedhandler, RDB, chained RDB, IDB, HDB, RTE and gateway) —
without modifying any of that repo's own source, plus a Grafana dashboard and a randomized
load generator. See [tick-x/README.md](tick-x/README.md).
