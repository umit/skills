# Output formats

async-profiler can emit several formats — pick by who/what consumes the output.

## Flame graph (HTML / SVG)

```bash
asprof -d 60 -f profile.html <pid>
```

- **Default and most useful** — interactive, search-enabled, runs in any browser.
- HTML format includes embedded JavaScript: zoom, search (Ctrl-F), inverted (icicle), and color reset.
- SVG variant via `.svg` extension — older but works in tools that don't render the HTML inline.
- See `flame-graphs.md` for reading.

## JFR

```bash
asprof -d 60 -o jfr -f profile.jfr <pid>
```

- Java Flight Recorder format. Contains per-sample event records with timestamps, thread IDs, stack traces.
- **Consume with:**
  - `jfrconv --cpu profile.jfr profile.html` → flame graph
  - `jfrconv --diff a.jfr b.jfr diff.html` → differential
  - `jfrconv --total` → include total time vs self time
  - JDK Mission Control (JMC) — full event browser
  - IntelliJ Profiler — opens JFR natively
  - VisualVM, Java Mission Control plugin, JfrViewer (Jeffrey)
- **Why prefer JFR:** preserves per-sample data; you can re-render flame graphs later with different filters/grouping. HTML output is "baked" — you can't slice differently afterward.

## Collapsed stacks

```bash
asprof -d 60 -o collapsed -f stacks.txt <pid>
```

- One line per unique stack, semicolon-separated, with sample count.
- **Format:** `frame1;frame2;frame3 <count>`
- **Compatible with:** Brendan Gregg's `FlameGraph.pl`, custom diffing scripts, grep/awk.
- **Use when:** scripted analysis, regression tests on hot frames, custom visualizations.

```bash
# Convert to flame graph with FlameGraph.pl
asprof -d 60 -o collapsed -f stacks.txt <pid>
flamegraph.pl --color=java stacks.txt > flame.svg
```

## Tree (text)

```bash
asprof -d 60 -o tree -f tree.txt <pid>
```

- Text call tree with sample counts.
- **Use when:** terminal-only review, diffing two trees with `diff`, or piping into LLM context.
- Less information-dense than flame graphs but readable inline.

## Flat (top frames)

```bash
asprof -d 60 -o flat -f flat.txt <pid>
```

- Top hot methods sorted by self-samples.
- **Use when:** quick "what's the hottest method" answer; CI regression checks.

## pprof

```bash
asprof -d 60 -o pprof -f profile.pb.gz <pid>
```

- Google pprof binary format.
- **Consume with:** `go tool pprof`, `pprof` web UI, Pyroscope, Parca.
- **Use when:** mixed-language stack (Go + Java backend) and you want a unified pprof viewer.

## Traces

```bash
asprof -d 60 -o traces -f traces.txt <pid>
```

- All raw stack samples, one per line.
- **Use when:** custom analysis where you need each sample's full context.

## Choosing

| Need | Format |
| --- | --- |
| Quick visual review | `flamegraph` (HTML) |
| Production archival, re-render later | `jfr` |
| Diff before/after | `jfr` + `jfrconv --diff` |
| Scripted regression | `collapsed` or `flat` |
| Mixed-language tooling | `pprof` |
| Open in JMC / IntelliJ | `jfr` |
| Email / paste in PR | `flamegraph` (HTML attaches) |

## Recommended default

For most workflows: **emit JFR, render flame graphs from it.** This way you can re-run `jfrconv` later with different filters (per-thread, exclude regex, total vs self) without re-profiling.

```bash
# 1. Profile to JFR
asprof -e cpu -d 60 -f profile.jfr <pid>

# 2. Default flame graph
jfrconv --cpu profile.jfr cpu.html

# 3. Same data, allocations
jfrconv --alloc profile.jfr alloc.html  # (only if alloc was sampled too)

# 4. Per-thread
jfrconv --cpu --threads profile.jfr threads.html

# 5. Filter to one package
jfrconv --cpu --include 'com\.acme\..*' profile.jfr acme.html
```
