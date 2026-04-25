# Attach modes

Four ways to load async-profiler into a JVM. Choose based on lifecycle, restart constraints, and what you need to capture.

## 1. PID attach (most common)

```bash
asprof -d 30 -f profile.html <pid>
```

- **Pros:** no restart, ad-hoc, fast iteration, works on already-running prod JVMs.
- **Cons:** misses startup activity; JVMTI dynamic attach must be enabled (default-on for HotSpot, off for some hardened images).
- **Find PID:**
  - `jps -v` — lists JVMs with their start args.
  - `jcmd` — same.
  - `pgrep -f 'java.*myapp'`.
  - In Kubernetes: `kubectl exec <pod> -- jps -v`.
- **Permissions:** must be the same UID as the target. Cross-user attach requires `kernel.yama.ptrace_scope=0` (loosens ptrace) or running asprof as root.
- **Disable check:** `-XX:+DisableAttachMechanism` blocks dynamic attach. If the target was started this way, you cannot use PID attach — restart with `-agentpath` instead.

## 2. JVM agent at startup (`-agentpath`)

```
java -agentpath:/opt/async-profiler/lib/libasyncProfiler.so=start,event=cpu,file=/var/log/profile-%p-%t.jfr,interval=10ms \
     -XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints \
     -jar app.jar
```

- **Pros:** captures startup, deterministic, works in immutable infrastructure, survives JVMTI lockdown.
- **Cons:** requires restart; the `.so` (or `.dylib`) must exist on the container filesystem.
- **Common agent options:**
  - `start` / `stop` — auto-start at JVM init; stop via JVM shutdown or signal.
  - `event=<name>` — see `events.md`.
  - `file=<path>` — output file; supports format tokens:
    - `%p` — PID
    - `%t` — start timestamp
    - `%n` — sequence number (with `loop=`)
    - `%h` — hostname
  - `interval=<duration>` — sampling interval (`10ms`, `1s`, `1000us`).
  - `loop=<duration>` — rotate output every N (e.g. `loop=1h` produces hourly files).
  - `jstackdepth=<n>` — max stack frames per sample (default 2048).
  - `threads` — separate output per thread.
  - `cstack=fp|dwarf|lbr|vm|no` — native stack-walk strategy (see `pitfalls.md`).
  - `simple` — simple class names in output (no package).
  - `sig` — include method signatures.
  - `timeout=<duration>` — auto-stop after N (combine with `start`).
  - `log=<path>` — agent log file (debug attach issues).
- **Stop without restart:** send `SIGTERM` to the JVM, or use `asprof stop <pid>` to flush.

## 3. Programmatic Java API

```java
import one.profiler.AsyncProfiler;

public class Profiling {
    public static void main(String[] args) throws Exception {
        AsyncProfiler profiler = AsyncProfiler.getInstance(
            "/opt/async-profiler/lib/libasyncProfiler.so");

        profiler.execute("start,event=cpu,interval=1ms,file=/tmp/critical-section.jfr");
        try {
            criticalSection();
        } finally {
            profiler.execute("stop,file=/tmp/critical-section.jfr");
        }

        // Snapshot of accumulated counters
        String summary = profiler.execute("status");
        System.out.println(summary);
    }
}
```

- **Pros:** profile a specific code path; embed in test harnesses; expose via HTTP health endpoint for on-demand profiling.
- **Cons:** requires `async-profiler.jar` (or copy `one.profiler.AsyncProfiler` source — single file).
- **Maven:**
  ```xml
  <dependency>
    <groupId>tools.profiler</groupId>
    <artifactId>async-profiler</artifactId>
    <version>4.0</version>
  </dependency>
  ```
- **Common command strings:** any flag from the CLI works as a comma-separated `key=value` string.

See `api.md` for advanced usage (per-thread profiling, programmatic flame-graph dump, integration with Spring Actuator).

## 4. `jcmd` integration

Recent async-profiler builds integrate with `jcmd` via JFR event sources:

```bash
jcmd <pid> JFR.start name=ap settings=/path/to/profile.jfc duration=60s filename=/tmp/ap.jfr
```

- **When useful:** environments where `jcmd` is allowlisted but `asprof` isn't, or to combine async-profiler events with JFR's GC/IO events in one recording.
- **Setup:** drop `libasyncProfiler.so` into a path the JVM can `dlopen`; configure `.jfc` to enable async-profiler events.

## Decision matrix

| Scenario | Mode |
| --- | --- |
| Live prod investigation | PID attach |
| Capture startup behavior | `-agentpath` |
| Profile specific test method | Programmatic API |
| Always-on production | `-agentpath` with `loop=1h` |
| `-XX:+DisableAttachMechanism` set | `-agentpath` |
| Cross-user / sandboxed | `-agentpath` (avoids ptrace) |
| Per-request profiling | Programmatic API + per-request thread filter |
| Combined with JFR I/O events | `jcmd` integration |
| Kubernetes pod | `kubectl exec` + PID attach (ship `.so` in image or sidecar) |
| Lambda / FaaS | `-agentpath` with output to `/tmp` |

## Common attach failures

| Error | Cause | Fix |
| --- | --- | --- |
| `Could not attach to PID` | Different UID or `ptrace_scope` | `sudo asprof` or relax `kernel.yama.ptrace_scope` |
| `JVM does not support dynamic attach` | `-XX:+DisableAttachMechanism` | Restart with `-agentpath` |
| `dlopen failed: ...libasyncProfiler.so...` | `.so` not on target's filesystem | Copy `.so` into container/pod |
| `perf_event_open failed: EACCES` | Kernel paranoia | `sysctl kernel.perf_event_paranoid=1` |
| `JNI ERROR: GetEnv failed` | Wrong JDK version vs `.so` | Match `.so` to target architecture |
| Empty stacks (only `[unknown_Java]`) | Stripped JDK or aggressive inlining | Add `-XX:+DebugNonSafepoints` |
