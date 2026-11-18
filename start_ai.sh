#!/usr/bin/env bash
# Start the AI backend on demand: Ollama (model server) + Flask API.
# Stop it again with ./stop_ai.sh
set -e

echo "Starting Ollama..."
systemctl is-active --quiet ollama || sudo systemctl start ollama

echo "Starting Flask backend..."
systemctl --user start expense-backend

for _ in $(seq 1 15); do
  if curl -s -m 2 http://127.0.0.1:5000/api/health >/dev/null; then
    IP=$(hostname -I | awk '{print $1}')
    echo "Ready: http://$IP:5000  (logs: journalctl --user -u expense-backend -f)"
    # Set up USB sync too if the phone is plugged in.
    "$(dirname "$0")/sync_usb.sh" 2>/dev/null || true
    exit 0
  fi
  sleep 1
done

echo "Backend did not respond. Check: journalctl --user -u expense-backend -n 30"
exit 1
