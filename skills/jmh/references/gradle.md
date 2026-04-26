# JMH with Gradle

Use the **`me.champeau.jmh`** plugin (maintained by Cédric Champeau, official-recommended). Avoid older forks; the `me.champeau.jmh` plugin handles source set, classpath, and runner correctly.

Plugin: https://github.com/melix/jmh-gradle-plugin

## Apply the plugin

### Groovy DSL (`build.gradle`)
```groovy
plugins {
    id 'java'
    id 'me.champeau.jmh' version '0.7.2'
}

repositories { mavenCentral() }

dependencies {
    // production code goes in main source set
}

jmh {
    warmupIterations = 5
    iterations = 10
    fork = 3
    timeOnIteration = '1s'
    warmup = '1s'
    benchmarkMode = ['thrpt']
    timeUnit = 'ns'
    resultFormat = 'JSON'
    resultsFile = file("$buildDir/reports/jmh/results.json")
    profilers = ['gc']
    jvmArgs = ['-Xmx2g', '-Xms2g', '-XX:+UseSerialGC']
}
```

### Kotlin DSL (`build.gradle.kts`)
```kotlin
plugins {
    java
    id("me.champeau.jmh") version "0.7.2"
}

jmh {
    warmupIterations.set(5)
    iterations.set(10)
    fork.set(3)
    timeOnIteration.set("1s")
    warmup.set("1s")
    benchmarkMode.set(listOf("thrpt"))
    timeUnit.set("ns")
    resultFormat.set("JSON")
    resultsFile.set(file("$buildDir/reports/jmh/results.json"))
    profilers.set(listOf("gc"))
    jvmArgs.set(listOf("-Xmx2g", "-Xms2g", "-XX:+UseSerialGC"))
}
```

## Source set

By default the plugin creates a `jmh` source set:

```
src/jmh/java/...        ← @Benchmark classes
src/jmh/resources/...
```

Benchmarks have access to `main` classpath automatically. Tests are not included; if you need test code, add:

```groovy
sourceSets.jmh.java.srcDirs += sourceSets.test.java.srcDirs
```

## Run

```bash
# Run all benchmarks
./gradlew jmh

# Run a single benchmark class
./gradlew jmh -Pjmh.includes='com\.acme\.MyBench.*'

# Run with overrides via property
./gradlew jmh -Pjmh.iterations=20 -Pjmh.fork=5

# Profile with async-profiler
./gradlew jmh -Pjmh.profilers='async:output=flamegraph'
```

Output:
- JSON: `build/reports/jmh/results.json`
- Text log: `build/reports/jmh/human.txt`
- Profiler output (e.g. flame graphs): `build/reports/jmh/profiles/`

## Configuration via properties (CI-friendly)

The plugin honors `-Pjmh.<property>` flags so the same `build.gradle` covers dev (long runs) and CI (smoke):

```bash
# Local full run
./gradlew jmh

# CI smoke
./gradlew jmh \
  -Pjmh.warmupIterations=1 \
  -Pjmh.iterations=2 \
  -Pjmh.fork=1
```

## Multi-project setup

```
root/
├── settings.gradle
├── core/
│   └── build.gradle              ← java
└── benchmarks/
    ├── build.gradle              ← java + me.champeau.jmh
    └── src/jmh/java/...
```

`benchmarks/build.gradle`:
```groovy
plugins {
    id 'java'
    id 'me.champeau.jmh' version '0.7.2'
}
dependencies {
    jmh project(':core')
}
```

## Producing a runnable fat-jar (optional)

If you need to ship a `benchmarks.jar` like the Maven shade output:

```groovy
tasks.register('jmhJar', Jar) {
    archiveClassifier = 'jmh'
    from sourceSets.jmh.output
    from configurations.jmhRuntimeClasspath.collect { it.isDirectory() ? it : zipTree(it) }
    manifest { attributes 'Main-Class': 'org.openjdk.jmh.Main' }
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
    exclude 'META-INF/*.SF', 'META-INF/*.DSA', 'META-INF/*.RSA'
}
```

```bash
./gradlew jmhJar
java -jar build/libs/<project>-jmh.jar MyBench -wi 10 -i 10 -f 3
```

## IDE integration

- IntelliJ: imports the `jmh` source set automatically; the JMH IntelliJ plugin recognizes `@Benchmark` and adds run gutter icons.
- Eclipse: works via Buildship; manual run via `./gradlew jmh`.

## Common Gradle gotchas

- **Plugin version drift** — `me.champeau.jmh` 0.7.x supports Gradle 7+; older Gradle versions need 0.6.x. Match plugin version to Gradle.
- **JMH version override** — by default the plugin pulls a JMH version; pin explicitly:
  ```groovy
  jmh { jmhVersion = '1.37' }
  ```
- **Annotation processing in `jmh` source set** — newer Gradle requires explicit:
  ```groovy
  dependencies {
      jmhAnnotationProcessor 'org.openjdk.jmh:jmh-generator-annprocess:1.37'
  }
  ```
  Otherwise "no benchmarks found".
- **Daemon JVM args** — Gradle daemon's JVM args do *not* affect benchmark JVMs; benchmark JVMs are forked and use `jmh.jvmArgs`. Misconfigured `org.gradle.jvmargs` looks like it's working but isn't.
- **`./gradlew test` doesn't run benchmarks** — that's correct; only `jmh` task does. Don't try to wire benchmarks into `test`.

## CI integration (continuous benchmarking)

```yaml
# GitHub Actions
- name: Run JMH
  run: ./gradlew jmh -Pjmh.warmupIterations=2 -Pjmh.iterations=3 -Pjmh.fork=1

- name: Upload JSON
  uses: actions/upload-artifact@v4
  with:
    name: jmh-results
    path: build/reports/jmh/results.json

- name: Bencher track
  uses: bencherdev/bencher@main
  with:
    bencher_token: ${{ secrets.BENCHER_API_TOKEN }}
    project: my-project
    adapter: java_jmh
    file: build/reports/jmh/results.json
```

See `references/analysis.md` for the analysis side of CI integration.
