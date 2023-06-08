#!/usr/bin/env bash

docker run --rm --volume "$(pwd):/helm-docs" -u "$(id -u)" jnorwood/helm-docs:v1.8.1
if ! git diff --exit-code; then
    echo "Documentation not up to date. Please run helm-docs and commit changes!" >&2
    exit 1
fi