# Modes, State, and Scope

Three orthogonal choices that change what a benchmark measures.

## `BenchmarkMode`

| Mode | Output | Question it answers |
| --- | --- | --- |
| `Mode.Throughput` | ops/time (e.g. ops/sec) | "How many per unit time?" — saturated workload |
| `Mode.AverageTime` | time/op (e.g. ns/op) | "How long per call on average?" — direct comparison |
| `Mode.SampleTime` | time/op + p50/p90/p95/p99/p999/p9999/max | Distribution + outliers |
| `Mode.SingleShotTime` | time/op (no warmup loop) | Cold start, init, single-event |
| `Mode.All` | all of the above | Exploratory; expensive |

Set per class or per method:
```java
@BenchmarkMode({Mode.AverageTime, Mode.SampleTime})
@OutputTimeUnit(TimeUnit.NANOSECONDS)
public class MyBench { ... }
```

**Common mistake:** picking `Throughput` then comparing two ops/sec values that differ by 5%. Variance in throughput often dwarfs that. Use `AverageTime` for direct A/B comparison.

## `OutputTimeUnit`

Always set explicitly:
- `NANOSECONDS` — nano-ops (HashMap put, primitive ops)
- `MICROSECONDS` — small object work
- `MILLISECONDS` — IO-bound, larger algorithms
- `SECONDS` — single-shot init

Default is `SECONDS` which is rarely what you want.

## `@State` and Scope

State carries data between iterations and prevents constant folding. Scope determines lifetime + sharing.

| Scope | Lifetime | When |
| --- | --- | --- |
| `Scope.Benchmark` | one instance shared by all threads | read-mostly state, large fixtures |
| `Scope.Thread` | one instance per thread | per-thread mutable state, no contention |
| `Scope.Group` | one instance per `@Group` | producer-consumer benchmarks |

```java
@State(Scope.Benchmark)
public class Data {
    int[] arr;
    @Setup public void setup() {
        arr = ThreadLocalRandom.current().ints(1000).toArray();
    }
}

@Benchmark
public int sum(Data d) {
    int s = 0;
    for (int v : d.arr) s += v;
    return s;
}
```

The `Data d` parameter signals JMH to inject the state — never instantiate state inside the benchmark.

## `@Setup` levels

| Level | Runs before each | Time included in measurement? |
| --- | --- | --- |
| `Level.Trial` | trial (one per fork) | No |
| `Level.Iteration` | iteration | No |
| `Level.Invocation` | each `@Benchmark` call | **Yes** — be very careful |

Reserve `Level.Invocation` for state that *must* be reset (e.g. queue you're measuring offer on); make it cheap (≤ benchmark cost) or accept the inflation.

```java
@Setup(Level.Iteration)
public void resetCache() { cache.clear(); }
```

## `@TearDown`

Mirror of `@Setup` with same `Level` semantics. Useful for closing resources or asserting invariants.

## `@Param`

Run the same benchmark across a parameter matrix. JMH multiplies the matrix and emits one row per combination.

```java
@State(Scope.Benchmark)
public class Bench {
    @Param({"100", "10000", "1000000"})
    int size;

    @Param({"linear", "binary"})
    String algo;

    int[] arr;

    @Setup public void setup() {
        arr = new int[size];
        Arrays.setAll(arr, i -> i);
    }

    @Benchmark
    public int find() {
        return "binary".equals(algo) ? Arrays.binarySearch(arr, 42) : linear(arr, 42);
    }
}
```

This produces 3×2 = 6 measurement rows.

**Tip:** filter at runtime with `-p size=10000 -p algo=binary` to skip combinations.

## `@OperationsPerInvocation`

If your benchmark body internally amortizes N operations (e.g., loops 1000 times for cache-warming reasons), normalize:

```java
@Benchmark
@OperationsPerInvocation(1000)
public int batched() {
    int s = 0;
    for (int i = 0; i < 1000; i++) s += compute(i);
    return s;
}
```

JMH divides reported time by 1000, giving per-op numbers comparable to non-batched benchmarks.

## `@Threads` and `@Group`

Multi-thread benchmarks:

```java
@Threads(4)
@Benchmark
public int contended(MyState s) { return s.counter.incrementAndGet(); }
```

For producer-consumer:
```java
@Group("queue")
@GroupThreads(2)
@Benchmark
public void producer(QueueState s) { s.q.offer(42); }

@Group("queue")
@GroupThreads(2)
@Benchmark
public Integer consumer(QueueState s) { return s.q.poll(); }
```

`@State(Scope.Group)` sharing is required.

## `@CompilerControl`

Force the JIT's hand for measurement-stable code:

```java
@CompilerControl(CompilerControl.Mode.DONT_INLINE)
public int target() { ... }
```

Modes: `INLINE`, `DONT_INLINE`, `EXCLUDE` (don't compile at all).

Use sparingly — usually you want realistic JIT behavior, not forced.

## `@Fork` arguments

```java
@Fork(value = 3, jvmArgs = {"-Xmx2g", "-XX:+UseG1GC"})
```

`value` = number of separate JVMs (independent samples). `jvmArgs` = passed to each forked JVM.

For comparing JVM flags: `@Fork(value = 1, jvmArgs = "-XX:+UseG1GC")` vs `@Fork(value = 1, jvmArgs = "-XX:+UseZGC")` — but better to use `@Param` over JVM args since `@Param` keeps the comparison in one report.

## Putting it together — canonical class-level template

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
        data = new int[size];
        Arrays.setAll(data, i -> i);
    }

    @Benchmark
    public int sumLoop() {
        int s = 0;
        for (int v : data) s += v;
        return s;  // returned → JMH consumes → no DCE
    }
}
```

Every line carries weight; remove any default and you risk an antipattern from `pitfalls.md`.
