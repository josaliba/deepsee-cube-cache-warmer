#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p /durable/databases/DISEASEREGISTRY

echo "Bootstrapping the DISEASEREGISTRY namespace and loading ObjectScript sources..."
iris session IRIS < /opt/disease-registry/docker/iris.script
echo "Disease Registry bootstrap complete."

