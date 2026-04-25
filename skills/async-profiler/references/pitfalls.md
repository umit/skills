# Pitfalls and gotchas

Real-world failure modes when profiling JVMs with async-profiler. Check this list before claiming a profile is misleading.

## Inlining and stack accuracy

### Symptom: wide `[unknown_Java]` frames or methods appearing under wrong callers
**Cause:** the JIT inlines methods aggressively. Without debug info, the stack walker attributes samples to the *containing* compiled method instead of the inlined one.

**Fix:**
```
-XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints
```

Add these to the JVM start args of the *target* process. They have negligible cost and are safe in production. Without them, profiles can be subtly wrong — methods showing 0% when they're actually hot.

## Container / Kubernetes permissions

### Symptom: `perf_event_open: EACCES` or empty kernel frames
**Cause:** Linux kernel paranoia. Default `kernel.perf_event_paranoid=2` blocks unprivileged perf usage.

**Fixes (in order of preference):**
1. Set on the host: `sysctl kernel.perf_event_paranoid=1`
2. Run pod with `securityContext.capabilities.add: ["SYS_ADMIN"]`
3. Use `itimer` event instead of `cpu` — works without perf permissions but loses kernel frames
4. Use `--cstack vm` to skip native stack walking entirely

### Symptom: `kptr_restrict` blocks kernel symbol resolution
**Fix:** `sysctl kernel.kptr_restrict=0` on the host. Required to see real kernel function names instead of addresses.

### Symptom: agent fails to load (`dlopen` error) inside container
**Cause:** the `.so` isn't on the container's filesystem.
**Fixes:**
- Bake into the image: `COPY libasyncProfiler.so /opt/lib/`
- Sidecar container with shared volume containing the `.so`
- `kubectl cp` the `.so` into the pod for ad-hoc use

## Sampling skew

### `cpu` event misses off-CPU work
The `cpu` (perf-based) event only fires on threads currently running on a CPU. Threads in `park()`, `epoll_wait`, blocking I/O, or stuck in mutex waits are **invisible**.

**Fix:** use `wall` for wall-clock sampling that captures all states.

**Heuristic:** if the JVM uses 30% CPU but response times are bad, you need `wall`, not `cpu`.

### Cgroup CPU throttling
In Kubernetes with CPU limits, threads can be throttled mid-execution. This appears as "gaps" in `wall` (no thread is running) and reduces total samples in `cpu`.

**Fix:** correlate with `container_cpu_cfs_throttled_seconds_total` from cAdvisor. If throttling is high, the profile under-represents CPU-bound work.

## Allocation profiler quirks

### Sample bias toward large objects
Default sampling interval is 512 KB allocated. Objects smaller than that may be missed; very large objects appear inflated.

**Fix:** reduce interval (`--alloc 64k`) for short-running tests; accept bias for long production sessions.

### Outside-TLAB allocations look different
TLAB-allocated and outside-TLAB allocations have different stacks (the outside-TLAB path goes through slow-path code). Both are captured but stack shapes differ.

### JDK version sensitivity
- JDK 11+: full `SampledObjectAlloc` JVMTI event — accurate.
- JDK 8: TLAB-only instrumentation — misses many allocations.
- Recommendation: profile allocations on JDK 11+.

## Time-to-safepoint blindness

`cpu` and `wall` profilers can't show time spent waiting for a safepoint to be reached. If you see GC pauses longer than the actual STW work, threads are slow to yield.

**Fix:** `asprof --ttsp -d 60 -f ttsp.html <pid>` reveals the call sites delaying safepoints. Common culprits:
- Long counted loops over arrays
- JNI methods without safepoint polls
- `Arrays.fill` on huge arrays
- Hand-rolled hashing/parsing loops

## Native frames missing

### Symptom: stacks end at `Java_*` JNI bridge with no detail
**Cause:** native libraries built without frame pointers (default for production GCC builds).

**Fix:** `--cstack dwarf` uses DWARF unwinding instead of frame-pointer walking. Slower but works on stripped/optimized binaries.

For glibc / kernel: install debug symbols (`debuginfo-install glibc`, `apt install libc6-dbg`).

## JIT warmup contamination

### Symptom: profile dominated by `C2 CompilerThread`, `Interpreter`, or class init
**Cause:** profiling started before JIT compiled hot methods; samples reflect compilation, not steady-state work.

**Fix:**
- Wait until throughput plateaus before starting profile.
- For short-running benchmarks, use JMH which controls warmup.
- If you must profile cold start, separate startup-profile from steady-state-profile.

## File rotation gotchas

### Agent mode `loop=1h` doesn't rotate
**Cause:** filename lacks `%t`/`%n` token, so each rotation tries to overwrite the same file.
**Fix:** include a token: `file=/var/log/profile-%t.jfr,loop=1h`.

### Disk fills up in production
**Fix:** combine `loop=1h` with a cron/cleanup that deletes profiles older than N days. async-profiler doesn't auto-prune.

## Cross-version `.so` mismatch

### Symptom: `JNI ERROR: GetEnv failed` or JVM crash
**Cause:** wrong architecture (x64 `.so` on arm64) or major version skew between async-profiler and JVM.
**Fix:** match `.so` to target architecture. Use the latest async-profiler release; older releases may not support newer JDKs (e.g., Loom virtual threads need 3.x+).

## Virtual threads (Project Loom)

### Symptom: profile shows only carrier threads, virtual threads invisible
**Fix:** async-profiler 3.x+ has explicit virtual thread support. Older versions lump VTs into carrier threads. Check `asprof version`.

For virtual-thread-heavy apps:
- Use async-profiler ≥3.0
- `wall` event is essential — VTs spend most time parked
- `-t` shows per-carrier; for per-VT, capture JFR and slice in JMC

## Reflection / proxy noise

### Symptom: hot frames are all `sun.reflect.*` or `cglib.*`
**Cause:** Spring/Hibernate/AOP wrap your code in proxies; reflective dispatch dominates the visible stack.

**Fix:**
- Filter: `-X 'sun\.reflect.*' -X '.*\$\$EnhancerByCGLIB\$\$.*'`
- Or use `--include 'com\.yourcompany\..*'` to focus on your code
- For root-cause: switch to `--total` to see what reflection ultimately calls

## Permission elevation security

`sudo asprof` works but creates root-owned output files. Either:
- `chown` after profiling
- Use `asprof --output-dir` if available; many versions write to cwd
- Or use `setcap cap_sys_admin+ep $(which asprof)` for fine-grained perm

## Reading the wrong graph

### "Why doesn't my hot method show up?"
Possible reasons:
1. **Wrong event:** method is I/O-bound but you used `cpu`. Try `wall`.
2. **Inlined into caller:** add `-XX:+DebugNonSafepoints`.
3. **Filter too aggressive:** review `-I` / `-X` regex.
4. **Wrong PID:** confirm with `jps -v`.
5. **Steady state not reached:** profile longer.
6. **Sample count too low:** profile longer or reduce interval.
