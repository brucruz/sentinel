#!/bin/bash
# Prepare VPS for Sentinel deploys. Safe to rerun (idempotent).
# Usage: ssh user@your-vps 'bash -s' < deploy/setup-vps.sh

set -euo pipefail

echo "==> Creating sentinel user..."
sudo useradd --system --no-create-home --shell /usr/sbin/nologin sentinel 2>/dev/null || echo "User already exists"

echo "==> Adding sentinel to docker group..."
sudo usermod -aG docker sentinel

echo "==> Creating directories..."
sudo mkdir -p /opt/sentinel
sudo mkdir -p /etc/sentinel
sudo chown sentinel:docker /opt/sentinel

echo "==> NOTE: The systemd service file is deployed by CI (deploy/sentinel.service)."
echo "    On first setup, CI will copy it to /etc/systemd/system/sentinel.service"

echo "==> Creating env file template..."
if [ ! -f /etc/sentinel/env ]; then
  sudo tee /etc/sentinel/env > /dev/null << 'EOF'
SENTINEL_TELEGRAM_TOKEN=your-bot-token-here
SENTINEL_CHAT_ID=your-chat-id-here
EOF
  sudo chmod 600 /etc/sentinel/env
  echo "    IMPORTANT: Edit /etc/sentinel/env with your Telegram credentials"
else
  echo "    /etc/sentinel/env already exists, skipping"
fi

echo "==> Enabling service..."
if [ -f /etc/systemd/system/sentinel.service ]; then
  sudo systemctl daemon-reload
  sudo systemctl enable sentinel
else
  echo "    Service file not yet installed (CI will deploy it on first push)"
fi

echo ""
echo "==> Setup complete!"
echo "    Next steps:"
echo "    1. Edit /etc/sentinel/env with your Telegram bot token and chat ID"
echo "    2. Deploy the release to /opt/sentinel/"
echo "    3. Start with: sudo systemctl start sentinel"
echo "    4. Check logs: sudo journalctl -u sentinel -f"
