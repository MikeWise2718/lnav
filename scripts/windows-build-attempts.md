# lnav Windows Build Attempts - Summary

This document summarizes all attempts to build lnav from source on Windows.

## Environment

- **OS**: Windows 10/11 (MSYS_NT-10.0-26100)
- **Hardware**: 192 GB RAM, 4TB M.2 SSDs
- **Visual Studio**: 2022 Community (MSVC 14.44)
- **MSYS2**: Installed at C:\msys64

---

## Attempt 1: CMake + vcpkg + MSVC (FAILED)

### What we tried
- Used CMake with vcpkg preset
- Installed dependencies via vcpkg (took 3+ hours due to Windows Defender)

### Issues encountered
1. **libxml2 hash mismatch** - GitLab serving different archive than vcpkg expected
   - Fixed by modifying `vcpkg.json` to disable libxml2 in libarchive
2. **Missing config.h.in** - CMake referenced non-existent file
   - Fixed by creating placeholder file
3. **Missing sudo_log.json** - Referenced in CMakeLists.txt but doesn't exist
   - Fixed by removing from CMakeLists.txt
4. **libunistring.a path** - Hardcoded Unix path in CMakeLists.txt
   - Fixed by changing to `unistring.lib`
5. **notcurses compilation failures** - Missing Unix headers:
   - `pthread.h`, `unistd.h`, `sys/time.h`, `netinet/in.h`
   - **FATAL**: notcurses is Unix-only, cannot compile with MSVC

### Conclusion
**CMake + MSVC is not viable** - The codebase uses Unix-specific dependencies (notcurses) that don't compile with MSVC.

### Cleanup
```powershell
# Delete vcpkg cache (optional, saves ~3GB)
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\vcpkg\archives"

# Delete CMake build directory
Remove-Item -Recurse -Force "D:\cpp\lnav\build"
```

---

## Attempt 2: Autotools + MSYS2 MSYS (PARTIAL SUCCESS)

This is the official build method per `.github/workflows/bins.yml`.

### Setup completed
1. Installed MSYS2
2. Installed dependencies via pacman:
   ```bash
   pacman -S autoconf automake gcc git make zip \
       msys/libarchive-devel msys/libbz2-devel msys/libcurl-devel \
       msys/libidn2-devel msys/liblzma-devel msys/libsqlite-devel \
       msys/libunistring-devel msys/pcre2-devel msys/zlib-devel
   ```
3. Installed Rust via pacman: `pacman -S mingw-w64-x86_64-rust`
   - Required adding `/mingw64/bin` to PATH for cargo
4. Ran `./autogen.sh` successfully

### Issues encountered

#### Issue 1: Wrong compiler selected
- Adding `/mingw64/bin` to PATH caused MinGW64 gcc to be used instead of MSYS gcc
- **Fix**: Explicitly specify compilers:
  ```bash
  CC=/usr/bin/gcc CXX=/usr/bin/g++ ../lnav/configure ...
  ```

#### Issue 2: Rust/PRQL SSL certificate errors
- Cargo failed to clone git dependencies with SSL errors
- **Fix**: Configure without cargo:
  ```bash
  ../lnav/configure --without-cargo ...
  ```
- PRQL support is optional (alternative SQL syntax)

#### Issue 3: scnlib linker errors (CURRENT BLOCKER)
- Undefined references to `std::__cxx11::time_get`, `std::__cxx11::regex_traits`
- Wide character (wchar_t) C++ standard library symbols missing
- Likely a GCC 15.2.0 ABI compatibility issue with scnlib library

### Last working configure command
```bash
cd /d/cpp/lnav-build
rm -rf *

CC=/usr/bin/gcc CXX=/usr/bin/g++ ../lnav/configure \
    --without-cargo \
    CPPFLAGS="-g -O0" \
    CXXFLAGS="-g -O0" \
    CFLAGS="-g -O0"

make
```

---

## Future Suggestions

### Option A: Try older GCC version
The scnlib errors might be GCC 15 specific. Try:
```bash
# Check if older gcc is available
pacman -Ss gcc | grep -i msys

# Or check package archive for older versions
```

### Option B: Try adding library flags
```bash
CC=/usr/bin/gcc CXX=/usr/bin/g++ ../lnav/configure \
    --without-cargo \
    CPPFLAGS="-g -O0" \
    CXXFLAGS="-g -O0" \
    CFLAGS="-g -O0" \
    LIBS="-lstdc++ -lsupc++"
```

### Option C: Investigate scnlib compatibility
- scnlib is in `src/third-party/scnlib/`
- Check if there's a configure flag to disable features using wide chars
- Check scnlib GitHub for GCC 15 / Cygwin compatibility issues

### Option D: Use WSL (Windows Subsystem for Linux)
- Linux builds are the primary target and most tested
- Install WSL2 with Ubuntu
- Build using standard Linux instructions

### Option E: Use Docker
```bash
# From PowerShell
docker run -it -v D:\cpp\lnav:/lnav ubuntu:22.04 bash
# Then build inside container
```

### Option F: File GitHub issue
- Report GCC 15 + MSYS2 build failure
- Include error log from scnlib linking
- Maintainers may have insights or fixes

---

## Important Notes

### Windows Defender Exclusions
Add these exclusions BEFORE building to prevent 10x slowdown:
- `C:\msys64`
- `D:\cpp\lnav`
- `D:\cpp\lnav-build`
- `%LOCALAPPDATA%\Temp`

### Official Windows builds
Per `.github/workflows/bins.yml`:
- Uses MSYS2 MSYS subsystem (not MinGW)
- Uses autotools (not CMake)
- Includes `msys-2.0.dll` with the binary
- Successfully builds on GitHub Actions

### Files modified during attempts
These changes were made to the source tree:
- `vcpkg.json` - Modified libarchive features
- `CMakeLists.txt` - Changed libunistring path, removed sudo_log.json
- `src/CMakeLists.txt` - Removed sudo_log.json reference
- `src/config.h.in` - Created placeholder file

To revert:
```bash
cd /d/cpp/lnav
git checkout vcpkg.json CMakeLists.txt src/CMakeLists.txt
rm src/config.h.in
```

---

## Reference: Working CI Build Command

From `.github/workflows/bins.yml`:
```bash
./autogen.sh
mkdir -p ../lnav-build
cd ../lnav-build

../lnav/configure \
    --enable-static \
    LDFLAGS="-static" \
    CPPFLAGS="-O3" \
    CXXFLAGS="-fPIC" \
    CFLAGS="-fPIC" \
    LIBS="-larchive -lssh2 -llzma -lexpat -llz4 -lz -lzstd -lssl -lcrypto -liconv -lunistring -lbrotlicommon -lcrypt32" \
    --sysconfdir=/etc

make
```

Note: This works in CI but failed locally, possibly due to GCC version differences.
