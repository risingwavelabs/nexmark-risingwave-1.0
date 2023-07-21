# BENCHMARK

A benchmark tool to run the [Nexmark Benchmark](https://github.com/nexmark/nexmark) on both RisingWave and Apache Flink
with Kubernetes.

## Prerequisites

- Kubernetes >= 1.21
- Helm >= 3.0
- Bash >= 4.4
- RisingWave Operator >= 0.5.0

## Run

### Before Running

Ensure that the Kubernetes cluster is ready. Run the following command to check:

```shell
kubectl get nodes
```

Ensure there are at least 4 nodes with 8 CPU cores and 16 GB memory. For each test,

- 1 node is used for the benchmark driver
- 1 node is used for the Apache Kafka and Apache Zookeeper
- The rest nodes are used for the RisingWave or Apache Flink
    - For RisingWave, 1 node is used for etcd, meta, and frontend, another node is used for compute and compactor
    - For Apache Flink, 1 node is used for JobManager, another node is used for TaskManager

One could customize the requirements by modifying the resources part in `benchmark.toml` files in the `benchmarks`
directory as long as he understands the deployment.

### Build and Start a Docker Container

The scripts rely on several external tools to run. We provide a Dockerfile to build a Docker image with all the tools.

Just run the following command to build the Docker image and start a container:

```shell
make start
```

### Set Up

#### Set Up RisingWave

Export the following environment variables and keep it in all rest steps:

```shell
export BENCHMARK_ENV_OVERRIDE=benchmarks/risingwave/benchmark.toml
```

Update the AWS credentials required to create the S3 bucket for the benchmark in `benchmarks/risingwave/benchmark.toml`:

```toml
[benchmark.aws.credentials]
access_key = ""
access_secret = ""
```

Or export them into environment variables:

```shell
export BENCHMARK_AWS_CREDENTIALS_ACCESS_KEY=""
export BENCHMARK_AWS_CREDENTIALS_ACCESS_SECRET=""
```

(optional) Update the options where S3 bucket will be created:

```toml
[benchmark.risingwave.storage.s3]
region = "us-east-1"
bucket = "risingwave"
```

Then run the following command to set up the all required components:

```shell
./benchmark.sh setup -i
```

#### Set Up Flink

Similar to RisingWave, export the following environment variables:

```shell
export BENCHMARK_ENV_OVERRIDE=benchmarks/flink/benchmark.toml
```

Update the AWS credentials required to create the S3 bucket for the benchmark in `benchmarks/flink/benchmark.toml`:

```toml
[benchmark.aws.credentials]
access_key = ""
access_secret = ""
```

Or export them into environment variables:

```shell
export BENCHMARK_AWS_CREDENTIALS_ACCESS_KEY=""
export BENCHMARK_AWS_CREDENTIALS_ACCESS_SECRET=""
```

Prepare a S3 bucket on the console and update the options where S3 objects will be created:

```toml
[benchmark.flink.s3]
# The S3 bucket where the checkpoint will be stored. Must be prepared manually.
bucket = "flink"
bucket_folder = "checkpoints"
```

Then run the following command to set up the all required components:

```shell
./benchmark.sh setup -i
```

### Run Benchmark

Run the following command to prepare data and start:

```shell
./benchmark.sh prepare
./benchmark.sh start
```

By default, they will start the Nexmark `q0`.

> Note: the steps above are required for both RisingWave and Apache Flink. They have different implementations but they
> should all prepare data in the same way and start the benchmark.

### Restart with Another Query

Before restarting with another query, please update the following two options in `benchmarks/*/benchmark.toml`:

```toml
[benchmark.nexmark]
# Change it to another query to run another query. For supported values, please refer to the following two files:
#  - manifests/nexmark/nexmark-materialized-views.template.yaml
#  - manifests/flink-nexmark/nexmark-queries.template.yaml
query = "q0"

[benchmark.nexmark_kafka]
# Change it to true to skip inserting data into Kafka when preparing and deleting the topic when cleaning.
skip_insert_kafka = true
```

Then run the following command to clean the previous materialized views and tables:

```shell
./benchmark.sh clean
````

And run the following command to start the benchmark again:

```shell
./benchmark.sh prepare
./benchmark.sh start
```

### Tear Down

Run the following command to tear down all the components:

```shell
./benchmark.sh teardown -f
```