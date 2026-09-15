# Example usage of Prometheus Exporter interface


The demonstration described below uses [Docker Compose](https://docs.docker.com/compose/install/) to run an instance of Prometheus and [Grafana](https://grafana.com/) to gather metrics from a KDB-X process and present them on a pre-configured interactive dashboard.

This is intended as a simple and quick way to run an environment to demonstrate the use of this interface and is not a suggestion of how an environment should be run and maintained. It is not intended as a production-ready example, only for demonstration and development.


## Requirements

- KDB-X (the `prom` module uses the KDB-X module framework; it does not load on kdb+ 4.x — see the [migration guide](migration.md))
- A Docker instance capable of running Linux containers with Internet access, e.g. Docker Desktop for Mac, Linux, or Windows (Docker Engine 20.10 or later, so `host.docker.internal` resolves on Linux as well as macOS/Windows)


## Setup

### Start the exporter

Either install the module onto the module search path following the [quick start](../README.md#quick-start), or point `QPATH` at the repository root. From the repository root, the following starts a KDB-X process on port 8080 with all of the built-in event-handler metrics enabled:

```bash
QPATH=$PWD q examples/exporter.q -p 8080
```

Once running, view the currently exposed metrics at http://localhost:8080/metrics. The metric values shown are those at the time the URL is requested.

`examples/exporter.q` is a two-line wrapper: it loads the module with `` prom:use`prom `` and calls `prom.enableInstHdlr` for every handler. Use it as a template for adding the module to your own process; the only rule is to load it *after* your own `.z.*` handlers have been defined.

### Start Prometheus and Grafana

From the `examples/DockerCompose` directory run

```bash
docker compose up
```

The first run downloads the images and takes longer; subsequent runs start in a few seconds. Prometheus is configured in `prometheus.yml` to scrape the exporter on the Docker host at `host.docker.internal:8080` every 5 seconds. To monitor multiple targets or use service discovery, refer to the Prometheus documentation.

When you have finished, press Ctrl-C in the running `docker compose` and then run

```bash
docker compose down
```

## Accessing Prometheus and Grafana

After starting the environment, Prometheus and Grafana are accessible on the ports mapped in `docker-compose.yml`:

-   Prometheus expression browser: http://localhost:9090
-   Grafana: http://localhost:3000

> For Grafana use `admin` and `pass` as the username and password.

In the Prometheus front-end, try the expression `up`. A `1` value for the `kdb` job indicates Prometheus can reach the exporter.

On logging into Grafana, a pre-configured dashboard called `kdb+` is available from *Dashboards*. It shows example metrics from the exporter on port 8080: process and heap memory, symbol count, open handles, request rates per handler type, and request-duration heatmaps built from the `kdb_*_histogram_seconds` histograms.

If Prometheus is scraping more than one exporter, use the *Server* drop-down at the top of the dashboard to switch between instances.

The files in `grafana-config` contain the provisioned data source and dashboard; edit them to change the defaults between runs.

Example dashboard (from an earlier version; the layout of the request and error panels has since changed):

![Grafana_dash](grafana_kdb_example.png)


## Example: resource utilization and custom metrics

`examples/kdb_user_example.q` connects to the exporter on port 8080 and drives it with a mix of synchronous, asynchronous, HTTP and erroring requests every second, so the built-in metrics change. It also shows the custom-metric API: over the same handle it creates a labelled gauge, a histogram and a summary on the exporter (`prom.create`) and updates them (`prom.setv`, `prom.obs`) as the load runs.

Run it from the repository root, in a second terminal, while the exporter is running:

```bash
q examples/kdb_user_example.q
```

Within a few seconds the panels on the Grafana `kdb+` dashboard start to move, and the `example_*` metrics appear at http://localhost:8080/metrics.
