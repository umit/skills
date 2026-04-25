# Workflows

Common end-to-end profiling scenarios. Each one is a recipe: symptom → events → commands → analysis.

## 1. "My service is using 100% CPU"

**Hypothesis:** CPU-bound hot method.

```bash
# Identify
PID=$(pgrep -f myapp)

# Profile 60s of CPU
asprof -e cpu -d 60 -f cpu.html $PID

# If frames look incomplete:
# Restart with -XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints
```

**Analysis:**
1. Open `cpu.html`, look for the widest plateau near the top.
2. Search (Ctrl-F) for your application package; confirm % of total.
3. Drill into widest frame — is it your code, framework, or JIT?
4. If JIT (`C2 CompilerThread`), wait for steady state, re-profile.

**Common findings:**
- Hot regex (`Pattern.matcher`) — cache compiled patterns.
- Reflection (`Method.invoke`) — switch to MethodHandles.
- HashMap collisions — check `hashCode` of keys.
- JSON parsing — switch parsers, add caching.

## 2. "Latency spikes but CPU is low"

**Hypothesis:** threads waiting on I/O, locks, or downstream services.

```bash
# Wall-clock profile, per-thread
asprof -e wall -t -d 60 -f wall.html $PID
```

**Analysis:**
1. Open `wall.html`. Frames are wide if threads spend time *anywhere*, including waiting.
2. Look for `Unsafe.park`, `epoll_wait`, `socketRead`, `LockSupport.park`.
3. Identify which thread pool / executor.

**Follow-up if `Unsafe.park` is wide:**
```bash
# Check if it's lock contention
asprof -e lock --lock 1ms -d 60 -f lock.html $PID
```

**Common findings:**
- Connection pool exhausted — check pool metrics.
- Slow downstream — check distributed traces.
- Synchronized block bottleneck — refactor to `j.u.c`.

## 3. "Young GC fires too often"

**Hypothesis:** allocation churn.

```bash
asprof -e alloc -d 120 --alloc 256k -f alloc.html $PID
```

**Analysis:**
1. Top frames in flame graph = top allocators.
2. Search for `<init>` to find constructors of churned types.
3. Look for `String`, `byte[]`, `ArrayList`, common boxers (`Integer.valueOf`).

**Common findings:**
- String concat in loops — `StringBuilder`.
- `Stream.collect(Collectors.toList())` in hot path — pre-size, use mutable.
- Logging `String.format` — use parameterized logging.
- Auto-boxing of primitives — primitive collections (Eclipse Collections, fastutil).

## 4. "Threads are stuck — deadlock or contention?"

**Step 1:** thread dump first.
```bash
jcmd $PID Thread.print > thread.dump
```

If many `BLOCKED (on object monitor)` or `WAITING (parking)`:

**Step 2:** lock profile.
```bash
asprof -e lock --lock 100us -d 60 -f lock.html $PID
```

**Analysis:**
1. Wide frames = contended monitors.
2. Stack shows the synchronized block.
3. If multiple threads converge on same monitor → contention.
4. If thread A waits on B and B waits on A → deadlock (visible in thread dump).

**Common findings:**
- `synchronized (singletonMap)` — replace with `ConcurrentHashMap`.
- Database connection pool with synchronized borrow — switch pool.
- Logging framework lock contention — async appender.

## 5. "GC pauses are longer than expected"

**Hypothesis:** time-to-safepoint problem.

```bash
asprof --ttsp -d 60 -f ttsp.html $PID
```

**Analysis:**
1. Frames represent code that delays safepoint synchronization.
2. Common culprits: long counted loops, large `Arrays.fill`, JNI without safepoint polls.

**Fix:** rewrite long counted loops to use `int` index (counted-loop optimization), break large array operations into chunks.

## 6. "I deployed an optimization — did it work?"

**Step 1:** baseline profile (before deploy).
```bash
asprof -e cpu -d 120 -f baseline.jfr $PID
```

**Step 2:** profile after deploy.
```bash
asprof -e cpu -d 120 -f current.jfr $PID
```

**Step 3:** diff.
```bash
jfrconv --diff baseline.jfr current.jfr diff.html
```

**Analysis:**
- Blue frames in your changed code = improvement (samples decreased).
- Red frames = unintended regression.
- No color in changed code = optimization had no measurable effect at this rate.

**Tip:** capture both profiles under the same load (same RPS, same input). Otherwise diff is noisy.

## 7. "Production incident — capture for postmortem"

```bash
# Continuous JFR with 1h rotation
asprof -e cpu \
       -f /var/log/profile-%t.jfr \
       loop=1h \
       $PID

# When incident occurs, dump current state without stopping
asprof status $PID
asprof -e cpu start $PID  # if not already running

# After incident, slice the JFR window
jfrconv --cpu --from "13:00" --to "13:15" /var/log/profile-*.jfr incident.html
```

## 8. "Hot path crosses Java <-> native"

**Hypothesis:** JNI overhead or native code.

```bash
# Use DWARF for stripped native libs
asprof -e cpu --cstack dwarf -d 60 -f cpu.html $PID
```

**Analysis:**
1. Look for `Java_*` JNI bridge frames.
2. Frames above are native; frames below are Java.
3. If native is hot, profile the native side with `perf` directly.

## 9. "JMH benchmark — profile the hot loop"

```bash
java -jar target/benchmarks.jar MyBench \
     -prof async:output=flamegraph;dir=profiles
```

JMH's async-profiler integration auto-profiles each iteration's hot phase, dumping flame graphs to `profiles/`.

## 10. "Compare two implementations" (A/B)

```bash
# Run impl A
java -agentpath:.../libasyncProfiler.so=start,event=cpu,file=a.jfr -jar a.jar &
# ... run workload ...

# Run impl B
java -agentpath:.../libasyncProfiler.so=start,event=cpu,file=b.jfr -jar b.jar &
# ... same workload ...

jfrconv --diff a.jfr b.jfr ab-diff.html
```

## 11. "Embedded — profile only critical section in test"

```java
@Test
void hotPath() throws Exception {
    AsyncProfiler p = AsyncProfiler.getInstance("/opt/lib/libasyncProfiler.so");
    p.execute("start,event=cpu,interval=100us");
    try {
        for (int i = 0; i < 10_000; i++) systemUnderTest.compute();
    } finally {
        p.execute("stop,file=test-flame.html");
    }
}
```

100us interval is fine for short tests; default 10ms gives few samples in <1s sessions.

## 12. "Virtual threads (Loom) — find what's pinning"

```bash
asprof -e wall -t -d 60 \
       -I 'jdk\.internal\.vm\.Continuation\..*' \
       -f pinning.html $PID
```

Frames matching `Continuation.*` are pinning carrier threads. Common causes: `synchronized` blocks holding while doing I/O, native calls.

**Fix:** replace `synchronized` with `ReentrantLock` (doesn't pin in JDK 24+; check JEP for current behavior).
