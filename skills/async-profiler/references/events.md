# Events reference

Every event async-profiler can sample, with semantics, overhead, and when to use it.

## CPU profiling

### `cpu` — default
- **Mechanism:** Linux `perf_event_open(PERF_COUNT_SW_CPU_CLOCK)` + `AsyncGetCallTrace`. macOS falls back to `itimer` (SIGPROF).
- **What it captures:** stacks of threads that are currently running on a CPU, including JIT-compiled Java, native code, and kernel frames.
- **Default interval:** 10 ms per CPU (configurable: `-i 1ms`).
- **Overhead:** <1% at default. Tunable lower with longer intervals.
- **Bias:** only samples on-CPU threads. Threads in `park()`, `epoll_wait()`, blocking I/O are invisible — use `wall` for those.
- **When to use:** "Where is my CPU time going?" The most-asked profiling question.

### `itimer`
- **Mechanism:** SIGPROF delivered to the running thread every N microseconds.
- **What it captures:** like `cpu` but without perf_events. Misses kernel frames.
- **When to use:** containers without `SYS_ADMIN` / `perf_event_paranoid<2`, macOS, BSD, or any environment where perf is restricted.
- **Permission-free:** works without sysctl tuning.

### `wall`
- **Mechanism:** sample a fixed number of threads at a fixed wall-clock interval, regardless of state.
- **What it captures:** total elapsed time per stack — including waiting, parking, blocking I/O, sleep.
- **Default behavior:** with `-t`, splits per thread; useful when only some threads stall.
- **Overhead:** higher than `cpu` for highly threaded apps (samples across all threads, not just on-CPU).
- **When to use:** latency analysis where threads spend time waiting. "My request is slow but CPU is at 30%."

## Allocation profiling

### `alloc`
- **Mechanism:** JVMTI `SampledObjectAlloc` callback (JDK 11+). Pre-11 falls back to TLAB instrumentation.
- **What it captures:** allocation stacks, byte counts, object counts. Both inside-TLAB and outside-TLAB.
- **Default interval:** 512 KB allocated. Tune with `--alloc 1m` (less overhead) or `--alloc 64k` (more accuracy).
- **Output frames** typically end at `Object.<init>` or the constructor of the allocated type.
- **When to use:** GC pressure, young-gen filling fast, "why are we allocating so much?"
- **Caveat:** the sampling is biased toward larger objects when interval is large. Use small intervals for short-running tests.

## Synchronization profiling

### `lock`
- **Mechanism:** JVMTI `MonitorContendedEnter` and `MonitorContendedEntered`, plus `j.u.c.Lock` instrumentation.
- **What it captures:** stacks where threads waited on contended monitors or locks. Sample weight = total time blocked.
- **Threshold:** `--lock 10ms` ignores brief contention (default is 10ns; usually you want a real threshold).
- **When to use:** thread dumps show many BLOCKED/WAITING; throughput collapses with concurrency.
- **Limitation:** captures contended waits, not uncontended lock acquisition cost.

## Hardware performance counters (Linux only)

Discoverable per-PID:
```bash
asprof list <pid>
```

### `cycles`
- CPU cycles consumed. Combine with `instructions` to compute IPC.
- **When to use:** baseline CPU-bound profiling at hardware level.

### `instructions`
- Retired instructions. IPC = `instructions` / `cycles` — low IPC (<1.0) suggests memory or branch stalls.

### `cache-misses` (and `LLC-load-misses`)
- Last-level cache misses.
- **When to use:** memory-bound suspicion. Wide frames in cache-miss graph but narrow in cycles graph means CPU stalls on memory.

### `branch-misses`
- Branch mispredictions.
- **When to use:** branchy hot code (parsing, virtual dispatch, polymorphic call sites).

### `dTLB-load-misses` / `iTLB-load-misses`
- TLB pressure. Often relieved by huge pages.

### `context-switches` (alias `cs`)
- Voluntary + involuntary context switches.
- **When to use:** scheduler pressure, oversubscribed CPU, GC threads thrashing.

### `page-faults`, `minor-faults`, `major-faults`
- Page-fault stacks.
- **When to use:** memory-mapped IO (Lucene, RocksDB), JIT code-cache thrashing, swapping.

### `cpu-clock`
- Software clock — like `cpu` but uses kernel timer instead of hardware.

## Special events

### `--ttsp` (time-to-safepoint)
- Profiles call sites that delay JVM safepoint synchronization.
- **When to use:** GC pauses or thread dumps stall longer than expected. Long counted loops, JNI calls without safepoint polls, etc.
- Requires `-XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints`.

### Method-tracing events
- `-e java.lang.String.length` — sample on entry of a specific method.
- Format: fully-qualified `class.method`, optionally with descriptor.
- **Overhead:** high for hot methods. Use `--filter <interval>` or short durations.
- **When to use:** answer "who is calling X and how often?"

## Quick decision table

| Symptom | Event |
| --- | --- |
| 100% CPU, slow response | `cpu` |
| 30% CPU but slow response | `wall` |
| Frequent young GC | `alloc` |
| Thread dump full of BLOCKED | `lock` |
| Memory-bound suspicion | hardware: `cache-misses` |
| Low IPC | hardware: `cycles` + `instructions` |
| Long GC pauses | `--ttsp` |
| Specific method invocation count | method-tracing |
| Container without perf | `itimer` |

## Combining events

You can run multiple events sequentially against the same PID — each `start`/`stop` cycle outputs its own file. async-profiler does not multiplex multiple events in one session; if you need both CPU and alloc concurrently, run two profiling sessions or use JFR (which can multiplex via JMC).
