#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p /durable/databases/CCWDEMO

echo "Bootstrapping the CCWDEMO namespace and loading ObjectScript sources..."
iris session IRIS < /opt/ccw-demo/docker/iris.script
echo "Cube Cache Warmer Demo bootstrap complete."

