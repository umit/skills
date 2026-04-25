# JFR analysis

`jfrconv` ships with async-profiler and converts JFR recordings into flame graphs, collapsed stacks, and differential diffs. JFR is the recommended on-disk format because it's re-renderable.

## `jfrconv` basics

```bash
# CPU flame graph from JFR
jfrconv --cpu profile.jfr cpu.html

# Allocation flame graph
jfrconv --alloc profile.jfr alloc.html

# Lock-wait flame graph
jfrconv --lock profile.jfr lock.html

# Wall-clock
jfrconv --wall profile.jfr wall.html

# Differential
jfrconv --diff baseline.jfr current.jfr diff.html
```

## Common flags

| Flag | Effect |
| --- | --- |
| `--cpu` / `--alloc` / `--lock` / `--wall` | Filter by event type |
| `--threads` | Per-thread flame graphs |
| `--state <state>` | Filter by thread state (RUNNABLE, BLOCKED, etc.) for wall events |
| `--include <regex>` | Include stacks matching pattern |
| `--exclude <regex>` | Exclude stacks |
| `--simple` | Simple class names |
| `--total` | Width = total time (incl. children), not self time |
| `--reverse` | Inverted (icicle) flame graph |
| `--from <ts>` / `--to <ts>` | Time-window slice of recording |
| `--minwidth <px>` | Hide narrow frames |
| `--title <text>` | Flame graph title |
| `--diff <baseline> <current>` | Differential output |
| `-o <format>` | `flamegraph`, `collapsed`, `tree`, `flat` |

## Slicing by time

For long recordings (rotating production JFR), slice to a window of interest:

```bash
# Look at minute 5–6 of a 1-hour recording
jfrconv --cpu --from 5m --to 6m big.jfr slice.html

# Or absolute timestamp (ISO 8601 / epoch)
jfrconv --cpu --from 2026-04-25T13:30:00 --to 2026-04-25T13:31:00 big.jfr slice.html
```

This is huge for incident analysis — extract just the latency-spike window.

## Filtering

```bash
# Only stacks involving your application package
jfrconv --cpu --include 'com\.acme\..*' app.jfr app-only.html

# Exclude framework noise
jfrconv --cpu \
  --exclude 'sun\.reflect.*' \
  --exclude 'java\.lang\.reflect.*' \
  --exclude 'org\.springframework\.cglib.*' \
  app.jfr clean.html
```

Multiple `--include`/`--exclude` allowed; combined with AND/OR (include is OR; exclude is AND-NOT).

## Differential analysis

```bash
jfrconv --diff baseline.jfr current.jfr diff.html
```

- **Red frames** — sample count grew (regression).
- **Blue frames** — sample count shrank (improvement).
- **Width** — current sample count.
- **Strategy:** record baseline before a change, current after, diff. Don't interpret colors without the diff context — a "red" frame may simply mean the workload ran longer.

To normalize for duration mismatch:

```bash
jfrconv --diff --normalize baseline.jfr current.jfr diff.html
```

## Other tools that read JFR

### JDK Mission Control (JMC)
- Full event browser. Open the JFR; explore "Method Profiling", "Memory", "Lock Instances".
- Best when you need timeline view (when did the spike happen?).
- Free download from Adoptium.

### IntelliJ Profiler
- Built-in JFR viewer. Open `.jfr` directly in IDEA.
- Provides "Hot Spots", "Call Tree", "Methods List", differential view.
- Works with both `JFR.start` recordings and async-profiler JFRs.

### VisualVM
- JFR plugin available; weaker than JMC but adequate for quick views.

### JFR Query Experiments
- Web frontend for SQL-like queries over JFR files (https://github.com/parttimenerd/jfr-query-experiments).
- Use when standard JFR views are too rigid and you want ad-hoc aggregation across events.
- Lighter than JMC; runs in a browser.

### Pyroscope / Parca
- Continuous-profiling backends; ingest JFR or pprof for time-series flame graphs.

## Common JFR analysis patterns

### "Find the top 10 hottest methods"
```bash
jfrconv --cpu -o flat app.jfr | head -20
```

### "Why did p99 spike at 13:42?"
```bash
jfrconv --cpu --from 2026-04-25T13:41:30 --to 2026-04-25T13:42:30 \
        --threads app.jfr spike.html
```

### "Did our optimization help?"
```bash
jfrconv --diff before.jfr after.jfr diff.html
# Open diff.html, look for blue (improved) frames in changed code path
```

### "Which thread pool is hot?"
```bash
jfrconv --cpu --threads app.jfr per-thread.html
```

## JFR vs pure HTML output

| Capture as | Replay flexibility | File size | Use |
| --- | --- | --- | --- |
| `.html` (flame graph) | None — frozen | Small | Quick screenshot, one-off |
| `.jfr` | Full re-render with any filter | Larger | Production, incidents, archives |
| `.collapsed` | Custom scripted analysis | Smallest | Regression CI, custom tooling |

**Recommendation:** capture JFR in production and ad-hoc; render flame graphs from JFR on demand. Never capture only HTML for important sessions.

## File-size management

JFR files can grow large (~10 MB/min at default rate). Strategies:

- `loop=1h` chunked rotation — automatic size cap.
- `chunksize=100M` agent option — caps per-chunk size.
- Compress old JFRs: `gzip *.jfr` (~5x smaller).
- Trim with JMC: File → Save As → Time Range.
