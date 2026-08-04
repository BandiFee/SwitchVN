# Troubleshooting

[English](TROUBLESHOOTING.md) | [简体中文](TROUBLESHOOTING-CN.md)

Ordered most likely first. Each section gives you a test before it gives you a
conclusion.

---

## Black video, audio plays fine

First work out which layer is broken.

```bash
/usr/local/bin/ffmpeg -hwaccel envideo -threads 1 -i yourvideo -frames:v 3 \
    -f rawvideo -pix_fmt nv12 -y /tmp/t.nv12
tr -d '\0' < /tmp/t.nv12 | wc -c
```

- **Zero** — the system components are wrong. Keep reading.
- **Non-zero** — envideo and FFmpeg are fine, so it is the Proton side. Skip to
  the Proton sections below.

### Two copies of libenvideo

Historically the easiest trap. You built envideo by hand into `/usr/local`
once, then installed it from somewhere else too. Both copies are in the linker
cache, the older one gets loaded, and the result is black video with no error
at all.

```bash
ldconfig -p | grep libenvideo
```

There should be exactly one line. If there are more, delete the stale copy and
run `sudo ldconfig`.

### Box64 is not actually using the native FFmpeg

Box64's ffmpeg8 wrapper binds by soname and requires a whole set of symbols to
be present. If one is missing it **silently** falls back to emulating the x86
libraries — which looks exactly like hardware decoding not working, with no
error anywhere.

```bash
ldconfig -p | grep -E 'libavcodec\.so\.62|libavutil\.so\.60'
```

Both lines must be there. If not, rerun the installer, or check that
`/etc/ld.so.conf.d/switchvn.conf` exists and `sudo ldconfig` has run.

Also make sure `BOX64_EMULATED_LIBS` does not list ffmpeg — that explicitly
turns the wrapper off.

### Permissions and device nodes

```bash
ls -l /dev/nvhost-nvdec /dev/nvmap
id -nG | tr ' ' '\n' | grep -x video
```

Not in `video`: `sudo usermod -aG video $USER`, then **log out and back in** —
opening a new terminal is not enough.

### It went black again after a reboot

Check the files are still there and the cache is populated:

```bash
ls /usr/local/lib/aarch64-linux-gnu/libavcodec.so.62
ldconfig -p | grep -c libenvideo
```

If `switchvn.conf` is present but the cache is empty, just run `sudo ldconfig`.

---

## `cdma_handle_timeout` in dmesg

A host1x command submission timed out. That usually means the command buffer
handed to the hardware is malformed, not that the driver itself is broken.

If you built envideo yourself, make sure it includes
`cmdbuf: account for host1x gather and reloc offsets` (commit `a7555fd`).
Without it every codec produces corrupt output.

---

## Picture is there but tears horizontally or diagonally

That is the DXVK layer. Check that Proton has the SwitchVN build:

```bash
ls -l ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-*/files/lib/wine/dxvk/x86_64-windows/d3d9.dll
```

It should be a symlink to `.../files/lib/switchvn-dxvk/x64/d3d9.dll`.

If it points at `~/.local/share/Steam/Switchdeck/DXVK/...` instead, Switchdeck
swapped it back — rerun the installer (`--skip-system --skip-proton` is enough).

---

## Game hangs, or raises `Error Abort 0x80040211`, when skipping a video

Both are fixed by Proton-side patches. Confirm you are really running the
SwitchVN Proton:

```bash
grep -c SwitchVN ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-3-SwitchVN-1/compatibilitytool.vdf
```

And that the game itself is set to use it. Steam's global "default
compatibility tool" setting does not override a per-game one, or vice versa —
this is easy to misread.

---

## Unity game plays audio with a frozen picture

This is known, and the handling is **required** rather than a workaround.

To fix vertex explosions in 32-bit games, Switchdeck binary-patches Proton's
`win32u.so`, renaming the string `VK_EXT_external_memory_host` so it stops
working. The side effect is that winevulkan no longer exposes
`VK_KHR_external_memory_win32`, DXVK cannot export a shared texture, and Media
Foundation's Direct3D sample path fails — audio with no picture.

SwitchVN's Proton therefore defaults `WINE_DO_NOT_CREATE_DXGI_DEVICE_MANAGER=1`
on aarch64, making Media Foundation deliver system-memory samples instead. The
hardware decoder still does the decoding; only the delivery path changes. Do
not try to "fix" the shared-texture path — fixing it brings the vertex
explosions back.

If you want to turn the default off for one game, add `mfdxgiman` to its Proton
compat config in Steam's compatibility options.

---

## GE-Proton11-3-SwitchVN-1 does not appear in Steam

Quit Steam **completely**, then start it through Switchdeck's launcher:

```bash
~/.local/share/Steam/launch-steam.sh
```

Steam only scans `compatibilitytools.d` at startup.

---

## Checking whether the GPU is decoding

The log is the reliable answer:

```bash
grep -E 'trying envideo decoding|decoding in software|no usable envideo device' ~/steam-*.log
```

(Requires the launch option `WINEDEBUG=+dmo PROTON_LOG=1 %command%`.)

For the hardware side, the L4T kernel exposes NVDEC's clock through debugfs,
and it should be pulled up during playback:

```bash
sudo find /sys/kernel/debug/clk -maxdepth 1 -name '*nvdec*'
# then, with whatever name that found
sudo cat /sys/kernel/debug/clk/<name>/clk_rate
```

The node name differs between kernel versions, hence the `find` first. CPU load
is a crude but effective check too — software-decoding 1080p VC-1 saturates a
core, hardware decoding does not.

---

## Still broken

Open an issue with:

```bash
uname -a
ldconfig -p | grep -E 'libenvideo|libavcodec|libavutil'
ls -l ~/.local/share/Steam/compatibilitytools.d/
ffprobe yourvideo 2>&1 | tail -20
```

plus the `~/steam-*.log` from a run with `WINEDEBUG=+dmo PROTON_LOG=1`.

The codec matters a lot — VC-1, WMV3, H.264 and MPEG-4 take different code
paths.
