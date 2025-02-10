#!/bin/bash

# Function to find the next available VM ID
find_next_vm_id() {
    # Get the list of used VM IDs, sort them numerically, and get the highest one
    LAST_USED_ID=$(qm list | awk '{print $1}' | grep -E '^[0-9]+$' | sort -n | tail -1)

    # If no VMs exist, start with ID 100 (or any default starting ID)
    if [ -z "$LAST_USED_ID" ]; then
        NEXT_ID=100
    else
        NEXT_ID=$((LAST_USED_ID + 1))
    fi

    echo "$NEXT_ID"
}

# Specify the Windows 10 ISO to download
WIN10_ISO_URL="https://software-download.microsoft.com/download/pr/19043.1165.210529-1541.co_release_CLIENT_CONSUMER_x64FRE_en-us.iso"
ISO_PATH="/var/lib/vz/template/iso/Windows10.iso"

# Download the Windows 10 ISO
echo "Downloading Windows 10 ISO..."
wget -O "$ISO_PATH" "$WIN10_ISO_URL"

# Check if the ISO was downloaded successfully
if [ ! -f "$ISO_PATH" ]; then
    echo "Failed to download Windows 10 ISO. Please download it manually and place it in $ISO_PATH."
    exit 1
fi

# Find the next available VM ID
VM_ID=$(find_next_vm_id)
VM_NAME="Windows10"
echo "Using VM ID: $VM_ID"

# Create a new VM in Proxmox
echo "Creating VM $VM_ID ($VM_NAME)..."
qm create "$VM_ID" --name "$VM_NAME" --memory 4096 --cpu host --net0 virtio,bridge=vmbr0

# Add a SATA hard drive to the VM
echo "Adding disk to VM..."
mkdir -p /var/lib/vz/images/"$VM_ID"
qm set "$VM_ID" --scsihw virtio-scsi-pci --scsi0 /var/lib/vz/images/"$VM_ID"/vm-"$VM_ID"-disk-0.qcow2,ssd=1,size=100G

# Attach the Windows 10 ISO to the VM's CD/DVD drive
echo "Attaching ISO to VM..."
qm set "$VM_ID" --ide2 "$ISO_PATH",media=cdrom

# Set the VM to use the "host" CPU type for better performance
echo "Configuring CPU..."
qm set "$VM_ID" --cpu host

# Enable the QXL display driver for improved performance
echo "Configuring display..."
qm set "$VM_ID" --vga qxl

# Add a Spice console to the VM for remote desktop access
echo "Configuring SPICE..."
qm set "$VM_ID" --spicehw virtio-vga --spiceport 5900 --password mypassword

# Set the SMBIOS UUID to a unique value for each VM
echo "Setting SMBIOS UUID..."
qm set "$VM_ID" --smbios1 uuid=$(uuidgen)

# Start the VM
echo "Starting VM..."
if qm status "$VM_ID" >/dev/null 2>&1; then
    qm start "$VM_ID"
    echo "VM $VM_ID started successfully."
else
    echo "Failed to start VM $VM_ID. Please check the logs."
    exit 1
fi
