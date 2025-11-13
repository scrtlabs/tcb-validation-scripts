#!/bin/bash

echo "=========================================="
echo "  Current System State - TCB-R 18"
echo "=========================================="
echo ""

echo "--- CPU Information ---"
CPUID_RAW=$(cpuid -1 -r)
FAMILY=$(echo "$CPUID_RAW" | grep "0x00000001" | awk '{print $5}' | cut -d'=' -f2)
MODEL=$(echo "$CPUID_RAW" | grep "0x00000001" | awk '{print $6}' | cut -d'=' -f2)
STEPPING=$(echo "$CPUID_RAW" | grep "0x00000001" | awk '{print $7}' | cut -d'=' -f2)

echo "Family: $FAMILY"
echo "Model: $MODEL"
echo "Stepping: $STEPPING"
echo "CPUID: 0xC06F2 (Emerald Rapids)"
echo ""

echo "--- Current Microcode Version ---"
MCU_CURRENT=$(grep microcode /proc/cpuinfo | head -1 | awk '{print $3}')
echo "Current Microcode: $MCU_CURRENT"
echo ""
echo "TCB-R 18 Requirements:"
echo "  Minimum (IPU 2024.3): >= 0x21000201"
echo "  Recommended (UPLR2):  >= 0x21000290"
echo ""

# Determine compliance
if [[ "$MCU_CURRENT" < "0x21000201" ]]; then
    echo "Status: ❌ NEEDS UPDATE (below TCB-R 18 minimum)"
elif [[ "$MCU_CURRENT" < "0x21000290" ]]; then
    echo "Status: ⚠️  PARTIAL (meets IPU 2024.3, recommend UPLR2)"
elif [[ "$MCU_CURRENT" < "0x210002b3" ]]; then
    echo "Status: ✅ TCB-R 18 COMPLIANT (consider TCB-R 20 upgrade)"
else
    echo "Status: ✅ TCB-R 20 COMPLIANT (newer than TCB-R 18)"
fi
echo ""

echo "--- BIOS Information ---"
sudo dmidecode -t bios | grep -E "Vendor|Version|Release Date"
echo ""

echo "--- TDX Module Version ---"
TDX_VERSION=$(dmesg | grep "virt/tdx.*major_version" | tail -1)
if [ -n "$TDX_VERSION" ]; then
    echo "$TDX_VERSION"

    MAJOR=$(echo "$TDX_VERSION" | grep -oP 'major_version \K\d+')
    MINOR=$(echo "$TDX_VERSION" | grep -oP 'minor_version \K\d+')
    BUILD=$(echo "$TDX_VERSION" | grep -oP 'build_num \K\d+')

    echo "TDX Module: $MAJOR.$MINOR (build $BUILD)"
    echo "TCB-R 18 Required: >= 1.5.06"

    if [ "$MAJOR" -ge 1 ] && [ "$MINOR" -ge 5 ] && [ "$BUILD" -ge 600 ]; then
        echo "Status: ✅ COMPLIANT"
    else
        echo "Status: ❌ NEEDS UPDATE"
    fi
else
    echo "TDX Module: Not loaded or not available"
    echo "Status: ❌ NEEDS UPDATE"
fi
echo ""

echo "--- SEAMLDR Version ---"
SEAMLDR=$(dmesg | grep -i "seamldr.*version" | tail -1)
if [ -n "$SEAMLDR" ]; then
    echo "$SEAMLDR"

    # Extract version (format: X.Y.ZZ)
    VERSION=$(echo "$SEAMLDR" | grep -oP 'version \K[0-9.]+')
    echo "TCB-R 18 Required (5th Gen): >= 2.0.00"

    if [[ "$VERSION" > "2.0" ]] || [[ "$VERSION" == "2.0"* ]]; then
        echo "Status: ✅ COMPLIANT"
    else
        echo "Status: ❌ NEEDS UPDATE"
    fi
else
    echo "SEAMLDR: Not detected"
    echo "Status: ❌ NEEDS UPDATE"
fi
echo ""

echo "--- SGX Status ---"
if [ -c /dev/sgx_enclave ]; then
    echo "SGX Devices: ✅ Present"
    ls -l /dev/sgx*
else
    echo "SGX Devices: ❌ Not found"
fi
echo ""

if systemctl is-active --quiet aesmd; then
    echo "AESMD Service: ✅ Running"

    DCAP_VERSION=$(dpkg -l | grep libsgx-dcap-ql | awk '{print $3}')
    if [ -n "$DCAP_VERSION" ]; then
        echo "SGX DCAP Version: $DCAP_VERSION"
        echo "TCB-R 18 Required: >= 1.14"
    fi
else
    echo "AESMD Service: ❌ Not running"
fi
echo ""

echo "=========================================="
echo "  Current State Check Complete"
echo "=========================================="