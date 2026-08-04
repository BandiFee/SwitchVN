# Building

[English](BUILDING.md) | [简体中文](BUILDING-CN.md)

Ordinary users do not need this page — `install-switchvn.sh` installs prebuilt
binaries.

The four components build in different places:

| Component | Where | Roughly |
| --- | --- | --- |
| envideo | natively on the Switch, or `ubuntu-24.04-arm` | 1 minute |
| FFmpeg | same | 20–40 minutes on the Switch |
| DXVK | any machine, cross-compiled with mingw-w64 | 5 minutes |
| Proton | x86_64 PC with Docker | hours, needs 60–100 GB of disk |

Every repository has a `.github/workflows/release.yml`; pushing a `switchvn-*`
tag (`GE-Proton*-*` for Proton) builds and uploads the release asset. Below is
how to reproduce the same steps by hand.

---

## envideo

```bash
git clone --recursive https://github.com/BandiFee/SwitchVN-Envideo.git
cd SwitchVN-Envideo
meson setup build -Dnvgpu=enabled -Dtegra-drm=false \
    --prefix=/usr/local --libdir=lib --buildtype=release
meson compile -C build
sudo meson install -C build
sudo ldconfig
```

Neither option is negotiable:

- **`--recursive` is required.** There are nested submodules
  (`open-gpu-kernel-modules`); without them meson stops during configuration.
- **`-Dtegra-drm=false`.** The tegra-drm backend returns `ENOTTY` for every
  submission on the L4T kernel, so using it means no hardware decoding at all.
  The nvgpu backend is the one that works.

`--libdir=lib` puts `envideo.pc` in `/usr/local/lib/pkgconfig`, which is where
FFmpeg's configure looks for it.

---

## FFmpeg

Install envideo first (previous section).

```bash
git clone https://github.com/BandiFee/SwitchVN-FFmpeg.git
cd SwitchVN-FFmpeg
PKG_CONFIG_PATH=/usr/local/lib/pkgconfig ./configure \
    --prefix=/usr/local \
    --libdir=/usr/local/lib/aarch64-linux-gnu \
    --shlibdir=/usr/local/lib/aarch64-linux-gnu \
    --enable-shared --disable-static \
    --enable-envideo --disable-doc
grep '^#define CONFIG_ENVIDEO 1' config.h   # must match
make -j$(nproc)
sudo make install
sudo ldconfig
```

**Do not trim the build with `--disable-everything` or similar.** Box64's
ffmpeg8 wrapper checks a whole required symbol set before taking over, and a
trimmed build makes it fall back to the emulated x86 libraries without saying
anything — indistinguishable from hardware decoding not working.

Afterwards, confirm the two sonames Box64 looks for:

```bash
ldconfig -p | grep -E 'libavcodec\.so\.62|libavutil\.so\.60'
```

If `/usr/local/lib/aarch64-linux-gnu` is not on the linker search path, add it:

```bash
echo /usr/local/lib/aarch64-linux-gnu | sudo tee /etc/ld.so.conf.d/switchvn.conf
sudo ldconfig
```

---

## DXVK

Cross-compiles on any x86_64 Linux machine; no Switch needed.

```bash
git clone --recursive https://github.com/BandiFee/SwitchVN-DXVK-Sarek.git
cd SwitchVN-DXVK-Sarek
./package-release.sh switchvn-local /tmp/dxvk-out
```

Needs `mingw-w64`, `meson` and `glslang-tools`. `--recursive` is required here
too (Vulkan-Headers, SPIRV-Headers).

The output is an `x32/` + `x64/` layout. `ddraw.dll` exists only for 32-bit —
Windows never shipped a 64-bit DirectDraw runtime, so that is by design, not a
build failure.

---

## Proton

The awkward one. Needs an x86_64 machine, Docker, and 60–100 GB free.

```bash
git clone https://github.com/BandiFee/SwitchVN-ProtonGE.git
cd SwitchVN-ProtonGE
git submodule update --init --recursive --force
./patches/protonprep-valve-staging.sh
mkdir build && cd build
../configure.sh --build-name=GE-Proton11-3-SwitchVN --container-engine=docker
make -j$(nproc) redist
```

### Things you have to know

**`--build-name` must start with `GE-Proton11`.** Switchdeck's
`launch-steam.sh` decides whether to apply the vertex-explosion patch (renaming
`VK_EXT_external_memory_host` inside `win32u.so`) by matching the directory
name. Get the name wrong and 32-bit games render exploded geometry.

**`protonprep-valve-staging.sh` uses `|| true` in several places.** A patch that
fails to apply will not stop the script. CI has an explicit check
(`.github/workflows/_job_build.yml`); building by hand, verify it yourself:

```bash
grep -q transform_init_hw_decoding wine/dlls/winedmo/unix_transform.c
grep -q "Decommit the output allocators" wine/dlls/qasf/dmowrapper.c
grep -q "no longer committed" wine/dlls/winedmo/wm_reader.c
grep -q '"mfdxgiman" not in self.compat_config' proton
```

All four have to pass for the build to be a complete SwitchVN one.

**`--force` on the submodule update is not optional.** Half-initialised
submodules make the build fail somewhere like a missing `openfst/configure.ac`,
with a message that points nowhere near the actual cause.

**Preparing patches on macOS needs GNU patch.** Apple's `/usr/bin/patch`
silently mangles this patch series. `brew install gpatch`, then use `gpatch`.

### Known traps

- Submodule mtime changes trigger xz's maintainer-mode regeneration, which then
  fails on a missing `build-aux/missing` with `aclocal.m4 Error 127`. Clear it
  and retry: `rm -rf build/src-xz build/obj-xz-* build/.xz-*`
- A full disk disguises itself as assorted compile errors, most often in xz and
  kaldi. Run `df -h` before suspecting the code.

---

## Key commits per repository

Useful for checking whether your checkout has the fixes:

| Repository | Commit | Fixes |
| --- | --- | --- |
| SwitchVN-Envideo | `a7555fd` | host1x gather/reloc ignoring `mem_offset` — affects every codec, shows up as black video |
| SwitchVN-FFmpeg | `a16722a5` | VC-1 engine scratch map must be CPU-writable, otherwise memset dereferences null |
| SwitchVN-DXVK-Sarek | `972cd8f3` | D3D9 `CreatePresenter` hardcoded a non-vsync present mode, causing tearing |
| SwitchVN-ProtonGE | `483cd991` | winedmo hardware decoding through envideo |
| SwitchVN-ProtonGE | `b88b43b4` | qasf dmowrapper deadlocked by decommitting while holding the streaming lock |
| SwitchVN-ProtonGE | `773849b2` | wm_reader treats a decommitted allocator as end of stream |
| SwitchVN-ProtonGE | `4dbdca72` | Media Foundation system-memory samples on aarch64 |
