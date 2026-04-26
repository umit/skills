# JMH with Maven

Maven is the original JMH integration target — `pom.xml` produces a self-contained shaded `benchmarks.jar` that runs anywhere with a JDK.

## Bootstrap a new project

```bash
mvn archetype:generate \
  -DinteractiveMode=false \
  -DarchetypeGroupId=org.openjdk.jmh \
  -DarchetypeArtifactId=jmh-java-benchmark-archetype \
  -DgroupId=com.example \
  -DartifactId=my-bench \
  -Dversion=1.0
cd my-bench
mvn clean verify
java -jar target/benchmarks.jar
```

The archetype scaffolds `pom.xml` with the shade plugin already configured.

## Add JMH to an existing project

```xml
<properties>
  <jmh.version>1.37</jmh.version>
  <java.version>21</java.version>
</properties>

<dependencies>
  <dependency>
    <groupId>org.openjdk.jmh</groupId>
    <artifactId>jmh-core</artifactId>
    <version>${jmh.version}</version>
    <scope>provided</scope>
  </dependency>
  <dependency>
    <groupId>org.openjdk.jmh</groupId>
    <artifactId>jmh-generator-annprocess</artifactId>
    <version>${jmh.version}</version>
    <scope>provided</scope>
  </dependency>
</dependencies>

<build>
  <plugins>
    <plugin>
      <groupId>org.apache.maven.plugins</groupId>
      <artifactId>maven-shade-plugin</artifactId>
      <version>3.5.1</version>
      <executions>
        <execution>
          <phase>package</phase>
          <goals><goal>shade</goal></goals>
          <configuration>
            <finalName>benchmarks</finalName>
            <transformers>
              <transformer
                implementation="org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                <mainClass>org.openjdk.jmh.Main</mainClass>
              </transformer>
            </transformers>
            <filters>
              <filter>
                <artifact>*:*</artifact>
                <excludes>
                  <exclude>META-INF/*.SF</exclude>
                  <exclude>META-INF/*.DSA</exclude>
                  <exclude>META-INF/*.RSA</exclude>
                </excludes>
              </filter>
            </filters>
          </configuration>
        </execution>
      </executions>
    </plugin>
  </plugins>
</build>
```

## Build

```bash
mvn clean verify -DskipTests
# Produces target/benchmarks.jar (shaded fat-jar with JMH runner main class)
```

## Run

```bash
# Run all benchmarks
java -jar target/benchmarks.jar

# Run a single class (regex match)
java -jar target/benchmarks.jar MyBench

# Run with explicit warmup, measurement, fork
java -jar target/benchmarks.jar MyBench \
  -wi 10 -i 10 -f 3 \
  -prof gc \
  -rf json -rff result.json

# Run with async-profiler
java -jar target/benchmarks.jar MyBench \
  -prof async:output=flamegraph;dir=profiles
```

Common flags:

| Flag | Meaning |
| --- | --- |
| `-wi N` | warmup iterations |
| `-i N` | measurement iterations |
| `-w 5s` | warmup time per iteration |
| `-r 10s` | measurement time per iteration |
| `-f N` | forks (separate JVMs) |
| `-t N` | threads |
| `-bm Throughput` | benchmark mode (overrides annotation) |
| `-tu ns` | output time unit |
| `-prof <name>` | attach profiler (gc, async, jfr, perfasm, stack) |
| `-rf json -rff result.json` | JSON output |
| `-jvmArgs "-Xmx2g -XX:+UseSerialGC"` | extra JVM args |
| `-e <regex>` | exclude benchmarks |
| `-l` / `-lp` | list benchmarks / params |

## Multi-module projects

Place benchmarks in their own module to avoid contaminating the production jar:

```
parent/
├── pom.xml
├── core/
│   └── src/main/java/...
└── benchmarks/
    ├── pom.xml          ← jmh + shade
    └── src/main/java/...  ← @Benchmark classes
```

The benchmarks module depends on `core` (no `<scope>provided</scope>` for *core* — only for `jmh-core` itself).

## IDE integration

- IntelliJ: install the **JMH Plugin** — adds `Run Benchmark` next to `@Benchmark`. Translates to `org.openjdk.jmh.Main` invocation. Note: IDE runs use a *non-shaded* classpath; for definitive numbers always use `target/benchmarks.jar`.

## Common Maven gotchas

- **Annotation processor not running** → ensure `jmh-generator-annprocess` is on the build classpath; missing it produces "no benchmarks found" at runtime.
- **`META-INF/BenchmarkList` missing** → shade plugin not configured; benchmarks compile but the runner can't discover them. Add the `ManifestResourceTransformer` and ideally `ServicesResourceTransformer`.
- **Surefire skipped tests but benchmarks run** → benchmarks aren't tests; they live in `src/main/java`. Don't put them under `src/test/java` unless you also configure JMH to scan that source set.
- **Duplicate classes in shade** → exclude SF/DSA/RSA manifest signatures (above filter).

## Run as a JUnit-friendly task (optional)

Can be embedded into Maven `verify` phase via `exec-maven-plugin` running `org.openjdk.jmh.Main` — useful for CI smoke runs, but use **short** `-wi 1 -i 1 -f 1` for CI; full runs belong in a dedicated nightly job.
