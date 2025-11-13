#!/bin/bash

echo "=========================================="
echo "  TDX Failure Diagnostic Report"
echo "  Generated: $(date)"
echo "=========================================="
echo ""

# System Identity
echo "=== SYSTEM IDENTITY ==="
echo "Hostname: $(hostname)"
echo "Serial: $(sudo dmidecode -t system 2>/dev/null | grep "Serial Number" | cut -d: -f2 | xargs)"
MANUFACTURER=$(sudo dmidecode -t system 2>/dev/null | grep "Manufacturer" | cut -d: -f2 | xargs)
PRODUCT=$(sudo dmidecode -t system 2>/dev/null | grep "Product Name" | cut -d: -f2 | xargs)
echo "Manufacturer: $MANUFACTURER"
echo "Model: $PRODUCT"
echo ""

# CPU Info
echo "=== CPU INFORMATION ==="
CPUID_FAMILY=$(cpuid -1 -r 2>/dev/null | grep "0x00000001" | awk '{print $5}' | cut -d'=' -f2)
CPUID_MODEL=$(cpuid -1 -r 2>/dev/null | grep "0x00000001" | awk '{print $6}' | cut -d'=' -f2)
CPUID_STEPPING=$(cpuid -1 -r 2>/dev/null | grep "0x00000001" | awk '{print $7}' | cut -d'=' -f2)
echo "CPUID Family: $CPUID_FAMILY"
echo "CPUID Model: $CPUID_MODEL"
echo "CPUID Stepping: $CPUID_STEPPING"
echo "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
echo ""

# Microcode
echo "=== MICROCODE ==="
MCU=$(grep microcode /proc/cpuinfo | head -1 | awk '{print $3}')
echo "Current: $MCU"
echo "TCB-R 20 Required: 0x210002B3"
if [[ "$MCU" < "0x210002b3" ]]; then
    echo "Status: ❌ TOO OLD - This could prevent TDX"
else
    echo "Status: ✅ OK"
fi
echo ""

# BIOS
echo "=== BIOS INFORMATION ==="
sudo dmidecode -t bios 2>/dev/null | grep -E "Vendor|Version|Release Date"
echo ""

# Kernel
echo "=== KERNEL ==="
echo "Version: $(uname -r)"
echo "CONFIG_INTEL_TDX_HOST: $(grep CONFIG_INTEL_TDX_HOST /boot/config-$(uname -r) 2>/dev/null || echo 'NOT FOUND')"
echo "CONFIG_TDX_GUEST_DRIVER: $(grep CONFIG_TDX_GUEST_DRIVER /boot/config-$(uname -r) 2>/dev/null || echo 'NOT FOUND')"
echo ""

# Kernel Parameters
echo "=== KERNEL PARAMETERS ==="
echo "Full command line:"
cat /proc/cmdline
echo ""
echo "TDX-related parameters:"
cat /proc/cmdline | grep -o 'kvm_intel.tdx=[^ ]*' || echo "kvm_intel.tdx: NOT SET"
cat /proc/cmdline | grep -o 'intel_iommu=[^ ]*' || echo "intel_iommu: NOT SET"
echo ""

# TDX in BIOS
echo "=== TDX BIOS STATUS ==="
if sudo dmesg | grep -q "virt/tdx: BIOS enabled"; then
    echo "✅ TDX enabled in BIOS"
    sudo dmesg | grep "virt/tdx: BIOS enabled"
elif sudo journalctl -b 0 --no-pager 2>/dev/null | grep -q "virt/tdx: BIOS enabled"; then
    echo "✅ TDX enabled in BIOS (from journalctl)"
    sudo journalctl -b 0 --no-pager | grep "virt/tdx: BIOS enabled"
else
    echo "❌ TDX NOT enabled in BIOS"
fi
echo ""

# TDX Module Status
echo "=== TDX MODULE STATUS ==="
echo "From dmesg:"
if sudo dmesg | grep -q "virt/tdx"; then
    sudo dmesg | grep "virt/tdx" | head -10
else
    echo "❌ No TDX messages in dmesg"
fi
echo ""

echo "From journalctl (current boot):"
if sudo journalctl -b 0 --no-pager 2>/dev/null | grep -q "virt/tdx"; then
    sudo journalctl -b 0 --no-pager | grep "virt/tdx" | head -10
else
    echo "❌ No TDX messages in journalctl"
fi
echo ""

# TDX Module Load Status
echo "=== TDX INITIALIZATION ==="
if sudo dmesg | grep -q "virt/tdx: module initialized"; then
    echo "✅ TDX module initialized (dmesg)"
elif sudo journalctl -b 0 --no-pager 2>/dev/null | grep -q "virt/tdx: module initialized"; then
    echo "✅ TDX module initialized (journalctl)"
else
    echo "❌ TDX module NOT initialized"
fi
echo ""

