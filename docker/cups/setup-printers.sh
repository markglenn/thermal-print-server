#!/bin/bash
set -e

# Start CUPS in the background to configure printers
cupsd

# Wait for CUPS to be ready
for i in $(seq 1 30); do
  if lpstat -r 2>/dev/null | grep -q "scheduler is running"; then
    break
  fi
  sleep 0.5
done

echo "Adding test printers..."

lpadmin -p TestZebra-4x6 \
  -E \
  -v file:///dev/null \
  -m raw \
  -D "Test Zebra 4x6 (null)" \
  -L "Docker"

lpadmin -p TestZebra-4x2 \
  -E \
  -v file:///dev/null \
  -m raw \
  -D "Test Zebra 4x2 (null)" \
  -L "Docker"

lpadmin -p TestZebra-Capture \
  -E \
  -v file:///tmp/cups-capture \
  -m raw \
  -D "Test Zebra Capture (writes to /tmp/cups-capture)" \
  -L "Docker"

lpadmin -p Zebra-2x1 \
  -E \
  -v ipp://192.168.81.238/ipp/print \
  -m everywhere \
  -D "Zebra 2x1 (192.168.81.238)" \
  -L "LAN"

echo "Test printers configured:"
lpstat -p

# Stop background CUPS gracefully
kill "$(cat /var/run/cups/cupsd.pid 2>/dev/null || cat /run/cups/cupsd.pid 2>/dev/null)" 2>/dev/null || true
sleep 1

# Run CUPS in the foreground
echo "Starting CUPS in foreground..."
exec cupsd -f
