# credo_perf

Credo checks for per-request cost in Phoenix and Plug applications. Each one encodes a measurement
taken while porting a Rails application to Elixir, not a style preference.

## Checks

| id | check | what it catches | measured |
|---|---|---|---|
| CP1001 | `SystemGetEnvOutsideConfig` | `System.get_env/1,2`, `System.fetch_env/1`, `System.fetch_env!/1`, `:os.getenv/1` outside `config/`, `test/`, `rel/`, `mix.exs` | 10.5 µs per call under a VM-global lock; 8 processes scale only 6.0× ⇒ ~95k calls/s node-wide |
| CP1002 | `EtsTableWalkForEviction` | `:ets.tab2list/1`, `:ets.foldl/3`, unbounded `:ets.select/2` | four processes parked in `tab2list` during a load run; posting 676 → 810–1,750 req/s once eviction used an ordered index |
| CP1003 | `SplitCacheAdmission` | a module that inserts into ETS and accounts for bytes with `:counters` in separate steps | concurrent admissions exceed the bound and miscount replacements; a review called exactly this "separate operations across request processes" |
| CP1004 | `ProcessDictionaryCacheInPlug` | `Process.put/2` in a module that defines `call/2` | Bandit and Cowboy serve each request in a new process: 0% hit rate, one miss per request |

## Deliberately not checks

A `GenServer.call` inside a Plug is *not* a rule. Whether it costs anything depends on three things a
single-file AST cannot see: whether the call is on the hot path, whether the callee is a singleton or a
partitioned pool, and whether it dominates a request that is otherwise cheap. In the port these checks
come from, a per-request `GenServer.call` to a two-partition reader pool was tried against three
alternatives (a NIF, a dedicated pool, a TTL cache) and **kept**: the alternatives were slower or
weaker, and the call accounts for about 10% of a cache hit. Measure, then decide.

## Naming

`Credo.Plugin` is for extending the Credo CLI; checks are separate. The conventions this package
follows:

- package `credo_<focus>` (`credo_perf`);
- modules under the package's own namespace, `CredoPerf.Check.<Category>.<Name>`, so they cannot collide
  with future built-ins under `Credo.Check.*`;
- a unique `id:` per check (`CP1001`), because `.credo.exs` disables checks by id;
- `category: :warning`, `base_priority:` one of `:higher | :high | :normal | :low | :ignore`.

## Usage

```elixir
# mix.exs
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:credo_perf, path: "../credo_perf", only: [:dev, :test], runtime: false}
```

```elixir
# .credo.exs
checks: [
  {CredoPerf.Check.Warning.SystemGetEnvOutsideConfig, []},
  {CredoPerf.Check.Warning.EtsTableWalkForEviction, []},
  {CredoPerf.Check.Warning.SplitCacheAdmission, []},
  {CredoPerf.Check.Warning.ProcessDictionaryCacheInPlug, []}
]
```

Without wiring Credo up, a directory can be scanned directly:

    MIX_ENV=test mix run -e 'CredoPerf.Scan.run("path/to/lib")'

## Result on the codebase these came from

98 files, 34 issues: 32 × CP1001 (real — that port converted only some modules to a boot-time
environment map), 1 × CP1002 and 1 × CP1003 in `db/connection.ex` (benign: statement-cache cleanup and
writer bookkeeping, not eviction or cache admission), 0 × CP1004. No misses on the patterns that were
fixed: neither cache walks its table any more.
