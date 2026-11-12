#!/bin/bash

echo "Stopping rsyslog service..."
systemctl stop rsyslog

echo "Truncating main log files..."
truncate -s 0 /var/log/syslog /var/log/btmp* /var/log/auth.log* /var/log/messages* 2>/dev/null
truncate -s 0 /var/log/*.log 2>/dev/null
truncate -s 0 /var/log/*.gz 2>/dev/null
truncate -s 0 /var/log/dpkg.log* /var/log/alternatives.log* /var/log/bootstrap.log /var/log/boot.log /var/log/cron* 2>/dev/null
truncate -s 0 /var/log/fontconfig.log /var/log/gpu-manager.log /var/log/odoocleanup.log /var/log/yum.log /var/log/vmware-* 2>/dev/null

echo "Removing old rotated and numbered logs..."
rm -f /var/log/*-??????? 2>/dev/null
rm -f /var/log/*.[0-9] 2>/dev/null

echo "Cleaning special log files..."
truncate -s 0 /var/log/wtmp /var/log/lastlog /var/log/tallylog /var/log/btmp 2>/dev/null

echo "Clearing sysstat and sa logs if exist..."
truncate -s 0 /var/log/sa/* 2>/dev/null
truncate -s 0 /var/log/sysstat/* 2>/dev/null

echo "Clearing all systemd journal logs..."
# Stop journal service temporarily
systemctl stop systemd-journald
# Remove all journal logs
rm -rf /var/log/journal/* 2>/dev/null
rm -rf /run/log/journal/* 2>/dev/null
# Restart journal service
systemctl start systemd-journald

echo "Starting rsyslog service..."
systemctl start rsyslog

echo "Log cleanup completed successfully."

# Show current /var/log size
du -sh /var/log



