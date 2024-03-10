#!/bin/bash

# Set the mount path to monitor
MOUNT_PATH="/mnt/proxmox"

# Set the LXC container ID
LXC_CONTAINER_ID="103"

# Check if the mount path is active
if grep -qs "$MOUNT_PATH" /proc/mounts; then
    # Check if the container is stopped
    if ! pct status $LXC_CONTAINER_ID | grep -q "running"; then
        pct start $LXC_CONTAINER_ID
    fi
else
    # Check if the container is running
    if pct status $LXC_CONTAINER_ID | grep -q "running"; then
        pct stop $LXC_CONTAINER_ID
    fi
fi
