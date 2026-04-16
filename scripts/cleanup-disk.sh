#!/bin/bash
echo "=== Disk Cleanup Script ==="
echo "Before cleanup:"
df -h /

echo "Removing large files in /tmp..."
find /tmp -type f -size +100M -delete

echo "Clearing journal logs older than 2 days..."
sudo journalctl --vacuum-time=2d

echo "After cleanup:"
df -h /

echo "=== Cleanup Complete ==="