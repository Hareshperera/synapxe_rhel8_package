#!/bin/bash
# Synapxe RHEL 8 Remediation Script - 2025 Baseline

log() {
  echo -e "$1"
}

log "Starting remediation for kernel modules..."
modules=(cramfs freevxfs hfs hfsplus jffs2 squashfs udf usb-storage)
for mod in "${modules[@]}"; do
  echo "install $mod /bin/false" > /etc/modprobe.d/$mod.conf
  echo "blacklist $mod" >> /etc/modprobe.d/$mod.conf
done

log "Remediating mount options for /tmp, /dev/shm, /var/tmp, /var, /var/log, /var/log/audit, /home..."
mount -o remount,nodev,nosuid,noexec /tmp
mount -o remount,nodev,nosuid,noexec /dev/shm
mount -o remount,nodev,nosuid,noexec /var/tmp
mount -o remount,nodev,nosuid,noexec /var
mount -o remount,nodev,nosuid,noexec /var/log
mount -o remount,nodev,nosuid,noexec /var/log/audit
mount -o remount,nodev,nosuid,noexec /home

log "Enabling SELinux..."
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
setenforce 1

log "Hardening sysctl settings..."
sysctl -w kernel.kptr_restrict=1
sysctl -w fs.protected_hardlinks=1
sysctl -w fs.protected_symlinks=1
sysctl -w kernel.dmesg_restrict=1

log "Setting SSH configurations..."
sshd_config="/etc/ssh/sshd_config"
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' $sshd_config
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 4/' $sshd_config
sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' $sshd_config
sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 3/' $sshd_config
sed -i 's/^#*UsePAM.*/UsePAM yes/' $sshd_config
systemctl restart sshd

log "Setting login.defs parameters..."
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs

log "Remediation complete. Reboot may be required for full enforcement."#!/bin/bash
# Synapxe RHEL 8 Remediation Script - 2025 Baseline

log() {
  echo -e "$1"
}

log "Starting remediation for kernel modules..."
modules=(cramfs freevxfs hfs hfsplus jffs2 squashfs udf usb-storage)
for mod in "${modules[@]}"; do
  echo "install $mod /bin/false" > /etc/modprobe.d/$mod.conf
  echo "blacklist $mod" >> /etc/modprobe.d/$mod.conf
done

log "Remediating mount options for /tmp, /dev/shm, /var/tmp..."
mount -o remount,nodev,nosuid,noexec /tmp
mount -o remount,nodev,nosuid,noexec /dev/shm
mount -o bind /tmp /var/tmp

log "Enabling SELinux..."
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
setenforce 1

log "Hardening sysctl settings..."
sysctl -w kernel.kptr_restrict=1
sysctl -w fs.protected_hardlinks=1
sysctl -w fs.protected_symlinks=1
sysctl -w kernel.dmesg_restrict=1

log "Setting SSH configurations..."
sshd_config="/etc/ssh/sshd_config"
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' $sshd_config
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 4/' $sshd_config
sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' $sshd_config
sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 3/' $sshd_config
sed -i 's/^#*UsePAM.*/UsePAM yes/' $sshd_config
systemctl restart sshd

log "Setting login.defs parameters..."
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs

log "Remediation complete. Reboot may be required for full enforcement."
