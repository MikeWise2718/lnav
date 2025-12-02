# lnav WSL2 Build Notes

## Quick Start

```bash
# From WSL2 Ubuntu terminal - just run the script:
bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh
```

The script will:
1. Clone your fork (`MikeWise2718/lnav`) to `~/lnav-src`
2. Install Ubuntu build dependencies
3. Build in `~/lnav-build`
4. Test the resulting binary

**That's it!** Everything happens in WSL2's native filesystem for optimal speed.

---

## Build Options

| Option | Description |
|--------|-------------|
| `--repo URL` | Use different Git repo (default: your fork) |
| `--branch NAME` | Build specific branch (default: master) |
| `--with-rust` | Include Rust/PRQL support |
| `--static` | Build a static binary |
| `--clean` | Remove existing source/build dirs first |
| `--install` | Run `sudo make install` after build |
| `--jobs N` | Override parallel job count |

## Examples

```bash
# Basic build from your fork (fastest, recommended)
bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh

# Build from upstream instead of your fork
bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh --repo https://github.com/tstack/lnav.git

# Build a specific branch
bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh --branch develop

# Full clean rebuild with installation
bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh --clean --install

# Build with Rust/PRQL support
bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh --with-rust
```

---

## What Gets Built Where

| Location | Purpose |
|----------|---------|
| `~/lnav-src` | Cloned source code |
| `~/lnav-build` | Build output |
| `~/lnav-build/src/lnav` | The compiled binary |

All paths are in WSL2's native ext4 filesystem for fast I/O.

---

## Important Notes

### 1. First Run

The first run will:
- Prompt for sudo password to install Ubuntu packages
- Clone the repository (~50MB download)
- Take 5-15 minutes total

Subsequent runs are faster (source is updated via `git pull`, packages already installed).

### 2. Subsequent Runs

Running the script again will:
- Update the source to latest from GitHub (`git fetch && git reset --hard`)
- Rebuild only changed files (incremental build)

Use `--clean` to force a complete rebuild.

### 3. The Binary is Linux-Only

The resulting binary is a Linux ELF executable. It runs in WSL2 but **not** directly on Windows. To view Windows log files:

```bash
~/lnav-build/src/lnav /mnt/c/logs/myapp.log
```

### 4. Line Endings

If the script fails with `bad interpreter` errors, fix line endings:

```bash
sed -i 's/\r$//' /mnt/d/cpp/lnav/scripts/wsl2-build.sh
```

---

## Troubleshooting

### "Permission denied" running the script

```bash
chmod +x /mnt/d/cpp/lnav/scripts/wsl2-build.sh
# Or just run with bash:
bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh
```

### Git clone fails

Check your internet connection, or try:
```bash
bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh --repo https://github.com/tstack/lnav.git
```

### Configure fails

Usually missing dependencies. Try:
```bash
sudo apt-get update
sudo apt-get install build-essential autoconf automake
bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh --clean
```

### Build fails with compiler errors

Try a clean build:
```bash
bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh --clean
```

---

## Verifying the Build

```bash
# Check version
~/lnav-build/src/lnav -V

# View system logs
~/lnav-build/src/lnav /var/log/syslog

# View Windows log files
~/lnav-build/src/lnav /mnt/d/logs/*.log

# Non-interactive mode (for scripting)
echo "test log line" | ~/lnav-build/src/lnav -n
```

---

## Making lnav Easy to Run

### Option 1: Add alias to ~/.bashrc

```bash
echo 'alias lnav="$HOME/lnav-build/src/lnav"' >> ~/.bashrc
source ~/.bashrc
```

### Option 2: Install system-wide

```bash
bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh --install
# Now just run: lnav
```

### Option 3: Add to PATH

```bash
echo 'export PATH="$HOME/lnav-build/src:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## Why WSL2 Instead of Native Windows?

| Aspect | WSL2 | Windows MSYS2 |
|--------|------|---------------|
| Build status | Works reliably | Broken (GCC 15 ABI issues) |
| Build time | 3-10 minutes | N/A (fails) |
| Binary type | Linux ELF | Windows PE |
| Dependencies | Ubuntu packages | msys-2.0.dll |
| Windows file access | Via /mnt/* | Native |

WSL2 provides a fully working Linux environment where lnav builds without issues, while the native Windows MSYS2 build currently fails due to GCC 15 / scnlib compatibility problems.
