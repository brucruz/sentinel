#!/bin/bash
# Prepare VPS for Sentinel deploys. Safe to rerun (idempotent).
#
# Usage:
#   scp .env user@your-vps:/tmp/sentinel.env
#   ssh user@your-vps 'bash -s' < deploy/setup-vps.sh

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

echo "==> Setting up env file..."
if [ -f /tmp/sentinel.env ]; then
  sudo mv /tmp/sentinel.env /etc/sentinel/env
  sudo chmod 600 /etc/sentinel/env
  echo "    Installed from /tmp/sentinel.env"
elif [ -f /etc/sentinel/env ]; then
  echo "    /etc/sentinel/env already exists, skipping"
else
  echo "    WARNING: No env file found. Either:"
  echo "      - scp .env user@your-vps:/tmp/sentinel.env (before running this script)"
  echo "      - Or create /etc/sentinel/env manually"
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
echo "    1. Push to main to trigger CI deploy"
echo "    2. Check logs: sudo journalctl -u sentinel -f"
