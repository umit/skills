# Profilers (`-prof`)

JMH ships with built-in profilers that attach during the run and append data to results. Always run with at least `-prof gc` — time alone hides allocation pressure.

## Built-in profilers

| Name | What it measures | Cost |
| --- | --- | --- |
| `gc` | Allocation rate, GC count, GC time | ~0 (uses MX beans) |
| `cl` | Class loading | ~0 |
| `comp` | JIT compilation time | ~0 |
| `safepoints` | Safepoint count + duration | low |
| `stack` | Sampled call stacks (built-in) | low |
| `perfasm` | Perf + disassembly (Linux + hsdis) | medium |
| `perfnorm` | Perf normalized to ops | medium |
| `perfc2c` | Cache-line contention (perf c2c) | medium |
| `dtraceasm` | DTrace + disassembly (macOS / Solaris) | medium |
| `jfr` | Java Flight Recorder | low |
| `async` | async-profiler | low (when libasyncProfiler.so on path) |

List on a system with: `java -jar benchmarks.jar -lprof`.

## `-prof gc` — almost always include

Adds these columns to the result:

```
Benchmark         Mode  Cnt    Score    Error   Units
sumLoop           avgt   30   42.123 ±  0.456   ns/op
sumLoop:gc.alloc.rate.norm        avgt   30   24.000 ±  0.000    B/op
sumLoop:gc.count                  avgt   30    0.000           counts
```

The crucial one is `gc.alloc.rate.norm` — bytes allocated per operation. If this is non-zero where you expected zero, your benchmark allocates somewhere unexpected (autoboxing, varargs, lambda capture, iterator).

```bash
java -jar benchmarks.jar MyBench -prof gc
```

## `-prof async` — flame graph per benchmark

Requires async-profiler library available; JMH passes `libPath=...` if not on default search.

```bash
# CPU flame graph per benchmark
java -jar benchmarks.jar MyBench \
  -prof async:output=flamegraph;dir=profiles

# JFR for re-rendering later
java -jar benchmarks.jar MyBench \
  -prof async:output=jfr;dir=profiles

# Allocation flame graph
java -jar benchmarks.jar MyBench \
  -prof async:event=alloc;output=flamegraph

# Multiple options
java -jar benchmarks.jar MyBench \
  -prof "async:libPath=/opt/async-profiler/lib/libasyncProfiler.so;output=flamegraph;event=cpu;simple=true"
```

Output: `profiles/MyBench.method-CPU-flamegraph.html` per benchmark method.

**Why this matters:** time tells *how slow*, flame graph tells *why*. Without async, you guess. With it, you see hot frames per benchmark — orders of magnitude better diagnosis. See `references/async-correlation.md` (in `async-profiler` skill) for deep dive.

Cross-link: pair this skill with `umit/skills/async-profiler` for flame-graph reading guidance.

## `-prof jfr` — JFR alternative

Lighter-weight than async, ships with the JDK. Useful when you can't deploy async-profiler:

```bash
java -jar benchmarks.jar MyBench -prof jfr:dir=jfr-out
```

Open the `.jfr` in JMC, IntelliJ profiler, or render with `jfrconv`. Less allocation-tracking detail than `-prof async`.

## `-prof perfasm` — assembly-level

When you want to know "did the JIT vectorize my loop?" or "is this inlined?":

```bash
# Linux only; needs perf + hsdis (HotSpot disassembler)
java -jar benchmarks.jar MyBench -prof perfasm
```

Output shows hot `%` per assembly instruction. Massive output; use only on a single tight benchmark.

Common gotchas:
- `hsdis-amd64.so` must be on the JDK lib path; download from https://chriswhocodes.com/hsdis/.
- Run with `-XX:+UnlockDiagnosticVMOptions -XX:+PrintAssembly` in JVM args; JMH adds these when `perfasm` is selected.
- Best for "was X loop unrolled?" — not for big-picture profiling.

## `-prof safepoints`

Hidden cost of safepoint biasing. If your benchmark sees occasional huge outliers, safepoints might be the cause.

```bash
java -jar benchmarks.jar MyBench -prof safepoints
```

Shows count + time spent at safepoint per iteration. Long safepoints often correlate with GC, biased-locking revocation, or `-XX:+UseCountedLoopSafepoints`.

## `-prof stack` — built-in sampling

Lightweight stack sampler built into JMH. Use when you can't deploy async/jfr:

```bash
java -jar benchmarks.jar MyBench -prof "stack:lines=5;period=10"
```

Output: top frames + percentages. Less detailed than async-profiler but zero-dependency.

## Combining profilers

Multiple `-prof` allowed:

```bash
java -jar benchmarks.jar MyBench \
  -prof gc \
  -prof "async:output=flamegraph;dir=profiles" \
  -prof safepoints
```

Each appends columns / produces additional artifacts.

## Choosing a profiler

```
Want allocation insight?      → -prof gc          (always)
Want flame graph?             → -prof async       (best) or -prof jfr (fallback)
Suspect outliers / pauses?    → -prof safepoints
Need assembly?                → -prof perfasm     (Linux + hsdis)
Multi-thread contention?      → -prof perfc2c     (Linux)
Can't deploy native libs?     → -prof stack       (built-in, basic)
```

## CI consideration

In CI, `-prof gc` is fine — fast, deterministic. `-prof async` produces HTML flame graphs (large) — upload as artifacts only when investigating regressions, not on every run.

```yaml
# Only profile on regression
- name: JMH (track only)
  run: ./gradlew jmh -Pjmh.profilers='gc'

- name: JMH with flame graph
  if: github.event.label.name == 'investigate'
  run: ./gradlew jmh -Pjmh.profilers='gc,async:output=flamegraph'
  - uses: actions/upload-artifact@v4
    with: { name: profiles, path: build/reports/jmh/profiles/ }
```
