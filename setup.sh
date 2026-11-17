#!/usr/bin/env bash
# Sets up a browser-based IC design desktop (IIC-OSIC-TOOLS with the IHP SG13G2 open PDK) on a fresh Ubuntu VM.
# Safe to run again: only missing parts are installed, the container is recreated with the current settings.
# Usage: VNC_PW='password-for-desktop' ./setup.sh
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-2026.10}"            # fixed image version, "latest" would change the tools and PDK every month
WEBSERVER_PORT="${WEBSERVER_PORT:-8080}"     # noVNC port on the VM, reached only through the SSH tunnel
KEYBOARD="${KEYBOARD:-de}"                   # keyboard layout inside the desktop
TOOLS_DIR="$HOME/IIC-OSIC-TOOLS"             # start scripts of IIC-OSIC-TOOLS
CONTAINER="iic-osic-tools_xvnc_uid_$(id -u)" # name used by start_vnc.sh

: "${VNC_PW:?Set a desktop password, e.g. VNC_PW='password-for-desktop' ./setup.sh}"

echo "== Docker"
if ! command -v docker >/dev/null; then
    sudo apt-get update
    sudo apt-get -y upgrade
    curl -fsSL https://get.docker.com | sudo sh
fi
# docker without sudo from the next login on, until then this script uses "sg docker"
sudo usermod -aG docker "$USER"

echo "== IIC-OSIC-TOOLS start scripts"
if [ ! -d "$TOOLS_DIR" ]; then
    git clone --depth 1 https://github.com/iic-jku/IIC-OSIC-TOOLS.git "$TOOLS_DIR"
fi

echo "== Image hpretl/iic-osic-tools:$IMAGE_TAG (about 4 GB download, 17 GB on disk)"
sg docker -c "docker pull hpretl/iic-osic-tools:$IMAGE_TAG"

echo "== Desktop container"
sg docker -c "docker rm -f $CONTAINER" >/dev/null 2>&1 || true

# settings for start_vnc.sh, passed via the environment so the password needs no extra quoting
export DOCKER_TAG="$IMAGE_TAG" VNC_PW WEBSERVER_PORT XKB_KEYBOARD_LAYOUT="$KEYBOARD"
# own user and group IDs, under "sg docker" start_vnc.sh would take the docker group
export CONTAINER_USER="$(id -u)" CONTAINER_GROUP="$(id -g)"
# no direct VNC port, the browser is enough
export VNC_PORT=0
# restart after a VM reboot or a logout inside the desktop
export DOCKER_EXTRA_PARAMS="--restart unless-stopped"
(cd "$TOOLS_DIR" && sg docker -c ./start_vnc.sh)

echo
echo "Done. On your own computer:"
echo "  ./aws-vm.sh start   (or ssh with -L $WEBSERVER_PORT:localhost:$WEBSERVER_PORT)"
echo "  then open http://localhost:$WEBSERVER_PORT in the browser and log in with VNC_PW"
df -h /
