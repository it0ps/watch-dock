# Watch Dock

Watch Dock is a lightweight systemd timer plus Bash script that checks running Docker containers every minute and pushes Telegram alerts whenever their image digest changes. It is handy for keeping an eye on automated deploys or unexpected restarts without needing a full observability stack.

## Components
- `woof-woof.sh`: Bash script that inspects running containers, remembers the last image seen, and notifies Telegram on changes.
- `watch-dock.service`: One-shot systemd service that runs the script with environment loaded from `/opt/watch-dock/.env`.
- `watch-dock.timer`: systemd timer that triggers the service 60 seconds after boot and then every minute.

## Requirements
- systemd (for the timer + service)
- Docker CLI access for the user running the service
- `curl` and `jq`
- Telegram bot token and chat ID to receive notifications

## Installation
1. Clone this repository onto the target host and enter it:
   ```bash
   git clone https://github.com/it0ps/watch-dock.git
   cd watch-dock
   ```
2. Install the script and configuration directory (defaults assume `/opt/watch-dock`):
   ```bash
   sudo mkdir -p /opt/watch-dock
   sudo cp woof-woof.sh /opt/watch-dock/
   sudo chmod 750 /opt/watch-dock/woof-woof.sh
   sudo chown root:root /opt/watch-dock/woof-woof.sh
   ```
3. Create the environment file `/opt/watch-dock/.env` and populate the required variables (see [Configuration](#configuration)). Ensure it is readable only by the service account.
4. Copy the systemd unit files into place and reload systemd:
   ```bash
   sudo cp watch-dock.service /etc/systemd/system/
   sudo cp watch-dock.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   ```
5. Enable and start the timer:
   ```bash
   sudo systemctl enable --now watch-dock.timer
   ```

## Configuration
The service loads variables from `/opt/watch-dock/.env`.

Required:
- `TELEGRAM_BOT_TOKEN`: Token for your Telegram bot.
- `TELEGRAM_CHAT_ID`: Target chat or channel ID (e.g. `-1001234567890`).

Optional:
- `CONTAINER_NAME_REGEX`: Regular expression applied to container names (default: `.*` to watch all containers).
- `STATE_FILE`: Path to the JSON state file that stores last-seen container images (default: `/opt/watch-dock/state.json`).
- `SEND_ON_FIRST_SEEN`: Set to `1` to send a notification the first time a container is observed (default: `0`).
- `HOSTNAME_SHORT`: Override the hostname label that appears in Telegram messages (defaults to the system short hostname).

Example `.env`:
```bash
TELEGRAM_BOT_TOKEN=123456:abcde-your-bot-token
TELEGRAM_CHAT_ID=-100987654321
CONTAINER_NAME_REGEX=^prod_
STATE_FILE=/opt/watch-dock/state.json
SEND_ON_FIRST_SEEN=0
HOSTNAME_SHORT=prod-node-1
```

## How It Works
1. `watch-dock.timer` triggers `watch-dock.service` every minute.
2. `watch-dock.service` runs `woof-woof.sh`, which:
   - reads the environment file for configuration;
   - lists running containers and filters them with `CONTAINER_NAME_REGEX`;
   - inspects each container's image, preferring the repo digest or image ID as a stable reference;
   - compares the reference against previous runs stored in `STATE_FILE`;
   - sends a Telegram message when an image reference changes (deploy detected) or on first sight if enabled;
   - prunes state for containers that are no longer running.

## Monitoring and Troubleshooting
- Check last run status: `systemctl status watch-dock.service`.
- View recent logs: `journalctl -u watch-dock.service -n 50`.
- Inspect state file to see stored image references: `sudo cat /opt/watch-dock/state.json`.
- If notifications stop, verify that `jq`, `curl`, and `docker` are available to the service account and that the Telegram credentials are still valid.

## Development
- Run the script manually to test configuration:
  ```bash
  sudo TELEGRAM_BOT_TOKEN=... TELEGRAM_CHAT_ID=... ./woof-woof.sh
  ```
- Adjust the `watch-dock.service` `EnvironmentFile` path if you prefer a different installation directory.
- Pull requests and issues welcome!
