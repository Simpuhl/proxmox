#!/bin/bash

# Function to find the next available VM ID
find_next_vm_id() {
    LAST_USED_ID=$(qm list | awk '{print $1}' | grep -E '^[0-9]+$' | sort -n | tail -1)
    if [ -z "$LAST_USED_ID" ]; then
        NEXT_ID=100
    else
        NEXT_ID=$((LAST_USED_ID + 1))
    fi
    echo "$NEXT_ID"
}

# Generate a random password for the administrator account
generate_password() {
    echo "$(openssl rand -base64 12)"
}

# Prompt for user input or use defaults
read -p "Enter VM name [Windows10]: " VM_NAME
VM_NAME=${VM_NAME:-Windows10}

read -p "Enter memory size in MB [4096]: " MEMORY
MEMORY=${MEMORY:-4096}

read -p "Enter disk size in GB [100]: " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-100}

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

# Generate a random password
ADMIN_PASSWORD=$(generate_password)
echo "Generated administrator password: $ADMIN_PASSWORD"

# Create the autounattend.xml file
AUTOUATTEND_PATH="/var/lib/vz/template/iso/autounattend.xml"
cat <<EOF > "$AUTOUATTEND_PATH"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SetupUILanguage>
                <UILanguage>en-US</UILanguage>
            </SetupUILanguage>
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <UserData>
                <AcceptEula>true</AcceptEula>
                <FullName>Admin</FullName>
                <Organization>Proxmox</Organization>
            </UserData>
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <CreatePartition wcm:action="add">
                            <Order>1</Order>
                            <Type>Primary</Type>
                            <Size>100000</Size>
                        </CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add">
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Format>NTFS</Format>
                            <Label>OS</Label>
                        </ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>1</PartitionID>
                    </InstallTo>
                </OSImage>
            </ImageInstall>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <SkipMachineOOBE>true</SkipMachineOOBE>
                <SkipUserOOBE>true</SkipUserOOBE>
            </OOBE>
            <UserAccounts>
                <AdministratorPassword>
                    <Value>$ADMIN_PASSWORD</Value>
                    <PlainText>true</PlainText>
                </AdministratorPassword>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Password>
                            <Value>$ADMIN_PASSWORD</Value>
                            <PlainText>true</PlainText>
                        </Password>
                        <DisplayName>Admin</DisplayName>
                        <Group>Administrators</Group>
                        <Name>Admin</Name>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
            <AutoLogon>
                <Password>
                    <Value>$ADMIN_PASSWORD</Value>
                    <PlainText>true</PlainText>
                </Password>
                <Username>Admin</Username>
                <Enabled>true</Enabled>
                <LogonCount>1</LogonCount>
            </AutoLogon>
        </component>
    </settings>
</unattend>
EOF

# Find the next available VM ID
VM_ID=$(find_next_vm_id)
echo "Using VM ID: $VM_ID"

# Create a new VM in Proxmox
echo "Creating VM $VM_ID ($VM_NAME)..."
qm create "$VM_ID" --name "$VM_NAME" --memory "$MEMORY" --cpu host --net0 virtio,bridge=vmbr0

# Add a SATA hard drive to the VM
echo "Adding disk to VM..."
mkdir -p /var/lib/vz/images/"$VM_ID"
qm set "$VM_ID" --scsihw virtio-scsi-pci --scsi0 /var/lib/vz/images/"$VM_ID"/vm-"$VM_ID"-disk-0.qcow2,ssd=1,size="$DISK_SIZE"G

# Attach the Windows 10 ISO to the VM's CD/DVD drive
echo "Attaching ISO to VM..."
qm set "$VM_ID" --ide2 "$ISO_PATH",media=cdrom

# Attach the autounattend.xml file to the VM
echo "Attaching autounattend.xml..."
qm set "$VM_ID" --ide3 "$AUTOUATTEND_PATH",media=cdrom

# Set the VM to use the "host" CPU type for better performance
echo "Configuring CPU..."
qm set "$VM_ID" --cpu host

# Enable the QXL display driver for improved performance
echo "Configuring display..."
qm set "$VM_ID" --vga qxl

# Start the VM
echo "Starting VM..."
if qm status "$VM_ID" >/dev/null 2>&1; then
    qm start "$VM_ID"
    echo "VM $VM_ID started successfully."
    echo "Administrator password: $ADMIN_PASSWORD"
else
    echo "Failed to start VM $VM_ID. Please check the logs."
    exit 1
fi
