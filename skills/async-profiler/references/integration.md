# Integrations

How async-profiler plugs into common JVM ecosystem tools.

## JMH (Java Microbenchmark Harness)

Built-in profiler integration:

```bash
java -jar target/benchmarks.jar MyBenchmark \
     -prof async:output=flamegraph;dir=profiles
```

Options after `async:`:
- `output=flamegraph|jfr|collapsed|tree` — output format.
- `dir=<path>` — output directory.
- `event=cpu|alloc|lock|wall` — event type.
- `interval=<duration>` — sampling interval.
- `libPath=<path>` — explicit `.so` path if not on default search.
- `width=<px>`, `height=<px>` — flame graph dimensions.
- `simpleName=true` — drop package names.

Each benchmark iteration produces a separate flame graph: `profiles/MyBenchmark.method-CPU-flamegraph.html`.

**Tip:** combine with `-prof gc` to correlate allocation rate with allocation flame graphs.

## Spring Boot

### Actuator endpoint (DIY)

Expose a `/actuator/profile` endpoint backed by the programmatic API (see `api.md`). Lock down with `management.endpoints.web.exposure.include` and `management.endpoint.profile.enabled=true` only in non-prod, or behind admin auth.

### Bean-based start/stop

```java
@Component
public class ProfilerLifecycle {
    private final AsyncProfiler profiler = AsyncProfiler.getInstance(
        "${ASYNC_PROFILER_LIB:/opt/async-profiler/lib/libasyncProfiler.so}");

    @EventListener(ApplicationReadyEvent.class)
    public void start() {
        if ("true".equals(System.getenv("PROFILE_STARTUP"))) {
            // Profile the first 60s after ready
            profiler.execute("start,event=cpu,file=/tmp/startup.jfr");
            CompletableFuture.delayedExecutor(60, TimeUnit.SECONDS).execute(() ->
                profiler.execute("stop,file=/tmp/startup.jfr"));
        }
    }
}
```

## Quarkus

Quarkus dev mode integrates with async-profiler via the Quarkus Dev UI (extension `quarkus-async-profiler` or built-in in newer versions). Native-image builds don't support agent attach — use JVM mode or fall back to `perf`.

## Micrometer / Metrics

Async-profiler isn't a metrics tool, but you can pair them:

- Trigger profiling when a metric exceeds a threshold (e.g., p99 > 500ms for 5min).
- Use Micrometer's `MeterFilter` to detect anomalies; call programmatic API to capture profile.

```java
new ScheduledTimerListener(meter -> {
    if (meter.getId().getName().equals("http.server.requests")
            && p99(meter) > 500) {
        profiler.execute("start,event=wall,timeout=30s,file=/tmp/spike-" + Instant.now() + ".jfr");
    }
});
```

## Pyroscope (Grafana)

Pyroscope ingests continuous profiling data and provides a flame-graph time-series UI.

### Push from async-profiler

```bash
java -agentpath:/opt/async-profiler/lib/libasyncProfiler.so=start,event=cpu,file=/tmp/profile-%t.jfr,loop=10s ...

# Sidecar uploads JFRs to Pyroscope
pyroscope cli upload --server http://pyroscope:4040 \
                    --app-name myapp \
                    /tmp/profile-*.jfr
```

### Pyroscope agent (alternative)

Pyroscope's Java agent embeds async-profiler and pushes directly:

```
java -javaagent:pyroscope.jar \
     -Dpyroscope.application.name=myapp \
     -Dpyroscope.server.address=http://pyroscope:4040 \
     -jar app.jar
```

## Parca

Parca is another continuous-profiling backend. Parca Agent runs as a DaemonSet and ingests profiles via eBPF + JFR.

For JVM-aware profiles, deploy Parca Agent with `--profiling-jvm-enabled` and ensure `libasyncProfiler.so` is mounted into target containers (or use JVM agent mode).

## IntelliJ IDEA / Ultimate

IntelliJ's bundled profiler uses async-profiler under the hood:

- **Run → Profile** on a configuration.
- IntelliJ controls start/stop, opens results in the Profiler tool window.
- Supports CPU, allocation, snapshot diff.
- Behind the scenes, IntelliJ ships its own `libasyncProfiler.so` — no setup required.

To use external JFRs:
- **File → Open** → select `.jfr`.
- Switch between flame graph, call tree, methods list, hotspots.

## VisualVM

VisualVM has a JFR plugin (Tools → Plugins → JFR). It can open async-profiler JFRs but with less detail than JMC or IntelliJ.

## JDK Mission Control (JMC)

Best free tool for deep JFR analysis.

- Open async-profiler `.jfr` directly.
- Method Profiling page → flame graph + tree.
- Memory page → allocations, garbage collection.
- Lock Instances page → contention.
- Timeline view to correlate with logs/metrics.

Download: https://jdk.java.net/jmc/ or via Adoptium.

## Datadog Continuous Profiler

Datadog's Java agent is a fork of async-profiler with cloud upload. If using Datadog APM:

```
java -javaagent:dd-java-agent.jar \
     -Ddd.profiling.enabled=true \
     -jar app.jar
```

Profiles appear in Datadog UI alongside traces. Doesn't require manual JFR handling.

## NewRelic Java Profiler

Similar pattern — embedded async-profiler, uploads to NewRelic. Configure via `newrelic.yml`.

## CI integration (regression detection)

GitHub Actions example:

```yaml
- name: Run benchmark
  run: java -jar bench.jar -prof async:output=jfr;dir=profiles

- name: Upload baseline
  if: github.ref == 'refs/heads/main'
  uses: actions/upload-artifact@v4
  with:
    name: baseline-profile
    path: profiles/*.jfr

- name: Diff against baseline
  if: github.event_name == 'pull_request'
  run: |
    gh run download --name baseline-profile --dir baseline
    jfrconv --diff baseline/main.jfr profiles/pr.jfr diff.html
    # Heuristic: fail if any frame regressed >10%
    python ci/check-regression.py diff.html
```

## Kubernetes operators

- **Inspectit Ocelot** — auto-instrumentation including async-profiler integration.
- **Cryostat** — Red Hat's JFR-as-a-service for OpenShift; can drive async-profiler via JMC API.

## eBPF complement

For full-stack visibility (JVM + kernel + syscalls), pair async-profiler (Java side) with BCC/bpftrace (kernel side). Examples:

```bash
# Trace all reads from JVM PID
bpftrace -e 'tracepoint:syscalls:sys_enter_read /pid == $1/ { @[comm] = count(); }' -- $JVM_PID
```

Combine timing from bpftrace with stack from async-profiler for deep system-level analysis.
