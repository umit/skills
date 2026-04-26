# Analyzing JMH results

JMH's console table is human-readable but lossy for diff/visualize. Always emit JSON.

## Always emit JSON

```bash
java -jar benchmarks.jar -rf json -rff result.json
```

The JSON contains everything: every iteration's raw measurements, percentiles (for `SampleTime`), profiler columns. Console table is a summary; JSON is the data.

## JSON schema (essentials)

```json
[
  {
    "benchmark": "com.acme.MyBench.sumLoop",
    "mode": "avgt",
    "threads": 1,
    "forks": 3,
    "warmupIterations": 5,
    "measurementIterations": 10,
    "primaryMetric": {
      "score": 42.123,
      "scoreError": 0.456,
      "scoreConfidence": [41.667, 42.579],
      "scorePercentiles": { "0.0": 41.0, "50.0": 42.1, "99.0": 43.5 },
      "scoreUnit": "ns/op",
      "rawData": [[ ... per-iteration scores ... ]]
    },
    "secondaryMetrics": {
      "gc.alloc.rate.norm": { "score": 24.0, "scoreUnit": "B/op" }
    }
  }
]
```

The `scoreConfidence` interval is the 99.9% CI for the mean. **Two means are statistically different only if their CIs don't overlap.**

## Visualizers

### jmh.morethan.io (one-shot, free, shareable)

1. Open https://jmh.morethan.io
2. Drop `result.json`
3. Charts: bar (single run), line (`@Param` sweep), scatter (multi-run)
4. URL is shareable (data persists in URL fragment for small results, or paste a JSON gist URL: `?source=https://gist.github.com/...`)

For multi-platform comparison, append multiple `?sources=...` URLs.

### IntelliJ JMH plugin
Right-click `result.json` → "Open with JMH Visualizer" — embedded UI inside IDE.

### Jenkins JMH Report Plugin
For self-hosted CI: archives `result.json` as build artifact and renders trend charts across builds.

## Diffing two runs

Compare two JSON runs by computing per-benchmark deltas and checking confidence-interval overlap:

```bash
# Sort & extract benchmark + score
jq -r '.[] | "\(.benchmark)\t\(.primaryMetric.score)\t\(.primaryMetric.scoreError)"' \
   baseline.json | sort > baseline.tsv

jq -r '.[] | "\(.benchmark)\t\(.primaryMetric.score)\t\(.primaryMetric.scoreError)"' \
   current.json  | sort > current.tsv

# Compare
join baseline.tsv current.tsv | \
  awk '{
    base=$2; baseE=$3; curr=$4; currE=$5;
    delta=(curr-base)/base*100;
    if (curr+currE < base-baseE) status="IMPROVED";
    else if (curr-currE > base+baseE) status="REGRESSED";
    else status="NOISE";
    printf "%-50s %8.2f %% %s\n", $1, delta, status;
  }'
```

Key: **only flag changes where confidence intervals don't overlap.** Anything else is noise.

## Statistical interpretation

JMH reports three things per benchmark:

- **Score** — mean across all iterations × forks
- **Error** — half-width of the 99.9% CI (Student's t)
- **Score Percentiles** (only for `SampleTime` mode)

Rules of thumb:
- Mean ± Error covers the *true* mean with 99.9% probability.
- If CI of A = `[40, 44]` and CI of B = `[45, 50]` → significantly different.
- If CI of A = `[40, 46]` and CI of B = `[44, 50]` → overlapping → **do not claim different**.
- More forks (`-f 5`) shrinks Error; more iterations (`-i 20`) shrinks intra-fork variance.
- Outliers from GC/safepoint can inflate Error; investigate with `-prof safepoints`.

## CI integration

### Bencher (continuous benchmarking SaaS, OSS adapter)

```yaml
- run: ./gradlew jmh
- uses: bencherdev/bencher@main
  with:
    bencher_token: ${{ secrets.BENCHER_API_TOKEN }}
    project: my-project
    branch: ${{ github.head_ref || github.ref_name }}
    testbed: ci-linux
    adapter: java_jmh
    file: build/reports/jmh/results.json
    threshold_test: t_test
    threshold_max_sample_size: 64
    threshold_upper_boundary: 0.95
    err: true
```

`err: true` fails the PR if a benchmark regresses past the threshold.

### Codspeed (alternative SaaS)

```yaml
- uses: CodSpeedHQ/action@v3
  with:
    token: ${{ secrets.CODSPEED_TOKEN }}
    run: ./gradlew jmh
```

Codspeed instruments via Cachegrind for deterministic results (no machine-noise variance) but only on its hosted runners.

### Self-hosted (jmh-report Jenkins plugin)

Archive `result.json` per build; the plugin renders trend charts. Free; less feature-rich than Bencher/Codspeed.

## Sharing with reviewers

Three options, increasing in fidelity:

1. **Console table screenshot** — fastest, lossy.
2. **`jmh.morethan.io` URL** — interactive, shareable, free, no auth.
3. **Bencher/Codspeed link** — historical context, regression alerts.

For PR reviews, link a `jmh.morethan.io` chart in the description. Reviewers see the comparison without setting anything up.

## Anti-patterns in analysis

- **Reporting one fork's number** — always aggregate across forks (JMH does this for you in JSON; don't manually pick one).
- **Comparing scores from different `Mode`** — Throughput and AverageTime are reciprocals; converting introduces error. Use the same Mode for A/B.
- **Comparing scores from different `OutputTimeUnit`** — JMH normalizes internally but a copy-paste between reports loses units.
- **Ignoring `gc.alloc.rate.norm`** — a "faster" benchmark that allocates 2× more usually loses under load. Always read GC columns alongside time.
- **Cherry-picking `@Param` rows** — report all rows or none; selecting one undermines the matrix design.
