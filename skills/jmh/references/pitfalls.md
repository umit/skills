# JMH pitfalls

The single most important reference. Most "fast" microbenchmark results are wrong because the JIT optimized away the work being measured. This page covers the antipatterns to scan for before every run.

Source of truth: [JMH samples 08–38](https://github.com/openjdk/jmh/tree/master/jmh-samples) by Aleksey Shipilëv.

## 1. Dead-code elimination (DCE)

If the benchmark computes a value and *doesn't use it*, the JIT proves the computation has no side effect and removes it.

**Wrong:**
```java
@Benchmark
public void measure() {
    Math.log(x);  // result discarded → eliminated
}
```

**Right — return the value:**
```java
@Benchmark
public double measure() {
    return Math.log(x);  // JMH consumes the return automatically
}
```

**Right — multi-result with `Blackhole`:**
```java
@Benchmark
public void measure(Blackhole bh) {
    bh.consume(Math.log(x));
    bh.consume(Math.log(y));
}
```

**Detection:** any `@Benchmark` method that is `void` and has no `Blackhole` parameter is suspect.

## 2. Constant folding

If inputs are `static final` or `final` compile-time constants, the JIT folds the entire computation at compile time → "0 ns".

**Wrong:**
```java
private final int x = 100;
private final int y = 200;

@Benchmark
public int add() {
    return x + y;  // folded to 300 at JIT time
}
```

**Right — load via `@State` field that's not `final`, set in `@Setup`:**
```java
@State(Scope.Benchmark)
public class MyState {
    int x, y;
    @Setup public void setup() { x = 100; y = 200; }
}

@Benchmark
public int add(MyState s) {
    return s.x + s.y;
}
```

**Detection:** `@Benchmark` body referencing `final` fields that are compile-time constants.

## 3. Loop in benchmark body

JMH already loops the call. A loop *inside* the benchmark fights with JIT loop-unrolling/vectorization differently than realistic code.

**Wrong:**
```java
@Benchmark
public int sum() {
    int s = 0;
    for (int i = 0; i < 1000; i++) s += i;
    return s;
}
```

**Right — use `@OperationsPerInvocation` if amortizing setup is needed:**
```java
@Benchmark
@OperationsPerInvocation(1000)
public int sum() {
    int s = 0;
    for (int i = 0; i < 1000; i++) s += i;
    return s;
}
```

But prefer single-op benchmarks unless you have a specific reason.

## 4. False sharing

Two threads writing to fields on the same cache line cause invisible cross-core latency.

**Wrong:**
```java
@State(Scope.Group)
public class State {
    int writerA;
    int writerB;  // likely same cache line as writerA
}
```

**Right:**
```java
@State(Scope.Group)
@jdk.internal.vm.annotation.Contended  // or sun.misc.Contended on older JDKs
public class State {
    @Contended int writerA;
    @Contended int writerB;
}
```

Run with `-XX:-RestrictContended` if `@Contended` is ignored.

## 5. JIT cross-contamination

Without `@Fork`, all benchmarks run in one JVM. JIT decisions from benchmark A poison benchmark B.

**Wrong:** `@Fork(0)` — JIT state leaks across benchmarks.
**Right:** `@Fork(value = 3)` — three separate JVMs, results averaged. Detect inter-fork variance.

## 6. Insufficient warmup

JIT goes through C1 → C2 (or Graal). If warmup is 1 iteration, you're measuring the transition.

**Wrong:** `@Warmup(iterations = 1, time = 1, timeUnit = TimeUnit.SECONDS)`
**Right:** `@Warmup(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)` minimum; `iterations = 10` for more complex code paths.

## 7. Setup time leaking into measurement

`@Setup(Level.Invocation)` runs before each invocation — its time is *included* in the measurement.

**Wrong:**
```java
@Setup(Level.Invocation)
public void setup() {
    list = new ArrayList<>();
    for (int i = 0; i < 1_000_000; i++) list.add(i);  // measured!
}
```

**Right:** use `Level.Iteration` or `Level.Trial` for expensive setup; reserve `Level.Invocation` for state that *must* be reset between calls (and make it cheap).

## 8. Wrong `Mode` for the question

- "Which is faster?" → `AverageTime` (ns/op) — direct comparison.
- "How many per second?" → `Throughput` — saturated workload.
- "What's my p99?" → `SampleTime` — outlier detection.
- "Cold path / startup?" → `SingleShotTime` — no warm loop.

Mixing modes makes comparison invalid.

## 9. Forgetting `@OutputTimeUnit`

Default is seconds for throughput and seconds-per-op for AverageTime — both unhelpful for nano-operations. Always set:
```java
@OutputTimeUnit(TimeUnit.NANOSECONDS)
```
or `MICROSECONDS` for op-scale.

## 10. Inlining contamination

Hot small methods get inlined → measured cost is "free". Large methods don't. To measure a function call cost realistically:
```java
@CompilerControl(CompilerControl.Mode.DONT_INLINE)
public int target() { ... }
```

## 11. GC noise

Default G1 introduces stop-the-world pauses → outliers in p99. For predictable measurements, force one GC mode and limit heap:
```bash
java -jar benchmarks.jar -jvmArgs "-Xmx2g -Xms2g -XX:+UseSerialGC"
```

For allocation-sensitive benchmarks: always run with `-prof gc` to see allocation rate alongside time.

## 12. Async/CompletableFuture benchmarks

Async work that completes after the benchmark returns is *not measured*. Block on the result:
```java
@Benchmark
public Object measure() throws Exception {
    return future.get();  // forces wait
}
```

Or use JMH's `@Group + @GroupThreads` for producer-consumer benchmarks.

## 13. Single-shot for I/O / JIT compile time

For "how long does the first call take", use `Mode.SingleShotTime` — no warmup, one measurement per fork.

## 14. Statistics, not "the number"

JMH outputs `Score ± Error`. If two means' confidence intervals overlap, **they are not statistically different**. Don't claim "5% faster" inside noise.

## 15. `-prof gc` is mandatory for allocation work

Time alone doesn't tell whether allocation pressure or compute is the cost. Always include `-prof gc` to see `gc.alloc.rate.norm` (bytes per op).

## Pre-flight checklist (apply mentally before each run)

1. Has `@Benchmark` annotation
2. Returns a value OR consumes via `Blackhole`
3. No `final` compile-time constants in operation
4. `@Fork` ≥ 1 (no `@Fork(0)`)
5. `@Warmup(iterations >= 5)`
6. `@Measurement(iterations >= 5)`
7. `@OutputTimeUnit` set (not default seconds)
8. `@BenchmarkMode` explicit
9. State carried via `@State`-annotated class, not benchmark fields
10. `@Setup` level appropriate (no expensive work in `Level.Invocation`)
11. No raw loops in benchmark body without `@OperationsPerInvocation`
12. Async work blocks before returning
13. JVM args include explicit `-Xmx/-Xms` for reproducibility
14. `-prof gc` in run command
15. JSON output flag (`-rf json -rff`) present

## Beyond the checklist — read the assembly?

For deep verification that the JIT didn't fold/eliminate the work you measure: run `-prof perfasm` (Linux + hsdis) and inspect the hot assembly. If the operation you wrote isn't in the disassembly, JIT optimized it away.

This is overkill for routine benchmarks but essential when results look "too good" (sub-nanosecond ops are nearly always benchmark bugs).

## Confidence-interval rule

After a run completes, before claiming "X is faster than Y":
1. Note `Score ± Error` for both.
2. Compute CIs: `[Score - Error, Score + Error]`.
3. **If CIs overlap, do not claim a difference.** Increase forks or iterations.

## What syntactic checks can't catch

A purely-syntactic scan will *not* catch:
- Subtle DCE where return-value paths don't actually use a variable.
- Constant folding through method calls (constant-fold-friendly methods like `String.length()` on a final `String`).
- False sharing across cache lines (use `@Contended`).
- JNI/native calls that bypass JIT instrumentation.
- Allocation hidden inside lambdas / streams (run `-prof gc` to catch).

So: pair the syntactic checklist *with* `-prof gc` and ideally `-prof async` flame graphs at runtime.

## Minimal correct template

```java
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@State(Scope.Benchmark)
@Fork(value = 3, jvmArgs = {"-Xmx2g", "-Xms2g"})
@Warmup(iterations = 5, time = 1)
@Measurement(iterations = 10, time = 1)
public class MyBench {

    @Param({"100", "10000"})
    int size;

    int[] data;

    @Setup
    public void setup() {
        data = ThreadLocalRandom.current().ints(size).toArray();
    }

    @Benchmark
    public int sum() {
        int s = 0;
        for (int v : data) s += v;
        return s;
    }
}
```

Run:
```bash
java -jar target/benchmarks.jar MyBench -prof gc -rf json -rff result.json
```

This passes all 15 checks.
