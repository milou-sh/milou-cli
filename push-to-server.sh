#!/bin/bash

# Default IP if none provided
DEFAULT_IP="142.93.229.75"
REMOTE_IP=${1:-$DEFAULT_IP}
SSH_KEY="$HOME/.ssh/digitalocean"
LOCAL_DIR="$HOME/milou-cli"
REMOTE_DIR="/home/milou-cli"

# Check prerequisites
if [ ! -f "$SSH_KEY" ]; then
  echo "❌ SSH key not found: $SSH_KEY"
  exit 1
fi

if [ ! -d "$LOCAL_DIR" ]; then
  echo "❌ Local directory not found: $LOCAL_DIR"
  exit 1
fi

chmod 600 "$SSH_KEY"

# Exclude files you don’t want to copy
echo "🚀 Copying filtered contents of milou-cli to $REMOTE_IP..."
rsync -avz -e "ssh -i $SSH_KEY" \
  --exclude '.git' \
  --exclude '.gitignore' \
  --exclude '.env' \
  --exclude '.env.example' \
  --exclude '*README*' \
  --exclude '*FIXES*' \
  "$LOCAL_DIR/" root@"$REMOTE_IP":"$REMOTE_DIR"

echo "✅ Deployment complete!"
