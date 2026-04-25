# Programmatic API

Embed async-profiler in Java code for per-test, per-request, or on-demand profiling.

## Loading

### Via Maven Central (recommended)

```xml
<dependency>
  <groupId>tools.profiler</groupId>
  <artifactId>async-profiler</artifactId>
  <version>4.0</version>
</dependency>
```

### Manual

Copy `lib/async-profiler.jar` (or just the `one.profiler.AsyncProfiler` source — single file) into your project. The native `.so`/`.dylib` must be on disk; it is **not** bundled in the jar.

## Basic usage

```java
import one.profiler.AsyncProfiler;

AsyncProfiler profiler = AsyncProfiler.getInstance(
    "/opt/async-profiler/lib/libasyncProfiler.so");

profiler.execute("start,event=cpu,file=/tmp/run.jfr");
// ... workload ...
profiler.execute("stop,file=/tmp/run.jfr");
```

`getInstance()` is a singleton — call once per process. Subsequent calls return the same instance.

## Command strings

The `execute(String)` method takes the same comma-separated key=value format as `-agentpath`. Any flag from the CLI works.

```java
profiler.execute("start,event=alloc,interval=64k,file=alloc.jfr");
profiler.execute("start,event=wall,threads,file=wall.jfr");
profiler.execute("start,event=lock,lockthreshold=1ms,file=lock.jfr");
```

## Status, dump, stop

```java
String status = profiler.execute("status");
// e.g. "Profiling cpu for 12s, 1234 samples\n"

// Dump current data without stopping
profiler.dumpFlat(20);  // top 20 frames as text

// Stop and write
profiler.execute("stop,file=final.jfr");
```

## Stack snapshot for a single thread

```java
String trace = profiler.dumpTraces(1);  // 1 = current thread
System.out.println(trace);
```

Useful for ad-hoc "what is this thread doing right now?" probes.

## Per-test profiling (JUnit example)

```java
public class HotPathTest {
    private static AsyncProfiler profiler;

    @BeforeAll
    static void loadProfiler() {
        profiler = AsyncProfiler.getInstance(
            System.getenv().getOrDefault(
                "ASYNC_PROFILER_LIB",
                "/opt/async-profiler/lib/libasyncProfiler.so"));
    }

    @Test
    void shouldFinishUnderBudget() throws Exception {
        profiler.execute("start,event=cpu,interval=100us");
        try {
            // Workload
            systemUnderTest.run();
        } finally {
            profiler.execute(
                "stop,file=build/profiles/" + testName() + ".html");
        }
    }
}
```

## On-demand profiling via HTTP endpoint (Spring Actuator-style)

```java
@RestController
public class ProfilingController {
    private final AsyncProfiler profiler = AsyncProfiler.getInstance(
        "/opt/async-profiler/lib/libasyncProfiler.so");

    @PostMapping("/internal/profile")
    public ResponseEntity<byte[]> profile(
            @RequestParam(defaultValue = "cpu") String event,
            @RequestParam(defaultValue = "30") int seconds) throws Exception {
        Path out = Files.createTempFile("profile-", ".jfr");
        profiler.execute("start,event=" + event + ",file=" + out);
        Thread.sleep(seconds * 1000L);
        profiler.execute("stop,file=" + out);
        byte[] body = Files.readAllBytes(out);
        Files.delete(out);
        return ResponseEntity.ok()
            .header("Content-Type", "application/octet-stream")
            .header("Content-Disposition", "attachment; filename=profile.jfr")
            .body(body);
    }
}
```

**Caution:** protect this endpoint — profiling is a debugging primitive, not a public API. Place behind admin auth, rate-limit, or expose only on internal interface.

## Per-thread profiling

```java
profiler.execute("start,event=cpu,filter,threads");
profiler.addThread(Thread.currentThread());

try {
    workload();
} finally {
    profiler.removeThread(Thread.currentThread());
    profiler.execute("stop,file=thread.jfr");
}
```

`filter` mode samples only threads explicitly added.

## Concurrent execution gotcha

Only one profiling session per JVM at a time. If you `start` while one is running, the second `start` is ignored or returns an error.

To safely wrap:

```java
public void profileSection(Runnable section, Path output) throws Exception {
    String status = profiler.execute("status");
    if (status.startsWith("Profiling")) {
        throw new IllegalStateException("Profiler already running");
    }
    profiler.execute("start,event=cpu,file=" + output);
    try {
        section.run();
    } finally {
        profiler.execute("stop,file=" + output);
    }
}
```

## Native lib path resolution

Hard-coded paths break across environments. Strategies:

```java
String lib = System.getenv("ASYNC_PROFILER_LIB");
if (lib == null) {
    // try common locations
    for (String candidate : List.of(
            "/opt/async-profiler/lib/libasyncProfiler.so",
            "/usr/local/lib/libasyncProfiler.so",
            "./libasyncProfiler.so")) {
        if (Files.exists(Path.of(candidate))) {
            lib = candidate;
            break;
        }
    }
}
if (lib == null) throw new IllegalStateException("libasyncProfiler not found");

AsyncProfiler profiler = AsyncProfiler.getInstance(lib);
```

For tests, ship the `.so` in the test classpath and extract to a temp file at startup.

## Programmatic flame graph generation

`execute("stop,file=x.html")` writes the flame graph directly. To get bytes in-memory:

```java
profiler.execute("stop");
byte[] flameGraph = profiler.dumpCollapsed(/*counter*/ 0).getBytes();
// Pipe through FlameGraph.pl for SVG, or analyze stacks directly
```

## Recording metadata

JFR output includes the command string used to start profiling. To attach business context:

```java
profiler.execute("start,event=cpu,file=run.jfr");
profiler.recordMetadata("service.version", "1.2.3");
profiler.recordMetadata("deployment.region", "us-east-1");
// ...
profiler.execute("stop,file=run.jfr");
```

(Metadata API depends on async-profiler version; verify with your release.)

## Lifecycle in long-running services

- Load lib once in app startup; store as singleton.
- Don't `dlclose` — async-profiler does not support unload-and-reload cleanly.
- Catch `IllegalStateException` from `execute()` to handle "already running" gracefully.
- For multi-tenant services, serialize profile requests with a `Semaphore` or single-threaded executor.
