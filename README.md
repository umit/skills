# skills

My personal agent skills.

## Install

```bash
npx skills add umit/skills --skill <skill-name>
```

## Skills

| Skill | What it does |
| --- | --- |
| [`async-profiler`](skills/async-profiler) | JVM profiling with async-profiler: CPU, allocation, lock, wall-clock, hardware counters. Flame graphs and JFR. |
| [`jmh`](skills/jmh) | Trustworthy Java microbenchmarks with JMH — DCE/constant-folding pre-flight checker, Maven & Gradle setup, mode/state/profiler guidance, jmh.morethan.io analysis. |

## Anatomy

```
skills/<name>/
├── SKILL.md          # loaded into agent context: triggers, workflow, index
├── references/       # read on demand by the agent
│   └── *.md
└── scripts/          # optional executable helpers
    └── *.sh
```

Short `SKILL.md` up front, deep references on demand — keeps context cost low.

## License

MIT
