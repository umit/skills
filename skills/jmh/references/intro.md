# What is JMH and why use it

## What

**JMH** = Java Microbenchmark Harness. An OpenJDK project (same team as the JVM) that runs Java code under controlled conditions so the *numbers* you measure mean something.

You don't measure with JMH because it's "fancy"; you measure with it because **measuring without it usually lies**.

## What is a microbenchmark

A **microbenchmark** measures a *single, isolated operation* at the nanosecond–millisecond scale: one method call, one hash, one parse, one allocation. Compare with:

| Scale | Unit per op | What it measures | Tool |
| --- | --- | --- | --- |
| **nano/micro** | ns – µs | A single function/method | **JMH** |
| **milli** | µs – ms | A single in-process operation (e.g. one query plan) | JMH or custom |
| **macro / system** | ms – s | Whole request lifecycle, HTTP endpoint, DB transaction | [Gatling](https://gatling.io), [k6](https://k6.io), [wrk](https://github.com/wg/wrk), [JMeter](https://jmeter.apache.org) |
| **load / soak** | minutes – hours | Capacity, durability under sustained traffic | k6, Gatling, Locust |

**Isolation discipline** — a microbenchmark has:
- No I/O (file, socket, DB).
- No network calls.
- No real concurrency unless that *is* the subject of the benchmark.
- Predictable inputs sized to fit in cache/heap.
- A single "thing" being measured — not a pipeline of three things.

If your "benchmark" reads from disk, calls a REST endpoint, or starts a Spring context, it's not a microbenchmark — JMH is the wrong tool. Use Gatling/k6 instead, or split into a true micro slice (mock the I/O) plus a separate macro test.

**Decision rule:** "Could I measure this with `System.nanoTime()` if I knew about JIT?" → JMH. "Does this need a real HTTP client and a running server?" → not JMH.

## Why naive benchmarks lie

```java
// DON'T DO THIS
long start = System.nanoTime();
for (int i = 0; i < 1_000_000; i++) {
    Math.log(42.0);
}
long elapsed = System.nanoTime() - start;
System.out.println(elapsed / 1_000_000 + " ns/op");
```

Problems:
1. **Dead-code elimination** — `Math.log(42.0)` result discarded; JIT removes the call entirely. You're timing an empty loop.
2. **Constant folding** — `42.0` is a compile-time constant; JIT may compute `Math.log(42.0)` once at JIT time.
3. **Warmup ignored** — first calls run interpreted (slow), then C1 (medium), then C2 (fast). Mixed measurement.
4. **JIT contamination** — running this after another benchmark in the same JVM means JIT decisions leak.
5. **GC noise** — random pause during measurement skews results.
6. **OS scheduling** — single thread on a busy machine gets descheduled mid-loop.

JMH addresses each of these systematically: forks separate JVMs, runs warmup iterations, supports `Blackhole` to defeat DCE, requires state injection to defeat constant folding, integrates GC/safepoint profilers.

## When to use JMH

- ✅ Micro-ops: hash function speed, parsing one input, single-call latency.
- ✅ A/B comparisons: "is `HashMap` or `ConcurrentHashMap` faster for my access pattern?"
- ✅ Optimization claims: "this PR makes `serialize()` 20% faster" — JMH or it didn't happen.
- ✅ Regression detection in CI (with Bencher/Codspeed integration).

## When NOT to use JMH

- ❌ End-to-end / system benchmarks (HTTP throughput, DB query latency end-to-end) → use [k6](https://k6.io), [wrk](https://github.com/wg/wrk), [Gatling](https://gatling.io).
- ❌ JVM startup time → use [hyperfine](https://github.com/sharkdp/hyperfine) or `time java ...` directly.
- ❌ "Does my test pass?" — JMH is not JUnit; benchmarks are not assertions.
- ❌ Single-shot one-off measurements where ±50% noise is fine — print `System.nanoTime()` deltas.

JMH is for the regime where 5% changes matter. Above that scale, lighter tools work.

## Minimal example — read this first

```java
package com.example;

import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.annotations.*;

@BenchmarkMode(Mode.AverageTime)            // "how long per call?"
@OutputTimeUnit(TimeUnit.NANOSECONDS)       // report in ns
@State(Scope.Benchmark)                     // shared state across threads
@Fork(value = 3, jvmArgs = {"-Xmx2g","-Xms2g"})  // 3 separate JVMs
@Warmup(iterations = 5, time = 1)           // 5 warmup iterations of 1s each
@Measurement(iterations = 10, time = 1)     // 10 measurement iterations of 1s
public class HelloBench {

    @Param({"100", "10000"})                // run twice: size=100 and size=10000
    int size;

    int[] data;

    @Setup
    public void setup() {
        data = new int[size];
        for (int i = 0; i < size; i++) data[i] = i;
    }

    @Benchmark
    public int sum() {
        int s = 0;
        for (int v : data) s += v;
        return s;                            // return → JMH consumes → no DCE
    }
}
```

Run (Maven):
```bash
mvn clean verify -DskipTests
java -jar target/benchmarks.jar HelloBench -prof gc
```

Run (Gradle with `me.champeau.jmh` plugin):
```bash
./gradlew jmh -Pjmh.includes='com\.example\.HelloBench.*'
```

## How to read the output

```
Benchmark         (size)  Mode  Cnt    Score    Error  Units
HelloBench.sum       100  avgt   30   42.123 ±  0.456  ns/op
HelloBench.sum     10000  avgt   30  4231.5  ± 12.3    ns/op
```

Column by column:

| Column | Meaning |
| --- | --- |
| `Benchmark` | Class.method name |
| `(size)` | `@Param` value for this row |
| `Mode` | `avgt` (AverageTime), `thrpt` (Throughput), `sample`, `ss` |
| `Cnt` | Total iterations across all forks (here: 3 forks × 10 iter = 30) |
| `Score` | Mean across all iterations |
| `Error` | Half-width of the 99.9% confidence interval (Student's t) |
| `Units` | `ns/op`, `ms/op`, `ops/s`, etc. |

**Crucial rule:** the *true* mean lies in `[Score - Error, Score + Error]` with 99.9% probability. So:

- `42.123 ± 0.456 ns/op` → true mean is between 41.667 and 42.579 ns/op.
- Compare to another benchmark `B = 43.0 ± 0.5 ns/op` → CI = [42.5, 43.5] → **overlaps** [41.667, 42.579] **just barely** → not statistically different.
- If `B = 50.0 ± 0.5` → CI = [49.5, 50.5] → no overlap → significantly slower.

**Never** report "Score is X% faster" unless the CIs don't overlap.

## With `-prof gc` columns

```
Benchmark                              Mode  Cnt    Score    Error   Units
HelloBench.sum                          avgt   30   42.123 ±  0.456   ns/op
HelloBench.sum:gc.alloc.rate.norm       avgt   30    0.000 ±  0.001    B/op
HelloBench.sum:gc.count                 avgt   30    0.000           counts
```

`gc.alloc.rate.norm` = bytes allocated per operation. Zero here = no allocation per call (good for hot path). Non-zero where you didn't expect it = autoboxing, varargs, lambda capture, iterator allocation hidden somewhere.

**Always read GC columns alongside time** — a benchmark that's "10% faster" but allocates 2× more usually loses under real load.

## How to read percentiles (`Mode.SampleTime` only)

```
Benchmark              Mode  Cnt    Score    Error   Units
HelloBench.sum       sample 100K   42.123 ±  0.456   ns/op
HelloBench.sum:p0.50 sample        41.000           ns/op
HelloBench.sum:p0.95 sample        45.000           ns/op
HelloBench.sum:p0.99 sample        58.000           ns/op
HelloBench.sum:p1.00 sample      1234.000           ns/op   (max — usually a GC outlier)
```

p99 is what user-perceived latency depends on, not mean. If your service SLO is "p99 < 100ms", measure with `Mode.SampleTime`, not `AverageTime`.

## Best-practice checklist (golden defaults)

1. `@BenchmarkMode(Mode.AverageTime)` for A/B comparison; `Mode.SampleTime` for distribution.
2. `@OutputTimeUnit(TimeUnit.NANOSECONDS)` (or `MICROSECONDS` for slower ops).
3. `@State(Scope.Benchmark)` on a state class with non-final fields set in `@Setup`.
4. `@Fork(value = 3, jvmArgs = {"-Xmx2g","-Xms2g"})` minimum.
5. `@Warmup(iterations = 5, time = 1)` minimum; bump to 10 for complex code.
6. `@Measurement(iterations = 10, time = 1)`.
7. Every `@Benchmark` method either **returns a value** or takes `Blackhole bh`.
8. Use `@Param` for matrices instead of N separate methods.
9. Always run with `-prof gc`.
10. Always emit JSON: `-rf json -rff result.json`.

## Recommended reading order

1. **`intro.md`** (this file) — what + why + how to read.
2. **`pitfalls.md`** — what makes results lie; the 15 antipatterns.
3. **`modes.md`** — choose the right Mode/State/Scope/Param.
4. **`maven.md` or `gradle.md`** — set up the build.
5. **`profilers.md`** — `-prof gc/async/jfr/perfasm` — when to use each.
6. **`analysis.md`** — JSON output, jmh.morethan.io, CI integration.

## Further reading

- [openjdk/jmh](https://github.com/openjdk/jmh) — source + samples.
- [JMH samples 01–38](https://github.com/openjdk/jmh/tree/master/jmh-samples) — Aleksey Shipilëv's canonical pitfall walkthroughs. Read all 38; they're each ~100 LOC and teach a single lesson.
- [Avoiding Benchmarking Pitfalls on the JVM](https://www.oracle.com/technical-resources/articles/java/architect-benchmarking.html) — Oracle article by JMH authors.
- ["JMH: The Lesser of Two Evils"](https://shipilev.net/talks/devoxx-Nov2013-benchmarking.pdf) — Shipilëv's 2013 talk, still relevant.