# Check for TDX errors
echo "=== TDX ERRORS ==="
TDX_ERRORS=$(sudo dmesg 2>/dev/null | grep -i "tdx.*error\|tdx.*fail" | head -5)
if [ -n "$TDX_ERRORS" ]; then
    echo "⚠️  Errors found in dmesg:"
    echo "$TDX_ERRORS"
else
    echo "No explicit TDX errors in dmesg"
fi

TDX_JOURNAL_ERRORS=$(sudo journalctl -b 0 --no-pager 2>/dev/null | grep -i "tdx.*error\|tdx.*fail" | head -5)
if [ -n "$TDX_JOURNAL_ERRORS" ]; then
    echo "⚠️  Errors found in journalctl:"
    echo "$TDX_JOURNAL_ERRORS"
fi
echo ""

# KVM TDX Parameter
echo "=== KVM TDX STATUS ==="
if [ -f /sys/module/kvm_intel/parameters/tdx ]; then
    KVM_TDX=$(cat /sys/module/kvm_intel/parameters/tdx)
    echo "kvm_intel.tdx = $KVM_TDX"
    if [ "$KVM_TDX" == "Y" ]; then
        echo "✅ TDX enabled in KVM module"
    else
        echo "❌ TDX disabled in KVM module"
    fi
else
    echo "❌ /sys/module/kvm_intel/parameters/tdx not found"
    echo "   (KVM module may not be loaded or kernel lacks TDX support)"
fi
echo ""

# Check if kvm_intel is loaded
echo "=== KVM MODULE ==="
if lsmod | grep -q kvm_intel; then
    echo "✅ kvm_intel module loaded"
    lsmod | grep kvm_intel
else
    echo "❌ kvm_intel module NOT loaded"
fi
echo ""

# IOMMU Status
echo "=== IOMMU STATUS ==="
if dmesg | grep -q "DMAR: IOMMU enabled"; then
    echo "✅ IOMMU enabled"
    dmesg | grep "DMAR.*IOMMU" | head -3
else
    echo "❌ IOMMU not enabled or not found"
fi
echo ""

# TME Status
echo "=== TME (Total Memory Encryption) ==="
if dmesg | grep -q "x86/tme"; then
    echo "✅ TME detected"
    dmesg | grep "x86/tme"
else
    echo "❌ TME not detected"
fi
echo ""

# CPU Features
echo "=== CPU FEATURES ==="
echo "TDX support: $(cpuid 2>/dev/null | grep -i tdx || echo 'NOT FOUND')"
echo "SGX support: $(cpuid 2>/dev/null | grep -i sgx || echo 'NOT FOUND')"
echo "TME support: $(cpuid 2>/dev/null | grep -i tme || echo 'NOT FOUND')"
echo ""

# SEAMLDR
echo "=== SEAMLDR ==="
if sudo dmesg | grep -qi seamldr; then
    sudo dmesg | grep -i seamldr
    echo "✅ SEAMLDR messages found"
elif sudo journalctl -b 0 --no-pager 2>/dev/null | grep -qi seamldr; then
    sudo journalctl -b 0 --no-pager | grep -i seamldr
    echo "✅ SEAMLDR messages found (journalctl)"
else
    echo "⚠️  No SEAMLDR messages (may load silently)"
fi
echo ""

# Summary
echo "=========================================="
echo "  DIAGNOSTIC SUMMARY"
echo "=========================================="
echo ""

# Check critical components
ISSUES=0

if [[ "$MCU" < "0x210002b3" ]]; then
    echo "❌ ISSUE: Microcode too old ($MCU)"
    ((ISSUES++))
fi

if ! grep -q "CONFIG_INTEL_TDX_HOST=y" /boot/config-$(uname -r) 2>/dev/null; then
    echo "❌ ISSUE: Kernel lacks TDX host support"
    ((ISSUES++))
fi

if ! cat /proc/cmdline | grep -q "kvm_intel.tdx="; then
    echo "❌ ISSUE: kvm_intel.tdx kernel parameter not set"
    ((ISSUES++))
fi

if ! cat /proc/cmdline | grep -q "intel_iommu=on"; then
    echo "⚠️  WARNING: intel_iommu=on not set (may be required)"
fi

if ! sudo dmesg 2>/dev/null | grep -q "virt/tdx" && ! sudo journalctl -b 0 --no-pager 2>/dev/null | grep -q "virt/tdx"; then
    echo "❌ ISSUE: No TDX kernel messages found"
    ((ISSUES++))
fi

if [ $ISSUES -eq 0 ]; then
    echo ""
    echo "✅ No critical issues detected"
    echo "   TDX should be working or requires BIOS settings"
else
    echo ""
    echo "⚠️  Found $ISSUES critical issue(s) preventing TDX"
fi

echo ""
echo "=========================================="
echo "  Save this output and compare with working server"
echo "=========================================="