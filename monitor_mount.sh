#!/bin/bash

# Set the mount path to monitor
MOUNT_PATH="/mnt/proxmox"

# Set the LXC container ID
LXC_CONTAINER_ID="103"

# Check if the mount path is active
if grep -qs "$MOUNT_PATH" /proc/mounts; then
    echo "Mount path is active."
    
    # Check if the container is stopped
    if ! pct status $LXC_CONTAINER_ID | grep -q "running"; then
        echo "Container is stopped. Starting container..."
        pct start $LXC_CONTAINER_ID
        echo "Container started."
    else
        echo "Container is already running."
    fi
else
    echo "Mount path is inactive."
    
    # Check if the container is running
    if pct status $LXC_CONTAINER_ID | grep -q "running"; then
        echo "Container is running. Stopping container..."
        pct stop $LXC_CONTAINER_ID
        echo "Container stopped."
    else
        echo "Container is already stopped."
    fi
fi