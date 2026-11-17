#!/usr/bin/env bash
# Starts, stops or checks the EC2 VM; "start" also connects via SSH through AWS Session Manager (no open ports, no changing IPs).
# Usage: ./aws-vm.sh start | stop | status
# Needs: AWS CLI v2, session-manager-plugin, "aws configure" done, SSH host entry with ProxyCommand (see README).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# local settings (INSTANCE_ID, AWS_REGION, SSH_HOST), not in Git
[ -f "$SCRIPT_DIR/aws-vm.env" ] && . "$SCRIPT_DIR/aws-vm.env"

: "${INSTANCE_ID:?Set INSTANCE_ID in aws-vm.env (see aws-vm.env.example)}"
REGION="${AWS_REGION:-eu-central-1}"
SSH_HOST="${SSH_HOST:-aws-eda}"   # Host entry in ~/.ssh/config
DESKTOP_PORT="${DESKTOP_PORT:-8080}"   # local port of the desktop tunnel (LocalForward)

vm_state() {
    aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' --output text
}

ssm_status() {
    aws ssm describe-instance-information --region "$REGION" \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0].PingStatus' --output text
}

case "${1:-}" in
    start)
        if [ "$(vm_state)" != "running" ]; then
            aws ec2 start-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
            echo "Starting $INSTANCE_ID ..."
            aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
        fi
        echo "Waiting for the SSM agent ..."
        for _ in $(seq 60); do   # up to 5 minutes
            [ "$(ssm_status)" = "Online" ] && break
            sleep 5
        done
        [ "$(ssm_status)" = "Online" ] || { echo "SSM agent not online, check the IAM role of the VM" >&2; exit 1; }
        echo "Connecting, desktop at http://localhost:$DESKTOP_PORT"
        exec ssh "$SSH_HOST"
        ;;
    stop)
        aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
        echo "Stopping $INSTANCE_ID (disk is kept, compute time is no longer charged)"
        ;;
    status)
        state="$(vm_state)"
        ssm="$(ssm_status)"
        echo "VM:      $state"
        echo "SSM:     $ssm"
        if [ "$state" = "running" ] && [ "$ssm" = "Online" ]; then
            # separate short SSH call without port forwarding, so it works next to an open session
            desktop="$(ssh -o BatchMode=yes -o ClearAllForwardings=yes "$SSH_HOST" \
                "docker ps --filter name=iic-osic-tools --format '{{.Status}}'" 2>/dev/null || true)"
            echo "Desktop: ${desktop:-not running}"
        else
            echo "Desktop: -"
        fi
        # local end of the SSH tunnel, only open while "start" or "ssh $SSH_HOST" is connected
        if (exec 3<>"/dev/tcp/127.0.0.1/$DESKTOP_PORT") 2>/dev/null; then
            echo "Tunnel:  open, http://localhost:$DESKTOP_PORT"
        else
            echo "Tunnel:  closed, connect with: $(basename "$0") start"
        fi
        ;;
    *)
        echo "Usage: $0 start | stop | status" >&2
        exit 2
        ;;
esac
