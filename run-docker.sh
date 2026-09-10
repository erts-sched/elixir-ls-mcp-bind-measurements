#!/usr/bin/env bash
# Runs mcp_bind.erl inside the official erlang:<version> images on Docker's
# default bridge network, i.e. in a network namespace of its own: no host
# firewall rules, a non-loopback address (172.17.0.x) to connect from.
# Usage: ./run-docker.sh 27 28 29
set -euo pipefail
cd "$(dirname "$0")"
[ $# -gt 0 ] || { echo "usage: $0 <otp-version>..." >&2; exit 2; }
mkdir -p results
for V in "$@"; do
  OUT="results/otp$V-docker-bridge.txt"
  echo "== erlang:$V (bridge) -> $OUT"
  docker run --rm -v "$PWD/mcp_bind.erl:/mcp_bind.erl:ro" "erlang:$V" \
    sh -c 'cd /tmp && erlc /mcp_bind.erl && erl -noshell -pa /tmp -eval "mcp_bind:main()."' 2>&1 | tee "$OUT"
done
