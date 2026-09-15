# CLAUDE.md

Guidance for coding agents (Claude Code, Codex, …) and maintainers working in this repository.
`AGENTS.md` is a symlink to this file so every agent reads the same instructions.

## What this project is

`prom` is a [KDB-X module](https://code.kx.com/kdb-x/modules/module-framework/overview.html) that
exposes metrics from a KDB-X process to Prometheus. It does three things:

1. **A Prometheus-client-style metric API** — `create` a `counter`, `gauge`, `histogram` or `summary`
   with optional labels, then `inc`/`incr`/`dec`/`decr`/`setv`/`obs` it from your own code. Labels are
   dictionaries validated against the definition; operations are validated against the metric type.
2. **Opt-in instrumentation of the `.z.*` event handlers** — `enableInstHdlr` wraps the handlers you
   name and maintains a standard set of request-count, request-duration and memory metrics. Hooks can be
   swapped with `overRideInstHdlr`; arbitrary logic can be stacked with `overLoadHdlr`.
3. **A `/metrics` HTTP endpoint** — served from `.z.ph` in Prometheus text exposition format.

Version 2 is a rewrite of the 1.x scripts (`q/exporter.q`, `q/extract.q`, `.prom.*` globals) that
targeted kdb+ 3.x/4.x. The module was developed in an internal KX use-case repo and lifted here in
September 2026. **This repository is canonical from 2.0.0**; the internal copy is frozen and must not
receive back-ports. The 1.x line lives at tag
[`1.0.1`](https://github.com/KxSystems/prometheus-kdb-exporter/tree/1.0.1) and is not maintained.

## Repo structure

```
prometheus-kdb-exporter/
├── prom/                      ← the module; loaded with prom:use`prom
│   ├── init.q                 ← loads the other two files, defines `export` (the public contract)
│   ├── prom.q                 ← metric model, validation, update APIs, serving, overLoadHdlr
│   └── evhdlr.q               ← default metrics and the .z.* wrappers/hooks, enableInstHdlr
├── tests/t.q                  ← `t)` assertion suite; run from the repo root with QPATH=$PWD
├── docs/
│   ├── reference.md           ← prom.* API reference (argument tables + verified sample output)
│   ├── event-handlers.md      ← enableInstHdlr / overRideInstHdlr / overLoadHdlr, default metric table
│   ├── migration.md           ← 1.x → 2.x guide (API mapping table, behavioural changes)
│   ├── examples.md            ← Docker/Grafana walkthrough
│   └── README.md
├── examples/
│   ├── exporter.q             ← defaults-only runner: QPATH=$PWD q examples/exporter.q -p 8080
│   ├── kdb_user_example.q     ← load generator that also defines custom metrics over IPC
│   └── DockerCompose/         ← pinned Prometheus + Grafana, provisioned dashboard
├── .claude/skills/prom-migrate/  ← Claude Code skill for 1.x → 2.x migrations
│   └── references/api-mapping.md ← the mapping table (duplicated in docs/migration.md, KEEP IN SYNC)
├── install.sh, install.bat    ← copy prom/ onto the module search path (ask q for .Q.m.SP)
├── .github/workflows/build.yml ← packages prom/ docs/ examples/ into release tarballs on GitHub Release
├── CHANGELOG.md               ← Keep-a-Changelog
├── CONTRIBUTING.md, README.md, LICENSE (Apache-2.0)
└── CLAUDE.md, AGENTS.md → CLAUDE.md
```

## Module boundaries

- **The `export` dict in [prom/init.q](prom/init.q) is the public contract.** It currently exposes
  `create` `inc` `incr` `dec` `decr` `setv` `obs` `del` `init` `metrics` `metricMeta` `overLoadHdlr`
  `enableInstHdlr` `overRideInstHdlr` `serve`. Adding, removing or changing the signature of any of these
  is a contract change: update [docs/reference.md](docs/reference.md), add a CHANGELOG entry, and say
  so in the commit message.
- **Keep the two-file split.** `prom.q` owns the metric table, validation, update paths and the text
  serialiser. `evhdlr.q` owns the default metric definitions, the handler wrappers and the hook
  functions. Default metrics are created only when `enableInstHdlr` is first called, never at load.
- **Metric names, label keys and the env vars (`METRICS_ENDPOINT`, `CACHELENGTH`) are contracts too.**
  Dashboards and alert rules depend on them. Renaming a default metric is a *Breaking* entry, even when
  the new name is more spec-compliant. `promtool` lint warnings about the inherited 1.x names
  (`*_histogram_seconds`, `*_summary_seconds`, `kdb_handles_total`) are known and accepted.
- **One deliberate load-time side effect.** `use` replaces `.z.ph` so the endpoint is live immediately,
  chaining to any handler that existed before. Nothing else happens until the host calls
  `enableInstHdlr`. Do not add further load-time effects; put them behind an explicit call.
- **The migration table lives in two places** — [docs/migration.md](docs/migration.md) and
  [.claude/skills/prom-migrate/references/api-mapping.md](.claude/skills/prom-migrate/references/api-mapping.md).
  Both carry a `KEEP IN SYNC` comment. Edit both or neither.

## Conventions for q code

- Flat private namespace per file; no `\d`. Module globals are mutated with `::`. Sibling files load with
  `\l ::file.q` (module-relative), never a bare or absolute path.
- Inside qSQL statements within the module, reference module functions as `.z.m.fn` (e.g.
  `.z.m.updDict`, `.z.m.updVal`) — qSQL resolves bare names at root, not in the module namespace.
- Every top-level statement that returns a value ends with `;`, otherwise it echoes at `use` time.
- Output must satisfy the
  [Prometheus text exposition format](https://prometheus.io/docs/instrumenting/exposition_formats/):
  `quantile="…"` for summaries, `le="+Inf"` for the overflow bucket, `_sum`/`_count` series, and a
  terminating newline. Validate with `promtool` (see Testing).
- Every exported function has a section in [docs/reference.md](docs/reference.md) with an argument table
  and sample code that was actually run.

## q gotchas surfaced in this repo

Landmines we have stepped on here. Check the list before "simplifying" the code that guards against them.

- **`:` applied as a function returns an atom; `+`/`-` on a one-element list return a list.** `updVal`
  applies the caller's operator as `x[z;y]`. With `setv` the result was an atom, so a gauge set before
  any other metric turned the `val` column into a simple float list and the next `create` (including
  `enableInstHdlr`'s defaults) failed with `'type`. The guard is `enlist (),x[z;y]` — keep the `(),`.
- **Mixing `0i` initial values with long increments gives a mixed-type list.** Histogram buckets
  initialise as longs (`#0`, not `#0i`) so bucket counts stay a simple list.
- **`type each` on a simple list returns atom types (`-7h`), not the list type (`7h`).** Use `type` on
  the list itself when asserting column types in tests.
- **The default module search path (`.Q.m.SP`) is resolved relative to the KDB-X runtime**, e.g.
  `~/.kx/mod` for a user install; `QHOME` is no longer required. Do not hard-code `$QHOME/mod` in docs
  or scripts: `install.sh` asks q for the path, and development uses `QPATH=<repo root>`.
- **`after_*` hooks are triadic (`[tmp;msg;res]`), `on_*` and `before_*` are monadic.** Overriding an
  `after_*` hook with a one-argument lambda gives `'rank` on the next request, not at override time.
- **`x)` at the start of a line dispatches to `.x.e`.** That is how the `t)` assertions in
  [tests/t.q](tests/t.q) work: `.t.e:{if[not value x;-1 x]}` prints the expression only when it is false.
- **A missing trailing newline in the served text is invisible in most tests.** Writing `serve[]` to a
  file with `0:` adds one; the HTTP response does not. `promtool` rejects it with "unexpected end of
  input stream". Always validate over a real `curl`.
- **q is right-to-left.** `i+1 >= n` is `i + (1 >= n)`. Parenthesise compound expressions.

## Testing

```bash
# unit/integration assertions - silent output and exit 0 means pass
QPATH=$PWD q tests/t.q -q </dev/null

# exposition format, over real HTTP
QPATH=$PWD q examples/exporter.q -p 8080 &
curl -s localhost:8080/metrics | docker run --rm -i --entrypoint promtool prom/prometheus:v3.5.0 check metrics
# exit 3 = lint warnings only (expected, see Module boundaries); exit 1 = parse error (fix it)

# end-to-end demo: Prometheus target `up`, Grafana dashboard provisioned
docker compose -f examples/DockerCompose/docker-compose.yml up
```

Add a `t)` assertion for every behaviour you change, in [tests/t.q](tests/t.q). When a test overrides
hooks, match the arity (see gotchas). There is no CI test job because running q needs a KDB-X licence;
tests are run locally before pushing and the PR description says so.

## Release model

Single public repository, no mirror. `master` on `KxSystems/prometheus-kdb-exporter` is canonical.

- Work on a branch, open a PR against `master`. External contributors fork and PR.
- User-visible changes get a bullet under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md) in the same
  commit. Internal refactors and test-only changes do not.
- Semver: a change to the `export` dict, a default metric name or label key, or an env var is **major**;
  new API or new default metrics are **minor**; everything else is **patch**. Tags have no `v` prefix
  (`1.0.0`, `1.0.1`, `2.0.0`).
- There is no version number in the code. The tag and the CHANGELOG heading are the only places a
  version appears, so a release is a CHANGELOG edit plus a tag plus a GitHub Release.

### Cutting a release

Needs write access to `KxSystems/prometheus-kdb-exporter`. [build.yml](.github/workflows/build.yml)
builds the archives on every push to `master` but only **uploads them to a release when a GitHub
Release is created** (`on: release: types: [created]`), and both jobs are gated on
`github.repository == 'KxSystems/prometheus-kdb-exporter'`, so nothing below can be rehearsed on a fork.

1. **Preconditions on `master`**: `QPATH=$PWD q tests/t.q -q </dev/null` is green; the served text
   parses with `promtool`; `docs/reference.md` matches the `export` dict; every user-visible change since
   the last tag has a bullet under `[Unreleased]` (`git log <last-tag>..master` is the checklist).
2. **Edit `CHANGELOG.md`** on a release branch:
   - rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` (for 2.0.0 the heading already reads
     `## [2.0.0] - unreleased`; replace `unreleased` with the date);
   - change the bottom link `[X.Y.Z]: .../compare/<prev>...master` to `.../compare/<prev>...X.Y.Z`;
   - add a fresh empty `## [Unreleased]` above it with a link `[Unreleased]: .../compare/X.Y.Z...master`.
3. **PR and merge** that change to `master` (`gh pr create`, review, `gh pr merge --squash`).
4. **Tag and release** from the merge commit:
   ```bash
   git checkout master && git pull
   git tag -a X.Y.Z -m "X.Y.Z"
   git push origin X.Y.Z
   # release notes = the X.Y.Z section of CHANGELOG.md, extracted to a file
   gh release create X.Y.Z --title "X.Y.Z" --notes-file /tmp/notes-X.Y.Z.md
   ```
   Creating the release triggers `build.yml`, which attaches
   `prometheus-exporter-{linux,macos,windows}-X.Y.Z.{tgz,zip}`.
5. **Verify**: `gh run list --workflow build.yml --limit 1` is green and
   `gh release view X.Y.Z` lists three assets. Download one and check it contains `prom/`, `docs/`,
   `examples/`, `CHANGELOG.md`, `install.sh` or `install.bat`.
6. **Announce** in the PR or issue that prompted the release, and close any issues the CHANGELOG bullets
   reference.

If the workflow fails after the release exists, fix it on `master`, then re-run the failed job from
the Actions tab (or `gh run rerun <id>`); do not delete and recreate the tag.

## Before committing

1. `QPATH=$PWD q tests/t.q -q </dev/null` is green. Touched serving? `promtool` parses the live output.
2. A test covers the behaviour you changed.
3. Changed the `export` dict, a metric name, a label key or an env var? Update
   [docs/reference.md](docs/reference.md) and/or [docs/event-handlers.md](docs/event-handlers.md), add a
   *Breaking* or *Changed* CHANGELOG bullet, and name the contract change in the commit message.
4. Change affects how a 1.x user migrates? Update [docs/migration.md](docs/migration.md), the skill's
   `api-mapping.md`, and the skill body together.
5. User-visible change? Bullet under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
6. Structural or ways-of-working change? Update this file.
7. Write commit bodies with `git commit -F <file>` or one `-m` per paragraph so newlines are real. One
   concern per commit.

## Agent skills

- [.claude/skills/prom-migrate/](.claude/skills/prom-migrate/SKILL.md) ships with this repo and applies
  the 1.x → 2.x migration procedure to a codebase.
- For q and KDB-X language guidance, install the `q-knowledge` and `kdbx-knowledge` plugins from
  [KxSystems/kx-skills](https://github.com/KxSystems/kx-skills).

## External references

- Prometheus: [exposition formats](https://prometheus.io/docs/instrumenting/exposition_formats/),
  [writing exporters](https://prometheus.io/docs/instrumenting/writing_exporters/),
  [metric and label naming](https://prometheus.io/docs/practices/naming/),
  [client library guidelines](https://prometheus.io/docs/instrumenting/writing_clientlibs/)
- KDB-X: [module framework quickstart](https://code.kx.com/kdb-x/modules/module-framework/quickstart.html),
  [`.z` namespace](https://code.kx.com/kdb-x/ref/dotz.html)
- Module structure reference: [KxSystems/taq](https://github.com/KxSystems/taq)
