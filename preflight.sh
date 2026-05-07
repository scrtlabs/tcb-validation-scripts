#!/bin/bash
#
# Install required tools
sudo apt update
sudo apt install -y \
    cpuid \
    msr-tools \
    dmidecode \
    pciutils \
    wget \
    curl \
    jq \
    pv

# Check if you have root/sudo access
sudo -v

# Verify internet connectivity
ping -c 3 8.8.8.8

# Check available disk space (need at least 2GB)
df -h /boot /tmp