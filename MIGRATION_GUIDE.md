# Migration Guide: v1.x → v2.0.0

This guide helps you migrate from the previous version (v1.x) to v2.0.0 with all security and feature improvements.

---

## 🔄 Breaking Changes

### 1. Configuration System

**v1.x**: No central configuration
**v2.0.0**: Uses `~/.config/linux-setting/config` for all settings

**Migration**:
```bash
# Create configuration directory
mkdir -p ~/.config/linux-setting

# Copy default configuration
cp config/linux-setting.conf ~/.config/linux-setting/config

# Customize as needed
vim ~/.config/linux-setting/config
```

### 2. Logging System

**v1.x**: Simple text logging without rotation
**v2.0.0**: Structured logging with automatic rotation

**Migration**:
```bash
# Old logs remain in ~/.local/log/linux-setting/
# New logs include JSON format option
# Configure in config file:
# LOG_FORMAT=json  # or "text"
```

### 3. Security Changes

**v1.x**: No signature verification, unsafe PPA additions
**v2.0.0**: GPG verification by default, secure PPAs

**Impact**:
- First run may be slower (downloading GPG keys)
- Some PPAs may require manual key import
- Failed signature verification will block installation

**Migration**:
```bash
# If you previously disabled security features, you can still do so:
ENABLE_GPG_VERIFY=false ./install.sh
ENABLE_SECURE_DOWNLOAD=false ./install.sh
```

---

## 📦 New Features

### 1. Configuration File

Create `~/.config/linux-setting/config` with your preferred settings:

```bash
# ~/.config/linux-setting/config

# Performance
ENABLE_PARALLEL_INSTALL=true
PARALLEL_JOBS=8

# Security
ENABLE_GPG_VERIFY=true
MAX_SCRIPT_SIZE=2097152  # 2MB

# Logging
LOG_FORMAT=json
MAX_LOG_SIZE=10  # 10MB
MAX_LOG_AGE=30  # days

# Package preferences
PREFER_HOMEBREW=true
PREFER_UV=true
```

### 2. Enhanced Security

**GPG Signature Verification**:
```bash
# Automatic for remote scripts
# Optional: Add your own GPG key
export GPG_KEY="-----BEGIN PGP PUBLIC KEY BLOCK-----
...your key...
-----END PGP PUBLIC KEY BLOCK-----"
```

**Safe Download Mechanism**:
```bash
# Validates script size before downloading
# Checks for dangerous patterns
# Limits download timeout
DOWNLOAD_TIMEOUT=120
MAX_SCRIPT_SIZE=5242880  # 5MB
```

### 3. Log Rotation

Automatic management of log files:
- **Size limit**: Compresses logs when they reach MAX_LOG_SIZE (default: 10MB)
- **Age limit**: Removes logs older than MAX_LOG_AGE (default: 30 days)
- **Count limit**: Keeps only MAX_LOG_COUNT files (default: 10)

**Configuration**:
```bash
# In ~/.config/linux-setting/config
MAX_LOG_SIZE=50       # 50MB
MAX_LOG_AGE=7         # 7 days
MAX_LOG_COUNT=20       # 20 files
```

### 4. Structured Logging

JSON format for programmatic parsing:

```bash
# Enable JSON logging
LOG_FORMAT=json ./install.sh

# Example output:
# {"timestamp":"2024-01-01T12:00:00","level":"INFO","pid":12345,"message":"Installing base tools"}
```

Parse with `jq`:
```bash
# Count errors
LOG_FORMAT=json ./install.sh 2>&1 | jq 'select(.level=="ERROR") | length'

# Get all INFO messages
LOG_FORMAT=json ./install.sh 2>&1 | jq 'select(.level=="INFO")'

# Export to CSV
LOG_FORMAT=json ./install.sh 2>&1 | jq -r '[.timestamp, .level, .message] | @csv' > install.log.csv
```

### 5. Improved Package Installation

**Multi-method fallback**:
```bash
# Automatically tries:
# 1. Homebrew (fast, pre-compiled)
# 2. Cargo (fast Rust tools)
# 3. PIP (Python tools)
# 4. APT/dnf/pacman (system packages)
```

