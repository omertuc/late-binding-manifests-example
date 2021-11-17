#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

function usage {
    echo "USAGE: $0 namespace pull_secret_base64 ssh_public_key"
    exit 1
}

set +u
if [[ "$1" == "" ]]; then
    usage
fi

if [[ "$2" == "" ]]; then
    usage
fi

if [[ "$3" == "" ]]; then
    usage
fi
set -u

rm -rf out
mkdir -p out

for f in *.j2; do
    jinja2 $f -Dnamespace=$1 -Dpull_secret_b64="$2" -Dssh_public_key="$3" > out/${f%.*}
done
