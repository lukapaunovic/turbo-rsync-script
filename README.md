# turbo-rsync-script

**High-performance rsync wrapper with parallel transfer for large files**

A robust Bash script for efficient remote synchronization with automatic parallelization of large files, resume capability, and WAN-optimized SSH settings.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [Environment Variables](#environment-variables)
- [Troubleshooting](#troubleshooting)
- [Performance Tuning](#performance-tuning)
- [Examples](#examples)
- [FAQ](#faq)

---

## ✨ Features

- ** Resume-friendly transfers** - Uses `--append-verify` for safe resumption of interrupted transfers
- ** Parallel transfers** - Automatically parallelizes large files (>64MB by default) using multiple rsync processes
- ** Progress monitoring** - Real-time progress with `--info=progress2`
- ** WAN-optimized** - SSH compression disabled, TCP keepalive enabled, QoS settings for throughput
- ** Safe by default** - Dry-run preview before actual transfer, version checks, sanity validation
- ** Low I/O priority** - Uses `ionice` and `nice` to avoid system overload
- ** Relative path preservation** - Optional `--relative` mode maintains directory structure

---

##  Requirements

### Minimum versions:
- **Bash** ≥ 4.0
- **rsync** ≥ 3.0.0 (for `--append-verify` support)
- **GNU find** (for `-size` and `-print0`)
- **xargs** with `-P` support (parallel execution)

### Optional:
- **ionice** (recommended for I/O priority control)
- **awk** (for version parsing)

### Verify your system:
```bash
bash --version     # Should be 4.0+
rsync --version    # Should be 3.0.0+
ionice --version   # Optional but recommended
```

---

## 🚀 Installation

### Quick install:
```bash
# Download the script
curl -O https://raw.githubusercontent.com/yourusername/turbo-rsync-script/main/turbo-rsync-script.sh

# Make executable
chmod +x turbo-rsync-script.sh

# Optional: Install to PATH
sudo mv turbo-rsync-script.sh /usr/local/bin/turbo-rsync-script
```

### Manual installation:
1. Copy the script to your system
2. Edit the configuration section (lines 4-10)
3. Make it executable: `chmod +x turbo-rsync-script.sh`

---

## Usage

### Basic usage:
```bash
./turbo-rsync-script.sh
```

### With environment variables:
```bash
# Test run without transferring
DRY_RUN=1 ./turbo-rsync-script.sh

# Use 8 parallel processes
PARALLEL=8 ./turbo-rsync-script.sh

# Change large file threshold to 100MB
BIG_SIZE=100M ./turbo-rsync-script.sh

# Disable --relative mode
USE_RELATIVE=0 ./turbo-rsync-script.sh

# Combine options
DRY_RUN=1 PARALLEL=6 BIG_SIZE=128M ./turbo-rsync-script.sh
```

---

## ⚙️ Configuration

Edit these variables at the top of the script:

```bash
# Source directory (trailing slash = copy contents)
SRC="/path/to/source/"

# Destination (user@host:/path/)
DST="user@host:/path/to/destination/"

# Number of parallel rsync processes (default: 3)
PAR="${PARALLEL:-3}"

# Large file threshold (files > this size are parallelized)
BIG="64M"

# Use --relative to preserve directory structure (1=yes, 0=no)
USE_RELATIVE="${USE_RELATIVE:-1}"

# Dry-run mode (1=test only, 0=real transfer)
DRY_RUN="${DRY_RUN:-0}"
```

### SSH Options:
```bash
SSHOPTS=(
  -T                          # Disable pseudo-terminal
  -o Compression=no           # Disable SSH compression (rsync handles it)
  -o ServerAliveInterval=30   # Send keepalive every 30s
  -o ServerAliveCountMax=6    # Drop connection after 6 failed keepalives
  -o TCPKeepAlive=yes         # Enable TCP keepalive
  -o IPQoS=throughput         # Optimize for throughput over latency
)
```

### rsync Options:
```bash
RSYNC_BASE_OPTS=(
  -a                    # Archive mode (recursive, preserve permissions, etc.)
  --info=progress2      # Show total progress
  --stats               # Show transfer statistics
  --human-readable      # Human-readable sizes
)
```

---

## How It Works

The script performs synchronization in **3 phases**:

### **Phase 1: Dry-Run Preview** 
```bash
rsync -anv -e "ssh ..." "$SRC" "$DST"
```
- Shows what would be transferred
- No actual data is sent
- Useful for validation

### **Phase 2: Main Sync** 🚀
```bash
rsync -a --partial --inplace --append-verify \
  -e "ssh ..." "$SRC" "$DST"
```
- Transfers **all files** (small and large)
- Uses `--partial` + `--inplace` + `--append-verify` for safe resume
- Single rsync process with total progress

### **Phase 3: Parallel Sync for Large Files** ⚡
```bash
find . -type f -size "+64M" -print0 |
  xargs -0 -P 3 -I{} rsync -a --relative ...
```
- Finds all files **larger than 64MB**
- Spawns multiple rsync processes (default: 3)
- Each process handles one large file
- Uses `--relative` to preserve directory structure

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PARALLEL` | `3` | Number of parallel rsync processes for large files |
| `BIG_SIZE` | `64M` | File size threshold for parallel transfer |
| `USE_RELATIVE` | `1` | Use `--relative` to preserve paths (1=yes, 0=no) |
| `DRY_RUN` | `0` | Enable dry-run mode (1=test, 0=real transfer) |

### Examples:
```bash
# Test with 4 parallel processes
DRY_RUN=1 PARALLEL=4 ./turbo-rsync-script.sh

# Transfer with 100MB threshold
BIG_SIZE=100M ./turbo-rsync-script.sh

# Disable relative paths
USE_RELATIVE=0 ./turbo-rsync-script.sh
```

---

## Troubleshooting

### **Exit code 141 (SIGPIPE)**
**Symptom:** Script exits with code 141  
**Cause:** `head -n1` closes pipe early in rsync version detection  
**Fix:** Already handled in script with `awk` instead of `head`

### **"rsync: --append-verify: unknown option"**
**Symptom:** rsync complains about `--append-verify`  
**Cause:** rsync version < 3.0.0  
**Fix:** Upgrade rsync or remove `--append-verify` (less safe)

### **"ionice: command not found"**
**Symptom:** Warning about missing `ionice`  
**Cause:** `ionice` not installed (common on macOS/BSD)  
**Fix:** Script automatically falls back to `nice` only

### **Files not transferred in parallel**
**Symptom:** Phase 3 shows "PARALLEL SYNC" but no files  
**Cause:** No files larger than `BIG` threshold  
**Fix:** Lower `BIG_SIZE` or check file sizes with `find . -size +64M`

### **Permission denied errors**
**Symptom:** rsync fails with permission errors  
**Cause:** SSH key not configured or wrong user  
**Fix:** Set up SSH keys: `ssh-copy-id user@host`

---

## 🚀 Performance Tuning

### **Adjust parallel processes based on CPU/network:**
```bash
# Low-end system or slow network
PARALLEL=2 ./turbo-rsync-script.sh

# High-performance system with fast network
PARALLEL=8 ./turbo-rsync-script.sh
```

### **Fine-tune large file threshold:**
```bash
# Many small files? Increase threshold
BIG_SIZE=128M ./turbo-rsync-script.sh

# Few large files? Decrease threshold
BIG_SIZE=32M ./turbo-rsync-script.sh
```

### **Disable ionice/nice for maximum speed:**
Edit script and set:
```bash
NICE_LOCAL=()
REMOTE_WRAPPER="rsync"
```

### **Enable rsync compression for slow networks:**
```bash
# In SSHOPTS, change:
-o Compression=no  →  -o Compression=yes

# In RSYNC_BASE_OPTS, add:
--compress
```

---

## Examples

### **Example 1: Sync website files**
```bash
#!/usr/bin/env bash
SRC="/var/www/html/"
DST="user@backup-server:/backups/www/"
PAR=4
BIG="100M"
./turbo-rsync-script.sh
```

### **Example 2: Backup media library**
```bash
# Large video files benefit from parallelization
SRC="/media/videos/"
DST="nas@192.168.1.100:/volume1/backups/"
PARALLEL=6 BIG_SIZE=500M ./turbo-rsync-script.sh
```

### **Example 3: Initial sync (test first)**
```bash
# 1. Test what will be synced
DRY_RUN=1 ./turbo-rsync-script.sh

# 2. If looks good, run for real
./turbo-rsync-script.sh
```

### **Example 4: Resume interrupted transfer**
```bash
# Just re-run the script - it will resume automatically
./turbo-rsync-script.sh
```

---

## ❓ FAQ

### **Q: Why disable SSH compression?**
**A:** rsync has its own compression (`-z`). SSH compression adds CPU overhead without benefit and can slow down transfers.

### **Q: What's the difference between `--partial` and `--partial-dir`?**
**A:** `--partial` keeps incomplete files in place. `--partial-dir` moves them to a temp directory. We use `--partial` because it's compatible with `--append-verify`.

### **Q: Is `--append-verify` safe for all file types?**
**A:** Yes, but best for write-once files (videos, backups). For frequently-modified files, rsync's default checksum is safer.

### **Q: Can I use this for local-to-local sync?**
**A:** Yes, but the parallel phase won't help much (disk I/O is the bottleneck). Remove SSH options and change `DST` to local path.

### **Q: How do I exclude certain files?**
**A:** Add to `RSYNC_BASE_OPTS`:
```bash
RSYNC_BASE_OPTS=(
  -a
  --info=progress2
  --exclude='*.tmp'
  --exclude='.cache/'
)
```

### **Q: Can I sync to multiple destinations?**
**A:** No, but you can run multiple instances:
```bash
DST="server1:/path/" ./turbo-rsync-script.sh &
DST="server2:/path/" ./turbo-rsync-script.sh &
wait
```

---

## License

MIT License - Feel free to use, modify, and distribute.

---

## 🤝 Contributing

Contributions welcome! Please:
1. Test thoroughly
2. Update documentation
3. Follow existing code style
4. Add comments for complex logic


---

## See Also

- [rsync man page](https://download.samba.org/pub/rsync/rsync.1)
- [SSH config options](https://man.openbsd.org/ssh_config)
- [GNU find manual](https://www.gnu.org/software/findutils/manual/html_mono/find.html)

---

**Last updated:** 2025-01-08  
**Script version:** 1.0.0