**Configuration**:
```bash
# Disable Homebrew preference
PREFER_HOMEBREW=false

# Disable uv preference
PREFER_UV=false

# Force reinstall even if package exists
FORCE_REINSTALL=true
```

---

## 🔧 Migration Steps

### Step 1: Backup Current Configuration

```bash
# Backup all configuration files
mkdir -p ~/backup-linux-setting-v1
cp ~/.zshrc ~/backup-linux-setting-v1/
cp ~/.p10k.zsh ~/backup-linux-setting-v1/ 2>/dev/null || true
cp -r ~/.config/nvim ~/backup-linux-setting-v1/ 2>/dev/null || true

# Backup old logs
cp -r ~/.local/log/linux-setting ~/backup-linux-setting-v1/logs 2>/dev/null || true
```

### Step 2: Clean Old Installation (Optional)

```bash
# Run uninstall script to clean packages
./uninstall.sh -y

# This keeps backups but removes installed packages
```

### Step 3: Create New Configuration

```bash
# Create configuration directory
mkdir -p ~/.config/linux-setting

# Copy and edit default config
cp config/linux-setting.conf ~/.config/linux-setting/config
vim ~/.config/linux-setting/config
```

### Step 4: Install New Version

```bash
# Run new installation script
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)"

# Select your preferred modules during installation
```

### Step 5: Restore Customizations

```bash
# Manually merge your custom settings from backup
# The new configuration file structure is different, so review carefully

# Example: Restore custom aliases
cat ~/backup-linux-setting-v1/.zshrc | grep "^alias " >> ~/.zshrc

# Example: Restore custom plugins
vim ~/.zshrc
# Add your custom zsh plugins from backup
```

### Step 6: Verify Installation

```bash
# Run health check
./scripts/health_check.sh

# Run security audit
./tests/security_audit.sh

# Run unit tests
./tests/test_common_library.sh
```

---

## 🎯 Common Migration Scenarios

### Scenario 1: Keeping Old Configuration

**Problem**: You have customized `.zshrc`, `.p10k.zsh`, etc.

**Solution**: New scripts will create backups automatically

```bash
# Check backups
ls -la ~/.config/linux-setting-backup/

# Manually restore if needed
cp ~/.config/linux-setting-backup/20240101_120000/.zshrc ~/
```

### Scenario 2: Custom Repository Fork

**Problem**: You use a fork of the repository

**Solution**: Update your fork with new changes

```bash
# Add upstream remote
git remote add upstream https://github.com/guan4tou2/my-linux-setting.git

# Fetch upstream
git fetch upstream

# Merge or rebase
git merge upstream/main

# Or create a new branch with v2 features
git checkout -b upgrade-to-v2 upstream/main
```

### Scenario 3: CI/CD Integration

**Problem**: Your CI pipeline breaks with security features

**Solution**: Disable GPG verification in CI

```bash
# In your CI configuration
export ENABLE_GPG_VERIFY=false
export ENABLE_SECURE_DOWNLOAD=false
export TUI_MODE=quiet

# Run installation
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)" --minimal
```

### Scenario 4: Limited Network

**Problem**: Downloading GPG keys fails due to network restrictions

**Solution**: Disable security features temporarily

```bash
# Disable GPG verification
ENABLE_GPG_VERIFY=false ./install.sh

# Or increase timeout
DOWNLOAD_TIMEOUT=120 ./install.sh
```

### Scenario 5: ARM64 Platform

**Problem**: Some tools don't have ARM64 packages

**Solution**: New version has improved ARM64 support

```bash
# The script now automatically:
# 1. Detects ARM64 architecture
# 2. Prefers Homebrew (better ARM64 support)
# 3. Falls back to Cargo for Rust tools
# 4. Skips unavailable packages gracefully

# If you still have issues:
ARCH=aarch64 ./install.sh --verbose
```

---

## 📊 Configuration Mapping

