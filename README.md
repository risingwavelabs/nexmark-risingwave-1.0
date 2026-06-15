# Nexmark RisingWave 1.0 Benchmark

This repository is a Kubernetes runner for the Nexmark benchmark on RisingWave 1.0 and Apache Flink.

The default RisingWave sample is a small smoke-sized run using:

- PostgreSQL as the RisingWave meta store.
- MinIO as the RisingWave state store.
- Kafka for Kafka-based Nexmark data generation.

Etcd and external object stores such as S3, GCS, Azure Blob, or S3-compatible storage remain available through configuration.

## Prerequisites

- Kubernetes >= 1.21
- Helm >= 3.0
- Bash >= 4.4
- Go 1.19+
- RisingWave Operator >= 0.5.0
- `jq` and `kubectl`
- Cloud CLIs only when using an external object store

## Validation

Build the TOML environment loader and render-check all tracked templates:

```shell
make check
```

Run shellcheck on tracked shell scripts:

```shell
make shellcheck
```

Build the console image locally:

```shell
make docker-build
```

## Docker Console

The scripts rely on several external tools. Build and start a local container with:

```shell
make start
```

This mounts your local kubeconfig, AWS config, and repository into the container.

## RisingWave Benchmark

Use the RisingWave override file:

```shell
export BENCHMARK_ENV_OVERRIDE=benchmarks/risingwave/benchmark.toml
```

The default override is a small smoke-sized run. It deploys PostgreSQL and MinIO inside the benchmark namespace, so it does
not require cloud object-store credentials. The sample uses RisingWave `v3.0.0` with PostgreSQL-backed metadata.

```toml
[benchmark.risingwave]
meta_store = "postgresql"

[benchmark.risingwave.storage]
type = "minio"

[benchmark.risingwave.storage.minio]
bucket = "hummock"
data_directory = "hummock_001"
```

### Configure Test Parameters

The runner loads `env.toml` plus one override file. If `BENCHMARK_ENV_OVERRIDE` is set, that file is used as the
override. Otherwise, the default override path is `env.override.toml`.

For local experiments, either edit `benchmarks/risingwave/benchmark.toml` directly or copy it and point
`BENCHMARK_ENV_OVERRIDE` to the copy:

```shell
cp benchmarks/risingwave/benchmark.toml env.override.toml
unset BENCHMARK_ENV_OVERRIDE
```

Common Nexmark workload parameters:

```toml
[benchmark.nexmark]
# Comma-separated query names. Do not add spaces.
query = "q0,q3"
# 0 means use RisingWave's default parallelism.
streaming_parallelism = 0

[benchmark.nexmark_kafka]
# Total events generated into Kafka during prepare.
max_events = 1000000
# Target total generation rate across all generator threads.
event_rate = 10000
# Number of event generator threads.
generator_thread_num = 8
# Kafka topic partition count.
partition = 8
# Reuse existing Kafka data on repeated runs.
skip_insert_kafka = true
keep_kafka_data = true
```

Use `skip_insert_kafka = false` for a fresh data generation run. Use `keep_kafka_data = false` when you want `clean` to
delete benchmark topics.

### Configure RisingWave Resources

Scale RisingWave replicas with:

```toml
[benchmark.risingwave.replicas]
meta = 1
frontend = 1
compute = 2
compactor = 1
connector = 0
```

Set the default RisingWave component resource request and limit with:

```toml
[benchmark.risingwave.resources]
cpu = { limit = "4", request = "2" }
mem = { limit = "8Gi", request = "4Gi" }
```

Use component-specific sections when meta, frontend, compute, or compactor need different sizing:

```toml
[benchmark.risingwave.resources.meta]
cpu = { limit = "2", request = "1" }
mem = { limit = "4Gi", request = "2Gi" }

[benchmark.risingwave.resources.frontend]
cpu = { limit = "2", request = "1" }
mem = { limit = "4Gi", request = "2Gi" }

[benchmark.risingwave.resources.compute]
cpu = { limit = "8", request = "4" }
mem = { limit = "16Gi", request = "8Gi" }

[benchmark.risingwave.resources.compactor]
cpu = { limit = "2", request = "1" }
mem = { limit = "4Gi", request = "2Gi" }
```

If a component-specific section is omitted, meta and frontend use `[benchmark.risingwave.resources]`. Compute and
compactor also use `[benchmark.risingwave.resources]` by default. To apply separate compute and compactor sizing, enable
node selectors for the pod distribution settings:

```toml
[benchmark.pods.distribution]
node_selectors = "node-group:benchmark"
compactor_compute_affinity_enabled = "true"
```

Supporting service resources are configured separately:

```toml
[benchmark.kafka.resources]
cpu = { limit = "2", request = "1" }
mem = { limit = "4Gi", request = "2Gi" }

[benchmark.postgresql.metastore.resources]
cpu = { limit = "1", request = "500m" }
mem = { limit = "2Gi", request = "1Gi" }

[benchmark.minio.resources]
cpu = { limit = "1", request = "500m" }
mem = { limit = "2Gi", request = "1Gi" }
```

Run the lifecycle:

```shell
./benchmark.sh setup -i
./benchmark.sh prepare
./benchmark.sh start
./benchmark.sh logs -f
./benchmark.sh clean
./benchmark.sh teardown
```

RisingWave setup starts the configured meta store, the configured object store, Kafka, and RisingWave.

## Flink Benchmark

Use the Flink override file:

```shell
export BENCHMARK_ENV_OVERRIDE=benchmarks/flink/benchmark.toml
```

Configure a checkpoint bucket before setup:

```toml
[benchmark.flink.s3]
access_key = ""
access_secret = ""
bucket = "flink"
bucket_folder = "checkpoints"
```

Then run the same lifecycle:

```shell
./benchmark.sh setup -i
./benchmark.sh prepare
./benchmark.sh start
./benchmark.sh logs -f
./benchmark.sh clean
./benchmark.sh teardown
```

## Query Changes

Change the Nexmark query in the selected override file:

```toml
[benchmark.nexmark]
query = "q0"
```

For repeated runs against existing Kafka data, set:

```toml
[benchmark.nexmark_kafka]
skip_insert_kafka = true
keep_kafka_data = true
```
