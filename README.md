# SwitchVN

[English](README.md) | [简体中文](README-CN.md)

Hardware video decoding for visual novels on a Nintendo Switch running
switchroot Ubuntu.

The Switch's Tegra X1 has an NVDEC hardware decoder, but Wine/Proton never
reaches it. Two things are in the way. winedmo only ever asks FFmpeg for
software decoding. And the x86 Proton running under Box64 has no idea a native
ARM FFmpeg exists on the system, so even a hardware-capable FFmpeg would be
emulated instruction by instruction. Openings and endings drop frames, stutter,
or come out black.

SwitchVN connects that path end to end — a Box64 wrapper that routes the x86
FFmpeg calls onto the native ARM libraries, an envideo hwaccel in FFmpeg, and
winedmo asking for it — then fixes the pile of bugs found along the way.

**For ordinary users: install [SwitchVN-Switchdeck](https://github.com/BandiFee/SwitchVN-Switchdeck)
first, then run one command.**

```bash
curl -fsSL -o /tmp/install-switchvn.sh https://raw.githubusercontent.com/BandiFee/SwitchVN/main/install-switchvn.sh \
  && bash /tmp/install-switchvn.sh
```

---

## What you get

| Change | Fixed in |
| --- | --- |
| The x86 Proton's FFmpeg calls land on the native ARM libraries instead of being emulated | Box64 ffmpeg8 wrapper |
| Video decodes on NVDEC; CPU load drops sharply | winedmo + envideo |
| Video is no longer black | envideo host1x gather/reloc offsets |
| WMV3 / VC-1 no longer black | FFmpeg envideo VC-1 null-pointer fix |
| Skipping an opening no longer hangs the game | qasf dmowrapper lock ordering |
| Skipping no longer raises `Error Abort 0x80040211` | winedmo wm_reader allocator handling |
| No more tearing during playback | DXVK D3D9 present mode |
| Unity games show the video instead of playing audio over a frozen frame | Media Foundation system-memory path on aarch64 |

Measured on 20 seconds of 1080p VC-1: 13.42s of CPU time down to 3.34s.

---

## Requirements

- A Nintendo Switch running switchroot Ubuntu (aarch64, Ubuntu 24.04 based)
- [SwitchVN-Switchdeck](https://github.com/BandiFee/SwitchVN-Switchdeck) installed, with Steam
  started through it at least once
- Your user in the `video` group (`id -nG | grep video`; if not,
  `sudo usermod -aG video $USER` and log out and back in)
- `/dev/nvhost-nvdec` and `/dev/nvmap` present

The installer checks all of these and tells you exactly what is missing.

---

## Installing

```bash
curl -fsSL -o /tmp/install-switchvn.sh https://raw.githubusercontent.com/BandiFee/SwitchVN/main/install-switchvn.sh \
  && bash /tmp/install-switchvn.sh
```

It does five things:

1. Installs native aarch64 **envideo** and **FFmpeg** into `/usr/local` (needs
   sudo).
2. Installs the **Box64** build carrying the ffmpeg8 wrapper, which redirects
   the x86 Proton's `libavcodec.so.62` and `libavutil.so.60` onto those native
   libraries. The version matters — see below.
3. Unpacks **GE-Proton11-3-SwitchVN-1** into
   `~/.local/share/Steam/compatibilitytools.d/`.
4. Puts the fixed **DXVK** inside the Proton directory and symlinks to it.
5. Checks itself: exactly one `libenvideo.so`, and both FFmpeg sonames in the
   linker cache.

Step 2 replaces the Pi-Apps `box64-tegrax1` package if it is present — the
package declares `Conflicts`/`Replaces` on it, so dpkg swaps it rather than
refusing to overwrite `/usr/bin/box64`.

Options: `-y` to skip prompts, `--skip-system` / `--skip-proton` /
`--skip-dxvk` to leave a part alone.

### Versions

A SwitchVN version names **one combination of components that was checked
together on hardware** — not a feature set. The components are not independent:
libavcodec links `libenvideo.so`, which carries no version in its SONAME, so
the loader accepts any copy and a mismatched pair produces bad decoding rather
than a link error.

That combination lives in [switchvn.lock](switchvn.lock), published as an asset
on each release. The installer downloads the lock for the release you asked
for, then fetches exactly those component tags.

```bash
bash /tmp/install-switchvn.sh                  # latest release
bash /tmp/install-switchvn.sh --version 1.0    # a specific one
```

Reinstalling prints which components are about to change, and refuses a lock
that moves only one of envideo and FFmpeg.

To try a combination that has not been released yet, point `SWITCHVN_LOCK` at
a lock file or URL — this is how a candidate is tested before it is tagged:

```bash
SWITCHVN_LOCK=https://raw.githubusercontent.com/BandiFee/SwitchVN/next/switchvn.lock \
  bash /tmp/install-switchvn.sh
```

Afterwards:

1. Restart Steam through Switchdeck's launcher:
   `~/.local/share/Steam/launch-steam.sh`
2. In the game's **Properties → Compatibility**, force a specific compatibility
   tool and pick **GE-Proton11-3-SwitchVN-1**.

### Why DXVK goes inside the Proton directory

`launch-steam.sh` relinks every Proton's `wine/dxvk` from
`$STEAMROOT/Switchdeck/DXVK` on each Steam launch, so a copy dropped only into
the Proton directory would be replaced on the next start. SwitchVN populates
`Switchdeck/DXVK` too, which is why SwitchVN-Switchdeck drops the DXVK download
that upstream Switchdeck does — it would otherwise overwrite that folder with a
stock DXVK-Sarek whenever upstream published one.

The relink is guarded by an idempotence check: if
`d3d11.dll` *and* `d3d12.dll` are both already symlinks, it skips the whole
block. So the installer keeps the DLLs in
`$PROTON/files/lib/switchvn-dxvk/` and turns Proton's `dxvk/` and
`vkd3d-proton/` directories into symlinks pointing there. Switchdeck then
leaves this Proton's DXVK alone.

The vertex-explosion patch is a separate `find` and still applies normally.
That is also why the Proton directory name has to start with `GE-Proton11` —
the installer verifies it.

---

## Confirming hardware decoding actually works

At the command line:

```bash
/usr/local/bin/ffmpeg -hwaccel envideo -threads 1 -i yourvideo.wmv -frames:v 3 -f rawvideo -pix_fmt nv12 -y /tmp/t.nv12
tr -d '\0' < /tmp/t.nv12 | wc -c
```

Non-zero means envideo and FFmpeg are fine. Zero means the system components
were not installed correctly.

In the game — set the launch options to:

```
WINEDEBUG=+dmo PROTON_LOG=1 %command%
```

Then after a video plays:

```bash
grep -E 'trying envideo decoding|decoding in software|no usable envideo device' ~/steam-*.log
```

`trying envideo decoding for <codec>` with no fallback line under it means it
worked.

---

## Uninstalling

```bash
curl -fsSL -o /tmp/uninstall-switchvn.sh https://raw.githubusercontent.com/BandiFee/SwitchVN/main/uninstall-switchvn.sh \
  && bash /tmp/uninstall-switchvn.sh
```

It removes exactly the files recorded at install time, so nothing else in
`/usr/local` is touched. Switchdeck itself is left alone.

---

## Something went wrong

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Building it yourself

See [docs/BUILDING.md](docs/BUILDING.md), and
[docs/RELEASING.md](docs/RELEASING.md) for how a version gets cut.
The component repositories:

| Repository | Contents |
| --- | --- |
| [SwitchVN-ProtonGE](https://github.com/BandiFee/SwitchVN-ProtonGE) | winedmo envideo decoding, qasf deadlock fix, wm_reader fix, aarch64 MF fallback |
| [SwitchVN-Box64](https://github.com/BandiFee/SwitchVN-Box64) | the ffmpeg8 native wrapper — libavcodec 62, libavformat 62, libavutil 60, libswscale 9 and libswresample 6 redirected to the ARM builds |
| [SwitchVN-FFmpeg](https://github.com/BandiFee/SwitchVN-FFmpeg) | FFmpeg with `--enable-envideo`, VC-1 null-pointer fix |
| [SwitchVN-Envideo](https://github.com/BandiFee/SwitchVN-Envideo) | host1x gather/reloc offset fix |
| [SwitchVN-DXVK-Sarek](https://github.com/BandiFee/SwitchVN-DXVK-Sarek) | D3D9 present mode vsync fix |
| [SwitchVN-Switchdeck](https://github.com/BandiFee/SwitchVN-Switchdeck) | Switchdeck with the DXVK download dropped, so SwitchVN owns `Switchdeck/DXVK` |

## Credits

- [averne](https://github.com/averne) — envideo
- [SildurFX](https://github.com/SildurFX) — Switchdeck
- [pythonlover02](https://github.com/pythonlover02) — DXVK-Sarek
- [GloriousEggroll](https://github.com/GloriousEggroll) — Proton-GE
- [ptitSeb](https://github.com/ptitSeb) — Box64

## License

The installer scripts are GPLv3. Each component keeps its upstream license.
