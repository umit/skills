# Reading flame graphs

How to read the HTML/SVG flame graphs async-profiler produces. Skim this before suggesting interpretations to the user.

## Anatomy

- **Y-axis:** stack depth. Bottom = entry points, top = leaf calls.
- **X-axis:** sample count, **alphabetically merged** — NOT a timeline. Two adjacent frames are not temporally adjacent.
- **Width of a frame** = number of samples where that frame appeared on the stack. Wider = more time spent there (or in something it called).
- **A frame on top of another** = the upper was called by the lower.

## Color semantics (async-profiler default palette)

| Color | Meaning |
| --- | --- |
| Green | Java method (interpreted or JIT-compiled) |
| Yellow | C++ (HotSpot/JVM internals) |
| Red | Native (system calls, JNI, stdlib) |
| Blue | Kernel frame |
| Aqua / cyan | Inlined Java method |
| Brown / dark green | Class init / static block |

**Color is by frame type, not severity.** A wide red frame means lots of time in native code, not "error". Often it's `epoll_wait`, `read`, or `gettimeofday`.

## What to look for

### 1. Wide plateaus near the top
Direct hotspots — methods that are themselves expensive. Optimize these first.

### 2. Wide trunks at the bottom calling many narrow children
Generic infrastructure (Tomcat, Netty event loop) — usually not actionable. Look up the stack to where your code dominates.

### 3. Gaps / unattributed `[unknown_Java]`
Stack-walker failure. Usually means:
- Inlining + missing `-XX:+DebugNonSafepoints`.
- Stripped JDK without symbols.
- Native frames without DWARF — try `--cstack dwarf`.

### 4. Many narrow frames with same name in different stacks
Polymorphic call site or a hot method called from many paths. Search by name to see total cost.

### 5. Tall stacks with mostly framework
Reflection, proxy, AOP — search for your code's package to see real work.

## Search & navigation

- **Ctrl-F (or click "Search"):** highlights matching frames by regex; sums them in the bottom bar (e.g., `12.3% matched`).
- **Click a frame:** zoom in. The frame becomes the new "100%". Useful to focus on one subtree.
- **"Reset zoom":** return to full graph.
- **Reversed (icicle) graph:** `asprof -r ...` — flip to look top-down. Useful when you know the leaf method and want to find callers.
- **`--minwidth <px>`:** hide frames narrower than N pixels. Cuts noise on wide datasets.

## Differential flame graphs

Compare two profiles to see what changed:

```bash
jfrconv --diff baseline.jfr current.jfr diff.html
```

- Red frames = sample count increased (regression).
- Blue frames = sample count decreased (improvement).
- Width = absolute sample count in `current.jfr`.

**Use when:** validating an optimization, post-deploy regression hunt, A/B comparing config changes.

## Per-thread / per-state graphs

```bash
asprof -e wall -t -d 60 -f wall.html <pid>
```

The `-t` flag splits the graph: each thread (or thread group, depending on async-profiler version) gets its own block. Useful when:
- Only some threads stall (e.g., one HTTP worker pool).
- Background threads (GC, JIT) dominate aggregate but aren't your problem.

## Common pattern recognition

| Pattern | Likely cause | Action |
| --- | --- | --- |
| Wide `Object.<init>` / `ArrayList.add` | High allocation rate | Switch to `alloc` event; pool, reduce allocations |
| Wide `Unsafe.park` (in `wall`) | Threads waiting | Check `lock` event; investigate executor sizing |
| Wide `epoll_wait` / `kqueue_wait` | Idle event loop | Often benign — workload may be IO-bound |
| Wide `JIT::CompileBroker::compile_method` | JIT warmup | Wait for steady state, or pre-warm |
| Wide `G1GC::*` / `Shenandoah::*` | GC dominates | Switch to `alloc` event; tune heap |
| Wide `Reflection.invoke` | Hot reflection | Cache `MethodHandle`s, use codegen |
| Wide `String.equals` / `HashMap.get` | Hot map lookups | Profile keys; switch to `Object2ObjectHashMap`, perfect-hash, or interning |
| Wide `Pattern.matcher` | Regex compile in hot path | Cache compiled `Pattern` |
| Wide `ConcurrentHashMap.computeIfAbsent` | Contention on a hot key | Pre-fill, partition, or switch data structure |
| Wide `Logger.log` | Logging in hot path | Lower level, use lazy suppliers, structured async appender |

## Gotchas in interpretation

- **Width is relative.** A 10% frame in a 30-second profile is 3 seconds of CPU. The same 10% over 30 minutes is 3 minutes. Always know the duration.
- **`[unknown]` ≠ broken.** Sometimes it's interpreter or JIT compile-time stacks that the unwinder can't attribute. Small fractions are normal.
- **`cpu` graph ≠ wall-clock graph.** A method that mostly waits won't appear wide in `cpu`; switch to `wall` to see it.
- **Self vs total.** Default flame graph shows self-time width (frame is at top of stack). With `--total`, width = total time including children. Different lens for different questions.
