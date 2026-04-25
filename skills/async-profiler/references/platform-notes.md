# Platform notes

Behavior differs across OS, kernel, and orchestrator. Check this before debugging "why doesn't this work on X."

## Linux

### Best supported, most accurate
- `cpu` event uses `perf_events` for low-overhead, high-accuracy sampling.
- All hardware events (`cycles`, `cache-misses`, etc.) work.
- Kernel frames captured with `kptr_restrict=0`.
- DWARF unwinding for stripped native libraries.

### Required sysctls (one-time, host-level)
```bash
sysctl kernel.perf_event_paranoid=1
sysctl kernel.kptr_restrict=0
```

To persist:
```
# /etc/sysctl.d/99-asprof.conf
kernel.perf_event_paranoid = 1
kernel.kptr_restrict = 0
```

### Distro-specific
- **Ubuntu / Debian:** install `linux-tools-$(uname -r)` for `perf` (used to validate perf works at all).
- **RHEL / CentOS:** `perf` package; SELinux may block ptrace — `setsebool -P deny_ptrace 0`.
- **Alpine (musl):** async-profiler ships `glibc` builds; for Alpine use the dedicated musl build (released since 2.x).
- **Amazon Linux 2 / 2023:** works out of box; install `kernel-tools` for perf utilities.

### Architecture
- x86_64: full feature set, including LBR (`--cstack lbr`) on Skylake+.
- aarch64: full feature set; some hardware events differ (`cycles` works, `cache-misses` may need different name — use `asprof list <pid>`).
- LBR is x86 Intel-only.

## macOS

### Limited but workable
- No `perf_events` — `cpu` event falls back to `itimer` automatically.
- No hardware performance counters.
- Native stacks via macOS-specific unwinder.
- `lock`, `alloc`, `wall`, `cpu` (itimer) work.
- Code signing: macOS may block agent loading. Disable SIP for the profiled JVM, or use `codesign --force --sign - libasyncProfiler.dylib`.

### Permissions
- No sysctl tuning needed.
- `sudo` may be required to attach to system JVMs.

### Architecture
- Intel and Apple Silicon both supported; download the matching release.

## FreeBSD

- Limited support. `cpu` event uses kqueue-based timer.
- No allocation profiling on some versions.
- Build from source if pre-built binaries don't match.

## Docker

### Profile inside the container
1. Bake `asprof` and `libasyncProfiler.so` into the image, or mount via volume.
2. Run container with capabilities:
   ```
   docker run --cap-add SYS_ADMIN --pid=host ...
   ```
   `--pid=host` is required if you want to profile across PID namespaces.
3. Inside container: `asprof -d 30 -f /tmp/profile.html <pid>`.

### Profile from host into container
Use `fdtransfer` to bridge namespaces:
```bash
# In container (long-running)
fdtransfer /tmp/asprof.sock

# On host
asprof --fdtransfer /tmp/asprof.sock -d 30 -f profile.html <container-pid>
```

### Common Docker pitfalls
- Default seccomp profile blocks `perf_event_open` — add `--security-opt seccomp=unconfined` or use `itimer`.
- Read-only filesystem: mount a writable volume for output (`-v /tmp/profiles:/tmp/profiles`).
- `--cap-add SYS_PTRACE` (in addition to `SYS_ADMIN`) required for cross-user attach.

## Kubernetes

### Strategies (best to worst for ad-hoc profiling)

1. **Bake into image** — `asprof` and `.so` always present. Profile via `kubectl exec`:
   ```bash
   kubectl exec <pod> -- asprof -d 30 -f /tmp/profile.html 1
   kubectl cp <pod>:/tmp/profile.html ./profile.html
   ```

2. **Ephemeral debug container** — Kubernetes 1.23+:
   ```bash
   kubectl debug <pod> --image=ghcr.io/your-org/asprof:latest \
                       --target=<container> -- asprof -d 30 ...
   ```
   Requires shared PID namespace in the pod spec (`shareProcessNamespace: true`).

3. **Sidecar pattern** — co-located container with `asprof`, shared PID namespace.

4. **Init container that copies `.so`** to a shared volume; main container loads via `-agentpath`.

### Required pod spec for full profiling
```yaml
spec:
  shareProcessNamespace: true
  containers:
  - name: app
    securityContext:
      capabilities:
        add: ["SYS_ADMIN", "SYS_PTRACE"]
```

### Continuous profiling
For always-on, use `-agentpath` with `loop=1h` writing to a sidecar that ships JFRs to S3 / object store. Pyroscope and Parca offer managed alternatives.

## Cloud-specific

### AWS Lambda (custom runtime / SnapStart)
- Use `-agentpath` in the start command.
- Output to `/tmp` (only writable path).
- Lambda has no perf — `itimer` only.
- Cold-start profiling: agent starts before user code → captures init.

### Google Cloud Run
- Similar to Lambda — write profiles to `/tmp`.
- Container can be configured with `--cpu-boost` to reduce profile distortion.

### AWS ECS / Fargate
- Fargate has no `--cap-add` — limited to `itimer`.
- ECS on EC2 has full Linux capability.

## Architecture pitfalls

| Target | `.so` you need |
| --- | --- |
| Linux x86_64 (glibc) | `async-profiler-<v>-linux-x64.tar.gz` |
| Linux x86_64 (musl) | `async-profiler-<v>-linux-musl-x64.tar.gz` |
| Linux aarch64 (glibc) | `async-profiler-<v>-linux-arm64.tar.gz` |
| macOS Intel | `async-profiler-<v>-macos.zip` (universal binary) |
| macOS Apple Silicon | same universal binary |

**Common mistake:** copying `.so` from a glibc image into an Alpine container — symbol resolution fails or JVM crashes. Use the musl build.

## Quick environment check

```bash
# 1. Can the kernel sample?
cat /proc/sys/kernel/perf_event_paranoid  # want 1 or lower

# 2. Can we resolve kernel symbols?
cat /proc/sys/kernel/kptr_restrict  # want 0

# 3. Is dynamic attach allowed?
jps -v | grep DisableAttachMechanism  # want NO match

# 4. Architecture match?
file libasyncProfiler.so
file $(readlink /proc/<pid>/exe)  # JVM binary

# 5. async-profiler version
asprof version
```
