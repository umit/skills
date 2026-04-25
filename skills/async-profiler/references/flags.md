# Flag reference

Complete `asprof` CLI flags grouped by purpose. For agent (`-agentpath`) options, the same names apply as comma-separated `key=value`.

## Action

| Flag | Purpose |
| --- | --- |
| (default action) | One-shot profile for `-d` seconds, then dump |
| `start` | Start profiling, return immediately |
| `stop` | Stop and dump; pair with prior `start` |
| `status` | Print current profiler state |
| `list` | List supported events on the target PID |
| `version` | Print async-profiler version |
| `dump` | Dump current data without stopping |

Example: `asprof start -e cpu <pid>` … workload … `asprof stop -f profile.html <pid>`.

## Duration & sampling

| Flag | Default | Purpose |
| --- | --- | --- |
| `-d <sec>` | (none) | Run for N seconds then auto-stop |
| `-i <duration>` | `10ms` | Sampling interval (cpu/wall) |
| `--alloc <bytes>` | `512k` | Allocation sampling interval |
| `--lock <duration>` | `10ns` | Lock-wait threshold |
| `-j <n>` | `2048` | Max stack frames |
| `-s` | off | Use simple class names (drop package) |
| `-g` | off | Include method signatures |
| `-a` | on | Annotate Java methods |
| `-t` | off | Per-thread output |
| `--threads` | off | Same as `-t` |

## Event selection

| Flag | Purpose |
| --- | --- |
| `-e <event>` | Event: `cpu`, `alloc`, `lock`, `wall`, `itimer`, `cycles`, `cache-misses`, etc. |
| `-e <class.method>` | Method-tracing event |
| `--ttsp` | Time-to-safepoint event |
| `--all-user` | Sample only user-space frames |
| `--all-kernel` | Sample only kernel frames |

## Output

| Flag | Purpose |
| --- | --- |
| `-f <file>` | Output file; format inferred from extension |
| `-o <format>` | Force format: `flamegraph`, `tree`, `jfr`, `collapsed`, `flat`, `pprof`, `traces` |
| `-r` | Reverse stacks (icicle graph) |
| `--minwidth <px>` | Hide frames narrower than N px in flame graph |
| `--total` | Annotate frames with total samples (not just self) |
| `--cstack <mode>` | Native stack walking: `fp`, `dwarf`, `lbr`, `vm`, `no` |
| `--title <text>` | Flame graph title |
| `--reverse` | Reverse merge order (top-down vs bottom-up) |

### Format-by-extension shortcut

| Extension | Format |
| --- | --- |
| `.html` | flamegraph |
| `.jfr` | JFR |
| `.collapsed` / `.txt` | folded stacks (FlameGraph.pl-compatible) |
| `.pb.gz` | pprof |
| `.svg` | flamegraph (svg) |

## Stack filtering

| Flag | Purpose |
| --- | --- |
| `-I <pattern>` | Include only stacks matching regex |
| `-X <pattern>` | Exclude stacks matching regex |
| `--include <pattern>` | Long form of `-I` (alias) |
| `--exclude <pattern>` | Long form of `-X` (alias) |
| `--filter <expr>` | Filter samples by thread ID, name, or state |

Patterns are Java regex matched against any frame in the stack. Multiple `-I/-X` allowed.

Example — only HTTP request stacks:
```bash
asprof -e cpu -d 60 -I 'org\.apache\.tomcat.*' -f http.html <pid>
```

## Native stack modes

| `--cstack` | Behavior | Use when |
| --- | --- | --- |
| `fp` | Frame-pointer walking (fast, default on most targets) | Native libs compiled with `-fno-omit-frame-pointer` |
| `dwarf` | DWARF unwinder | Production binaries without frame pointers |
| `lbr` | Last-Branch Record (Intel CPUs) | High-precision short stacks; needs Skylake+ |
| `vm` | JVM internal walker | Java-only profiling, no native interest |
| `no` | Skip native | Lowest overhead, lose native frames |

## Output post-processing

| Flag | Purpose |
| --- | --- |
| `--lib <path>` | Use a different `libasyncProfiler.so` |
| `--fdtransfer <addr>` | Use fdtransfer for cross-namespace profiling (containers) |
| `--log <file>` | Agent log file |
| `--loglevel <level>` | `trace`, `debug`, `info`, `warn`, `error` |

## Loop / rotation (agent mode)

| Option | Purpose |
| --- | --- |
| `loop=<duration>` | Rotate output file every N (`1h`, `30m`) |
| `timeout=<duration>` | Auto-stop after N |
| `chunksize=<bytes>` | JFR chunk size |
| `chunktime=<duration>` | JFR chunk rotation interval |

## Examples

### Detailed CPU profile, large stacks, exclude framework noise
```bash
asprof -e cpu -d 60 -i 5ms -j 4096 \
       -X 'sun\.reflect.*' -X 'java\.lang\.reflect.*' \
       -f cpu.html <pid>
```

### Allocation profile in JFR for JMC analysis
```bash
asprof -e alloc -d 120 --alloc 256k -o jfr -f alloc.jfr <pid>
```

### Wall-clock per-thread
```bash
asprof -e wall -d 60 -t -i 20ms -f wall.html <pid>
```

### Hardware cache-miss with DWARF unwinding
```bash
asprof -e cache-misses -d 60 --cstack dwarf -f cache.html <pid>
```

### Continuous rolling JFR (production)
```bash
asprof -e cpu -f /var/log/profile-%t-%p.jfr loop=1h <pid>
```