| Old Way | New Way | Notes |
|----------|-----------|-------|
| `INSTALL_MODE` env var | `INSTALL_MODE` in config file | Same functionality, new location |
| `TUI_MODE` env var | `TUI_MODE` in config file | Same functionality, new location |
| No rotation | `MAX_LOG_SIZE`, `MAX_LOG_AGE`, `MAX_LOG_COUNT` | Automatic log management |
| No verification | `ENABLE_GPG_VERIFY`, `ENABLE_SECURE_DOWNLOAD` | Security enhancements |
| Hardcoded URLs | `REPO_URL` in config file | Customizable repository URL |
| No structure | `LOG_FORMAT` option | JSON/text format selection |
| Manual fallback | Automatic `install_with_fallback()` | Multi-method package installation |
| No config file | `~/.config/linux-setting/config` | Centralized configuration |

---

## 🧪 Troubleshooting Migration

### Issue: Configuration File Ignored

**Problem**: Changes to `~/.config/linux-setting/config` are not applied

**Solution**: Check file permissions and path

```bash
# Verify file exists
ls -la ~/.config/linux-setting/config

# Check permissions (should be 600 or 644)
chmod 600 ~/.config/linux-setting/config

# Test config loading
CONFIG_FILE=~/.config/linux-setting/config ./install.sh --dry-run
```

### Issue: GPG Verification Fails

**Problem**: All downloads fail with GPG errors

**Solution**: Import missing keys or disable verification

```bash
# Check available GPG keys
gpg --list-keys

# Clear GPG cache and retry
rm -rf ~/.cache/linux-setting/trusted.gpg
./install.sh

# Or disable temporarily
ENABLE_GPG_VERIFY=false ./install.sh
```

### Issue: Old Logs Not Rotating

**Problem**: Old logs remain after migration

**Solution**: Manually clean old logs

```bash
# Remove old logs
rm -rf ~/.local/log/linux-setting/common_*.log

# Let new system create fresh logs
./install.sh --verbose
```

### Issue: Homebrew Fails to Install

**Problem**: Homebrew installation fails, causing cascading failures

**Solution**: Let script fall back to system package manager

```bash
# Disable Homebrew preference
PREFER_HOMEBREW=false ./install.sh

# Or install Homebrew manually first
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

---

## 🚀 Post-Migration Checklist

- [ ] Backup created successfully
- [ ] Configuration file created and customized
- [ ] New version installed without errors
- [ ] Health check passes: `./scripts/health_check.sh`
- [ ] Security audit passes: `./tests/security_audit.sh`
- [ ] Unit tests pass: `./tests/test_common_library.sh`
- [ ] All required tools installed: check `nvim`, `docker`, `zsh`
- [ ] Logs are rotating correctly: check `~/.local/log/linux-setting/`
- [ ] Custom aliases restored (if applicable)
- [ ] Git configuration preserved
- [ ] SSH keys preserved

---

## 📚 Additional Resources

### Documentation

- [Configuration Options](config/linux-setting.conf) - Full list of config options
- [Common Library Functions](scripts/core/common.sh) - Function documentation in comments
- [Troubleshooting Guide](README_IMPROVED.md#故障排除) - Common issues and solutions

### Scripts Reference

- [install.sh](install.sh) - Main installation script
- [uninstall.sh](uninstall.sh) - Uninstallation script
- [Module Scripts](scripts/core/) - Individual module installation scripts

### Testing

- [Unit Tests](tests/test_common_library.sh) - Test common library functions
- [Security Audit](tests/security_audit.sh) - Security vulnerability checks
- [Health Check](scripts/health_check.sh) - System health verification

---

## 🤝 Need Help?

If you encounter issues during migration:

1. **Check the troubleshooting guide**: See [README_IMPROVED.md](README_IMPROVED.md#故障排除)
2. **Run diagnostics**: `./scripts/health_check.sh` and `./tests/security_audit.sh`
3. **Review logs**: Check `~/.local/log/linux-setting/` for error messages
4. **Create an issue**: Include:
   - System information: `cat /etc/os-release`
   - Error messages: from log files
   - Configuration: redacted `~/.config/linux-setting/config`
   - Steps to reproduce

---

**Migration Complete! Welcome to v2.0.0** 🎉
