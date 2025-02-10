#!/bin/bash

# Ensure the script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Function to find the next available VM ID
find_next_vm_id() {
    LAST_USED_ID=$(qm list | awk '{print $1}' | grep -E '^[0-9]+$' | sort -n | tail -1)
    if [ -z "$LAST_USED_ID" ]; then
        NEXT_ID=100
    else
        NEXT_ID=$((LAST_USED_ID + 1))
    fi

    # Ensure the VM ID is not already in use (for both VMs and containers)
    while qm list | grep -q "^$NEXT_ID " || pct list | grep -q "^$NEXT_ID "; do
        NEXT_ID=$((NEXT_ID + 1))
    done

    echo "$NEXT_ID"
}

# Generate a random password for the administrator account
generate_password() {
    echo "$(openssl rand -base64 12)"
}

# Prompt for user input or use defaults
read -p "Enter VM name [Windows10]: " VM_NAME
VM_NAME=${VM_NAME:-Windows10}

# Ensure the VM name is in a valid format (replace spaces with hyphens)
VM_NAME=$(echo "$VM_NAME" | tr ' ' '-')
echo "-> Using VM name: $VM_NAME"

read -p "Enter memory size in MB [4096]: " MEMORY
MEMORY=${MEMORY:-4096}
echo "-> Using memory size: $MEMORY MB"

read -p "Enter disk size in GB [100]: " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-100}
echo "-> Using disk size: $DISK_SIZE GB"

# Ensure the ISO directory exists
ISO_DIR="/var/lib/vz/template/iso"
mkdir -p "$ISO_DIR" || {
    echo "Error: Failed to create ISO directory. Exiting."
    exit 1
}

# Specify the Windows 10 ISO to download
WIN10_ISO_URL="https://dl.bobpony.com/windows/10/en-us_windows_10_22h2_x64.iso"
ISO_PATH="$ISO_DIR/Windows10.iso"

# Attempt to download the Windows 10 ISO
echo "Downloading Windows 10 ISO..."
wget -O "$ISO_PATH" "$WIN10_ISO_URL" || {
    echo "Failed to download Windows 10 ISO. Please provide the path to an existing Windows 10 ISO."
    read -p "Enter the full path or URL to the Windows 10 ISO: " ISO_PATH

    # Check if the input is a URL (starts with http:// or https://)
    if [[ "$ISO_PATH" =~ ^https?:// ]]; then
        echo "Downloading ISO from provided URL: $ISO_PATH"
        wget -O "$ISO_DIR/Windows10.iso" "$ISO_PATH" || {
            echo "Error: Failed to download ISO from the provided URL. Exiting."
            exit 1
        }
    else
        # Check if the local file exists
        if [ -f "$ISO_PATH" ]; then
            echo "Using local ISO file: $ISO_PATH"
            cp "$ISO_PATH" "$ISO_DIR/Windows10.iso" || {
                echo "Error: Failed to copy the local ISO file. Exiting."
                exit 1
            }
        else
            echo "Error: The specified ISO file does not exist. Exiting."
            exit 1
        fi
    fi
}

echo "ISO downloaded successfully."

# Generate a random password
ADMIN_PASSWORD=$(generate_password)
echo "Generated administrator password: $ADMIN_PASSWORD"

# Create the autounattend.xml file
AUTOUATTEND_PATH="$ISO_DIR/autounattend.xml"
cat <<EOF > "$AUTOUATTEND_PATH"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <!-- XML content omitted for brevity -->
</unattend>
EOF

# Find the next available VM ID
VM_ID=$(find_next_vm_id)
echo "-> Using VM ID: $VM_ID"

# Validate storage path
STORAGE_PATH="/var/lib/vz/images/$VM_ID"
if [ ! -d "$STORAGE_PATH" ]; then
    echo "Creating storage directory: $STORAGE_PATH"
    mkdir -p "$STORAGE_PATH" || {
        echo "Error: Failed to create storage directory. Please check permissions or storage configuration."
        exit 1
    }
fi

# Create a new VM in Proxmox
echo "Creating VM $VM_ID ($VM_NAME)..."
qm create "$VM_ID" --name "$VM_NAME" --memory "$MEMORY" --cpu host --net0 virtio,bridge=vmbr0 || {
    echo "Error: Failed to create VM $VM_ID. Please check if the VM ID is already in use."
    echo "Logs can be found at: /var/log/pve/tasks/active"
    exit 1
}

# Add a SATA hard drive to the VM
echo "Adding disk to VM..."
qm set "$VM_ID" --scsi0 "local-lvm:vm-$VM_ID-disk-0,size=${DISK_SIZE}G" || {
    echo "Error: Failed to add disk to VM. Please check if the storage path is valid."
    echo "Logs can be found at: /var/log/pve/tasks/active"
    exit 1
}

# Attach the Windows 10 ISO to the VM's CD/DVD drive
echo "Attaching ISO to VM..."
qm set "$VM_ID" --ide2 "local:iso/Windows10.iso,media=cdrom" || {
    echo "Error: Failed to attach ISO to VM. Please check if the ISO path is valid."
    echo "Logs can be found at: /var/log/pve/tasks/active"
    exit 1
}

# Attach the autounattend.xml file to the VM
echo "Attaching autounattend.xml..."
qm set "$VM_ID" --ide3 "local:iso/autounattend.xml,media=cdrom" || {
    echo "Error: Failed to attach autounattend.xml to VM. Please check if the file path is valid."
    echo "Logs can be found at: /var/log/pve/tasks/active"
    exit 1
}

# Set the VM to use the "host" CPU type for better performance
echo "Configuring CPU..."
qm set "$VM_ID" --cpu host || {
    echo "Error: Failed to configure CPU."
    echo "Logs can be found at: /var/log/pve/tasks/active"
    exit 1
}

# Enable the QXL display driver for improved performance
echo "Configuring display..."
qm set "$VM_ID" --vga qxl || {
    echo "Error: Failed to configure display."
    echo "Logs can be found at: /var/log/pve/tasks/active"
    exit 1
}

# Start the VM
echo "Starting VM..."
qm start "$VM_ID" || {
    echo "Error: Failed to start VM $VM_ID. Please check the Proxmox logs for more details."
    echo "Logs can be found at: /var/log/pve/tasks/active"
    exit 1
}

echo "VM $VM_ID started successfully."
echo "Administrator password: $ADMIN_PASSWORD"
