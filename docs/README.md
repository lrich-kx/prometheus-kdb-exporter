# ![Prometheus](../prometheus.png) Prometheus Exporter


[Prometheus](https://prometheus.io/docs/instrumenting/exporters/) is free software which facilitates metric gathering, querying and alerting for a wealth of different third-party languages and applications. It also provides integration with Kubernetes for automatic discovery of supported applications.

Visualization and querying can be done through its built-in expression browser or, more commonly, via [Grafana](https://grafana.com/).

An environment being administered or analyzed by Prometheus can include current and past metrics exposed by KDB-X.


## Use cases

The following are potential use cases for the interface. This is by no means an exhaustive list.

-   effects from version upgrades (e.g. performance before/after changes)
-   alerts when your that a licence may be due to expire
-   bad use of symbol types within an instance


## KDB-X/Prometheus-Exporter integration

This interface

-   provides a module with useful general metrics that can be enabled per event handler and extended with your own
-   allows correlations between different instances, metrics, exporters and installs to be easily identified

Some caveats regarding where this interface in its current iteration can be used

-   This interface does not provide service discovery. Prometheus itself has support for multiple mechanisms such as DNS, Kubernetes, EC2, file based config, etc., to discover all the KDB-X instances within your environment.
-   You may need to define additional metrics to provide more relevant coverage for your environment. Please consider contributing if your change may be generic enough to have a wider user benefit.
-   General machine/Kubernetes/cloud metrics on which KDB-X is running. Metrics can be gathered by such exporters as the node exporter. Metrics from multiple exporters can be correlated to provide a bigger picture of your environment conditions.


## Metrics

In Prometheus _metrics_ refer to the statistics being monitored. Within Prometheus are different forms of metric. The exposure of these metrics from a KDB-X session allows for the monitoring a KDB-X process with Prometheus.

There are [four types of metric](https://prometheus.io/docs/concepts/metric_types/) in Prometheus:

```txt
counter
gauge
histogram
summary
```

These are classified as either _Single-value_ or _Aggregate_ metrics

-   Single-value metrics

    Both `counter` and `gauge` are single-value metrics, providing a number per instance.

    When updating a single-value metric (`prom.inc`, `prom.incr`, `prom.dec`, `prom.decr`, `prom.setv`), a single number is modified. On a request, this number is reported directly as the metric value.

-   Aggregate metrics

    Both `histogram` and `summary` are aggregate metrics, providing summary statistics per instance according to the parameters given when the metric was defined.

    -   A `histogram` keeps a cumulative count per bucket (`le` upper bounds from the definition, plus `+Inf`) and running `_sum`/`_count` totals. Each `prom.obs` increments the matching buckets at the time of the call, so serving is cheap regardless of observation rate.
    -   A `summary` keeps a bounded window of the most recent observations (`cacheLength`, default from `CACHELENGTH`) plus running `_sum`/`_count` totals. The configured quantiles are computed from that window each time Prometheus polls.

Each metric can carry a fixed set of label keys; every distinct label-value combination is a separate instance and is reported as a separate time series.

:point_right:
[Function reference](reference.md) · [Event handler instrumentation](event-handlers.md) · [Docker Compose example](examples.md)

## Upgrading from v1

Version 2 is a KDB-X module and replaces the `.prom` namespace API of v1. See the [migration guide](migration.md) for the mapping from `.prom.newmetric`/`.prom.addmetric`/`.prom.updval`/`.prom.init` to the new API and the list of behavioural changes.

## Status

The interface is currently available under an Apache 2.0 licence and is supported on a best-efforts basis by the Fusion team. The interface is currently in active development, with additional functionality to be released on an ongoing basis.


[Issues and feature requests](../../../issues) 

[Guide to contributing](../CONTRIBUTING.md)

