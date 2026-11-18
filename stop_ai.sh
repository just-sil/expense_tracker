#!/usr/bin/env bash
# Stop the AI backend started by ./start_ai.sh (frees the GPU/RAM used by the model).
systemctl --user stop expense-backend && echo "Flask backend stopped"
sudo systemctl stop ollama && echo "Ollama stopped"
