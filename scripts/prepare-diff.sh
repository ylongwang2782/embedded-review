#!/bin/bash
# prepare-diff.sh — Extract git diff and build review context for dual-model review
# Usage: prepare-diff.sh [repo_path] [diff_range]
# Examples:
#   prepare-diff.sh ~/Documents/dec/firmware-pro2          # uncommitted changes
#   prepare-diff.sh ~/Documents/dec/firmware-pro2 HEAD~3..HEAD  # last 3 commits
#   prepare-diff.sh ~/Documents/dec/firmware-pro2 main..feat/nfc  # branch diff

set -euo pipefail

REPO="${1:-.}"
RANGE="${2:-}"

cd "$REPO"

echo "=== REPO INFO ==="
echo "Path: $(pwd)"
echo "Branch: $(git branch --show-current 2>/dev/null || echo 'detached')"
echo "Last commit: $(git log -1 --oneline 2>/dev/null || echo 'none')"

echo ""
echo "=== TARGET IDENTIFICATION ==="
# Detect MCU/RTOS/compiler from CMake or Makefile
grep -r "STM32\|nRF\|ESP32\|ATSAMD\|RP2040" CMakeLists.txt Makefile *.cmake 2>/dev/null | head -5 || true
grep -r "FreeRTOS\|Zephyr\|ThreadX\|CMSIS_RTOS" CMakeLists.txt Makefile 2>/dev/null | head -3 || true
grep -r "arm-none-eabi\|armcc\|iccarm" CMakeLists.txt Makefile 2>/dev/null | head -3 || true

echo ""
echo "=== DIFF STAT ==="
if [ -n "$RANGE" ]; then
    git diff --stat "$RANGE" 2>/dev/null
    echo ""
    echo "=== DIFF ==="
    git diff "$RANGE" 2>/dev/null
else
    # Check for staged + unstaged changes
    STAGED=$(git diff --cached --stat 2>/dev/null)
    UNSTAGED=$(git diff --stat 2>/dev/null)
    
    if [ -n "$STAGED" ] || [ -n "$UNSTAGED" ]; then
        echo "--- Staged ---"
        git diff --cached --stat 2>/dev/null
        echo "--- Unstaged ---"
        git diff --stat 2>/dev/null
        echo ""
        echo "=== DIFF ==="
        git diff --cached 2>/dev/null
        git diff 2>/dev/null
    else
        echo "(No uncommitted changes. Showing last commit diff)"
        git diff HEAD~1 --stat 2>/dev/null
        echo ""
        echo "=== DIFF ==="
        git diff HEAD~1 2>/dev/null
    fi
fi
