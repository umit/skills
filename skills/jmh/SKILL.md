---
name: jmh
description: Write Java microbenchmarks with JMH (Java Microbenchmark Harness) that produce trustworthy numbers — not numbers distorted by JIT dead-code elimination, constant folding, insufficient warmup, or single-fork JIT contamination. Use this skill whenever the user writes `@Benchmark`, mentions JMH, microbenchmark, throughput measurement, latency measurement, or compares two implementations performance-wise. Triggers on `@Benchmark`, `@Setup`, `@State`, `Blackhole`, `@Fork`, `@Warmup`, `@Measurement`, `@OperationsPerInvocation`, `Mode.Throughput`, `Mode.AverageTime`, `Mode.SingleShotTime`, `Mode.SampleTime`, `BenchmarkMode`, `OutputTimeUnit`, `BenchmarkRunner`, `jmh-core`, `jmh-generator-annprocess`, `org.openjdk.jmh`, `me.champeau.jmh` (Gradle plugin), `pl.allegro.tech.build.axion-release`, `JMHTask`. Treat any benchmark without `Blackhole.consume()`, with `@Fork(0)`, or with `@Warmup(iterations < 5)` as broken by default — pre-flight statically before running. Pair with `async-profiler` (`-prof async`) for per-benchmark flame graphs to answer not just "which is faster" but "why".
---

# JMH — trustworthy Java microbenchmarks

## Workflow

1. **Pre-flight before running** — read `references/pitfalls.md` and apply its 15-point checklist to the benchmark source. Catch DCE, constant folding, missing `Blackhole`, `@Fork(0)`, `@Warmup < 5`, `final` constants in the op, missing `@State`, raw loops without `@OperationsPerInvocation`. Most "fast" results come from broken benchmarks; catching this before running saves hours.
2. **Identify the build system** — Maven (`pom.xml` with `jmh-core`) or Gradle (`me.champeau.jmh` plugin). Setup differs; running differs. See `references/maven.md` or `references/gradle.md`.
3. **Pick the right `Mode`** — `Throughput` for ops/sec, `AverageTime` for ns/op, `SingleShotTime` for cold-path / startup, `SampleTime` for distribution (p50/p99). Wrong mode → wrong question answered. See `references/modes.md`.
4. **Write the benchmark** — annotate class with `@State(Scope.Benchmark)`, `@BenchmarkMode`, `@OutputTimeUnit`, `@Fork(value=3, jvmArgs={"-Xmx2g","-Xms2g"})`, `@Warmup(iterations=5)`, `@Measurement(iterations=10)`. Every `@Benchmark` method either returns a value or takes a `Blackhole` parameter. Use `@Param` for matrices instead of separate methods.
5. **Re-check the source against the checklist** after edits.
6. **Run with profilers attached** — never run benchmarks without `-prof gc` (allocation rate context) and ideally `-prof async:output=flamegraph` (flame graph per benchmark). See `references/profilers.md`.
7. **Output JSON** (`-rf json -rff results.json`) — never trust the console table alone; JSON is what diffing and visualization tools consume.
8. **Analyze** — drag `results.json` to https://jmh.morethan.io for charts, or use Bencher/Codspeed in CI for continuous diff. See `references/analysis.md`.
9. **Report with confidence intervals** — JMH prints `Score ± Error (99.9%)`. Two means are *not* different if their confidence intervals overlap. Don't claim "10% faster" inside the noise band.

## Quick reference

```bash
# Maven — build + run a single benchmark class
mvn clean verify -DskipTests
java -jar target/benchmarks.jar MyBench -wi 10 -i 10 -f 3 -prof gc -rf json -rff result.json

# Gradle (me.champeau.jmh plugin) — run all benchmarks in jmh source set
./gradlew jmh

# Run only matching benchmarks (regex)
java -jar target/benchmarks.jar 'com\.acme\..*Hash.*'

# Profile per-benchmark with async-profiler
java -jar target/benchmarks.jar MyBench -prof async:output=flamegraph;dir=profiles
```

## Common modes

| Mode | Unit | When |
| --- | --- | --- |
| `Throughput` | ops/time | "how many per second" — default for hot-path code |
| `AverageTime` | time/op | "how long per call" — typical for latency-sensitive ops |
| `SampleTime` | time/op (sampled) | distribution incl. p50/p95/p99 — outlier-aware |
| `SingleShotTime` | time/op (one-shot, no warmup-loop) | cold start, init code, single-event measurement |

## References

| File | When to read |
| --- | --- |
| `references/intro.md` | **Read first** — what JMH is, why naive benchmarks lie, minimal example, how to read the score table + GC columns + percentiles, golden-default checklist |
| `references/pitfalls.md` | Always before reviewing/writing a benchmark — 15 antipatterns (DCE, constant folding, false sharing, etc.) + 15-point pre-flight checklist + minimal correct template |
| `references/maven.md` | Maven `pom.xml` setup, archetype, run command, multi-module projects |
| `references/gradle.md` | `me.champeau.jmh` plugin config, `jmh {}` block, source set, IDE integration |
| `references/modes.md` | Mode + State + Scope + `@OperationsPerInvocation` deep dive |
| `references/profilers.md` | `-prof gc`, `-prof async`, `-prof perfasm`, `-prof jfr`, `-prof stack` — when to use which |
| `references/analysis.md` | JSON schema, `jmh.morethan.io`, statistical interpretation, CI integration (Bencher, Codspeed) |

## Output format

- Raw run: console table + `result.json` (always emit JSON with `-rf json -rff`).
- For sharing: upload JSON to https://jmh.morethan.io and share the URL.
- For CI: integrate with Bencher (`bencher run`) or Codspeed (`codspeed run`); both have JMH adapters.
- For deep analysis: pair with `async-profiler` JFR per benchmark; render flame graphs with `jfrconv`.
