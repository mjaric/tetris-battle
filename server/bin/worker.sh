#!/usr/bin/env bash
set -euo pipefail

# Starts a Tetris evolution worker node.
#
# Usage:
#   ./bin/worker.sh <worker-ip-or-hostname> [cookie]
#
# Example:
#   ./bin/worker.sh 192.168.1.50
#   ./bin/worker.sh 192.168.1.50 my_secret_cookie

if [ $# -lt 1 ]; then
  echo "Usage: $0 <worker-ip-or-hostname> [cookie]"
  echo ""
  echo "Starts a BEAM worker node that accepts evolution jobs"
  echo "from the orchestrator via Erlang distribution."
  echo ""
  echo "  worker-ip  IP or hostname reachable from the orchestrator"
  echo "  cookie     Distribution cookie (default: tetris_evo)"
  exit 1
fi

WORKER_IP="$1"
COOKIE="${2:-tetris_evo}"
NODE_NAME="worker@${WORKER_IP}"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Starting worker node: ${NODE_NAME}"
echo "Cookie: ${COOKIE}"
echo "Project dir: ${SCRIPT_DIR}"
echo ""
echo "Waiting for orchestrator to connect..."
echo "Press Ctrl+C to stop."
echo ""

cd "$SCRIPT_DIR"

elixir \
  --name "$NODE_NAME" \
  --cookie "$COOKIE" \
  -S mix run --no-halt
