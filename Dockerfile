FROM golang:1.19 as envtoml-builder

WORKDIR /build

COPY tomlenv/go.mod go.mod
COPY tomlenv/go.sum go.sum

RUN go mod download

COPY tomlenv/main.go main.go

ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=linux GOARCH=$TARGETARCH go build -a -o tomlenv main.go

FROM ubuntu:22.04

WORKDIR /kube-bench

ARG TARGETARCH
RUN apt update && apt install curl gettext-base vim postgresql-client less coreutils unzip git jq python3-pip apt-transport-https ca-certificates gnupg -y && rm -rf /var/lib/apt/lists/* && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$TARGETARCH/kubectl" && mv kubectl /usr/local/bin && \
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && \
    chmod +x /usr/local/bin/kubectl && chmod +x /usr/local/bin/helm && echo 'alias k="kubectl -n ${BENCHMARK_CONSOLE_NAMESPACE}"' >> /root/.bashrc && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
    apt-get update && apt-get install google-cloud-cli google-cloud-sdk-gke-gcloud-auth-plugin -y && \
    helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null && helm repo add kafka-ui https://provectus.github.io/kafka-ui-charts && \
    helm repo update >/dev/null && curl "https://awscli.amazonaws.com/awscli-exe-linux-$(arch).zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && ./aws/install && rm -rf aws awscliv2.zip

COPY --from=envtoml-builder /build/tomlenv /usr/local/bin
COPY benchmarks benchmarks
COPY manifests manifests
COPY lib lib
COPY env.toml env.toml
COPY benchmark.sh benchmark.sh
COPY README.md README.md

ENTRYPOINT ["/bin/bash"]