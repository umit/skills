---
name: async-profiler
description: Profile JVM applications with async-profiler — sampling-based CPU, allocation, lock, wall-clock, and hardware-counter profiling that produces flame graphs, JFR, and pprof. Use this skill whenever the user investigates JVM performance, mentions hot methods or hot paths, asks about flame graphs, JFR, async-profiler, asprof, libasyncProfiler, jfrconv, or AsyncGetCallTrace, debugs allocation pressure or GC churn, hunts lock or monitor contention, traces latency spikes or time-to-safepoint issues, profiles a Java/Kotlin/Scala/Clojure process, sets up production-safe continuous profiling, or compares before/after performance with differential flame graphs. Use it even when the user only describes the symptom (e.g., "my JVM uses 100% CPU", "young GC is firing constantly", "threads are stuck") without naming the tool — async-profiler is the default JVM profiling choice over JFR-only and VisualVM.
---

# async-profiler

Low-overhead sampling profiler for JVMs (HotSpot, OpenJ9, GraalVM CE) that combines `AsyncGetCallTrace` with `perf_events` to produce accurate stack traces — including Java, JIT-inlined, native, and kernel frames.

The body below is the workflow. Detailed knowledge lives in `references/` and is loaded only when needed.

## Workflow

1. **Identify the JVM** — `jps -v`, `jcmd`, or `pgrep -f java` in a container. Confirm the workload has reached steady state; profiles taken during JIT warmup are dominated by `C2 CompilerThread` and don't reflect real hot paths.

2. **Pick the event** based on the symptom. If the user gave a symptom but not the event, choose for them and explain the choice. See `references/events.md` for the full list including hardware counters.

   | Symptom | Event |
   | --- | --- |
   | High CPU, slow throughput | `cpu` |
   | Low CPU but slow latency | `wall` (samples threads in any state) |
   | Frequent young GC, GC pressure | `alloc` |
   | Thread dump full of BLOCKED/WAITING | `lock` |
   | Memory-bound suspicion (large data scans) | hardware `cache-misses` |
   | GC pauses longer than expected | `--ttsp` (time-to-safepoint) |
   | Container without perf permissions | `itimer` (fallback) |

3. **Pick the attach mode**. See `references/attach-modes.md` for full details.

   - **PID attach** — running JVM, ad-hoc: `asprof -d 30 -f cpu.html <pid>`
   - **`-agentpath`** — captures startup; needed when `-XX:+DisableAttachMechanism` is set
   - **Programmatic API** — embed in tests, expose via internal HTTP endpoint

4. **Pick the duration**. 30–120s ad-hoc; for production use rotating JFR (`scripts/continuous-jfr.sh`). Long enough to capture steady-state behavior; short enough to keep file size manageable.

5. **Capture as JFR when possible**, render flame graphs from it. JFR is re-renderable — you can re-filter by thread, exclude packages, or diff against another recording without re-profiling. Pure HTML output is frozen.

6. **Analyze the flame graph**. Width = samples (not time). Wide plateaus near the top are direct hotspots. Wide trunks at the bottom are entry frames — drill upward to find your code. See `references/flame-graphs.md` for color semantics, search, and reading patterns.

7. **Verify the change**. After modifying code, re-profile under the same workload (same RPS, same input) and run `jfrconv --diff baseline.jfr current.jfr diff.html`. Blue frames in changed code paths confirm improvement; red signals regression.

## Quick command reference

| Goal | Command |
| --- | --- |
| 30s CPU flame graph | `asprof -d 30 -f cpu.html <pid>` |
| Allocation profile | `asprof -e alloc -d 60 -f alloc.html <pid>` |
| Lock contention | `asprof -e lock --lock 1ms -d 60 -f lock.html <pid>` |
| Wall-clock (off-CPU visible) | `asprof -e wall -t -d 60 -f wall.html <pid>` |
| Time-to-safepoint | `asprof --ttsp -d 60 -f ttsp.html <pid>` |
| Continuous start/stop | `asprof start -e cpu <pid>` ... `asprof stop -f out.jfr <pid>` |
| List events for a PID | `asprof list <pid>` |
| Convert JFR to flame graph | `jfrconv --cpu profile.jfr profile.html` |
| Differential flame graph | `jfrconv --diff baseline.jfr current.jfr diff.html` |

## Helper scripts

Located in `scripts/`. Read a script before suggesting it; each encodes safe defaults.

| Script | Purpose |
| --- | --- |
| `scripts/install.sh` | Download and install latest async-profiler for the current platform |
| `scripts/attach.sh <pid> [event] [seconds]` | One-shot attach and flame graph |
| `scripts/continuous-jfr.sh <pid> [rotate] [dir]` | Rotating JFR for production with hostname/PID-tagged output |
| `scripts/diff-profiles.sh <baseline> <current> [out]` | Differential flame graph wrapping `jfrconv --diff` |

## References

Read on demand. Each file is self-contained.

| File | When to read |
| --- | --- |
| `references/events.md` | Picking the right event; full list including hardware counters and method-tracing |
| `references/attach-modes.md` | Choosing PID-attach, `-agentpath`, programmatic API, or `jcmd` integration |
| `references/flags.md` | Complete CLI flag reference with examples |
| `references/output-formats.md` | flamegraph / jfr / collapsed / pprof / tree — when to use each |
| `references/flame-graphs.md` | Reading flame graphs: color semantics, search, differential, gotchas |
| `references/jfr.md` | JFR analysis with `jfrconv`, JMC, IntelliJ Profiler, Jeffrey |
| `references/pitfalls.md` | Inlining, container limits, kernel perms, sampling skew, virtual threads |
| `references/platform-notes.md` | Linux vs macOS vs Docker vs Kubernetes vs cloud (Lambda, Cloud Run) |
| `references/workflows.md` | End-to-end scenarios — latency spike, alloc churn, deadlock, GC, A/B compare |
| `references/api.md` | Programmatic Java API; embedding in tests and health endpoints |
| `references/integration.md` | JMH, Spring Boot, Quarkus, Pyroscope, Parca, IntelliJ, Datadog |

## Output format

When reporting profile findings to the user:

- **State the question first** — "You asked about X; here's what the profile shows."
- **Show the top frame(s)** with sample share — "`com.acme.Foo.bar` is 42% of CPU samples."
- **Explain why it's hot**, not just that it is — "It builds a regex on every call; cache the compiled `Pattern`."
- **Recommend a concrete next step** — code change, follow-up profile with a different event, or diff after the fix.
- **Link the artifact** — full path to the `.html` or `.jfr` file so the user can open it.

Avoid dumping full flame graph trees as text; the visual artifact is the deliverable.
