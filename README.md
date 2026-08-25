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

**For ordinary users: one command.** It installs
[SwitchVN-Switchdeck](https://github.com/BandiFee/SwitchVN-Switchdeck) too if
you do not have it, and leaves it alone if you do.

```bash
curl -fsSL -o /tmp/install-switchvn.sh https://raw.githubusercontent.com/BandiFee/SwitchVN/main/install-switchvn.sh \
  && bash /tmp/install-switchvn.sh
```

---

## What you get

| Result | SwitchVN work |
| --- | --- |
| The x86 Proton's FFmpeg calls land on the native ARM libraries instead of being emulated | Box64 ffmpeg8 wrapper |
| Compatible video decodes on NVDEC; unsupported streams fall back to software | winedmo + envideo integration |
| Video no longer comes out black because of Tegra host offsets or VC-1/WMV3 scratch mapping | envideo + FFmpeg fixes |
| Skipping or stopping an opening no longer hangs or raises `Error Abort 0x80040211` | DirectShow stream and allocator lifecycle fixes |
| No more tearing during playback | DXVK D3D9 present mode |
| Unity games show the video instead of playing audio over a frozen frame | Media Foundation system-memory path on aarch64 |
| Legacy MPEG graphs negotiate video correctly and expose complete MP1/MP2 audio types | DirectShow/Quartz compatibility fixes |
| Media Foundation applications can select the H.265/HEVC decoder backed by winedmo and envideo | HEVC MFT registration and media-type support |
| WMP ActiveX playback embeds, sizes and cleans up its DirectShow video window | WMP/DirectShow integration in `GE-Proton11-5-SwitchVN-2` |

### Hardware decoder capabilities

The current FFmpeg build enables these envideo hardware decoders:

| Codec | FFmpeg hwaccel |
| --- | --- |
| H.264/AVC | `h264_envideo` |
| H.265/HEVC | `hevc_envideo` |
| MJPEG | `mjpeg_envideo` |
| MPEG-1 Video | `mpeg1_envideo` |
| MPEG-2 Video | `mpeg2_envideo` |
| MPEG-4 Part 2 | `mpeg4_envideo` |
| VC-1 | `vc1_envideo` |
| WMV3 | `wmv3_envideo` |
| VP8 | `vp8_envideo` |
| VP9 | `vp9_envideo` |

This list means the decoders are enabled in the SwitchVN build. It is not a
blanket promise for every container, codec profile, level or resolution.
winedmo uses envideo when the device and stream are compatible and falls back
to software decoding otherwise. Extensions such as `.wmv`, `.asf`, `.mpg` or
`.mp4` below are examples of playback paths, not container-wide guarantees.

### Playback paths

| Path | Source support | Recorded hardware verification |
| --- | --- | --- |
| DirectShow/Quartz | ASF/WMV and legacy MPEG graphs; MPEG sequence-header recovery, Colour conversion and complete MP1/MP2 media types | VC-1/WMV3 playback and legacy MPEG + MP2 opening playback verified |
| qasf/WM Reader | Safe stop/skip ordering and allocator shutdown | VC-1/WMV3 stop and skip regressions verified |
| Media Foundation | aarch64 system-memory delivery for Unity; H.265/HEVC decoder registration through winedmo/envideo | Unity system-memory path verified; dedicated HEVC coverage still pending |
| WMP ActiveX | DirectShow video-window ownership, embedding, sizing, visibility and cleanup in `GE-Proton11-5-SwitchVN-2` | Implemented; dedicated hardware regression still pending |

### Performance

| Codec | Sample | Software CPU time | NVDEC CPU time | Reduction | Status |
| --- | --- | ---: | ---: | ---: | --- |
| VC-1 | 1080p, 20 seconds | 13.42s | 3.34s | 75.1% | Measured |
| H.264/AVC | Same-method sample | TBD | TBD | TBD | Not measured yet |
| H.265/HEVC | Same-method sample | TBD | TBD | TBD | Not measured yet |
| MPEG-1/2 Video | Same-method sample | TBD | TBD | TBD | Not measured yet |
| MPEG-4 Part 2 | Same-method sample | TBD | TBD | TBD | Not measured yet |
| WMV3 | Same-method sample | TBD | TBD | TBD | Not measured yet |
| VP8/VP9 | Same-method sample | TBD | TBD | TBD | Not measured yet |
| MJPEG | Same-method sample | TBD | TBD | TBD | Not measured yet |

`TBD` means no comparable measurement has been recorded yet; it does not mean
the decoder is unsupported or failed.

---

## Requirements

- A Nintendo Switch running switchroot Ubuntu (aarch64, Ubuntu 24.04 based)
- Nothing else — the installer offers to set up
  [SwitchVN-Switchdeck](https://github.com/BandiFee/SwitchVN-Switchdeck) (Steam,
  Box64, the launcher) when it is missing
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
3. Unpacks **GE-Proton11-5-SwitchVN-2** into
   `~/.local/share/Steam/compatibilitytools.d/`.
4. Puts the fixed **DXVK** inside the Proton directory and symlinks to it.
5. Checks itself: exactly one `libenvideo.so`, and both FFmpeg sonames in the
   linker cache.

Step 2 replaces the Pi-Apps `box64-tegrax1` package if it is present — the
package declares `Conflicts`/`Replaces` on it, so dpkg swaps it rather than
refusing to overwrite `/usr/bin/box64`.

Options: `-y` to skip prompts, `--skip-system` / `--skip-proton` /
`--skip-dxvk` to leave a part alone. `--skip-switchdeck` never touches
Switchdeck; `--reinstall-switchdeck` replaces it.

When Switchdeck is already installed the installer keeps it and only offers to
reinstall, because reinstalling clears most of Steam's configuration. `-y` does
not answer that one — it means "stop asking", not "yes, wipe it".

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
bash /tmp/install-switchvn.sh --version 0.1.3  # a specific one
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
   tool and pick **GE-Proton11-5-SwitchVN-2**.

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
| [SwitchVN-ProtonGE](https://github.com/BandiFee/SwitchVN-ProtonGE) | winedmo/envideo decoding; DirectShow lifecycle, MPEG/Colour and MP1/MP2 fixes; aarch64 MF and HEVC support; WMP ActiveX video embedding |
| [SwitchVN-Box64](https://github.com/BandiFee/SwitchVN-Box64) | the ffmpeg8 native wrapper — libavcodec 62, libavformat 62, libavutil 60, libswscale 9 and libswresample 6 redirected to the ARM builds |
| [SwitchVN-FFmpeg](https://github.com/BandiFee/SwitchVN-FFmpeg) | aarch64 build of FFmpeg's envideo branch, including the VC-1/WMV3 CPU-writable scratch-map fix |
| [SwitchVN-Envideo](https://github.com/BandiFee/SwitchVN-Envideo) | host1x gather/reloc offset fix |
| [SwitchVN-DXVK-Sarek](https://github.com/BandiFee/SwitchVN-DXVK-Sarek) | D3D9 present mode vsync fix |
| [SwitchVN-Switchdeck](https://github.com/BandiFee/SwitchVN-Switchdeck) | Switchdeck with the DXVK download dropped, so SwitchVN owns `Switchdeck/DXVK` |

## Credits

The SwitchVN-specific integration and compatibility fixes above are maintained
in these forks by BandiFee / Jianhao Fei. They build on the upstream projects
and work of:

- [averne](https://github.com/averne) — envideo and FFmpeg's envideo hardware decoders
- [SildurFX](https://github.com/SildurFX) — Switchdeck
- [pythonlover02](https://github.com/pythonlover02) — DXVK-Sarek
- [GloriousEggroll](https://github.com/GloriousEggroll) — Proton-GE and the media-stack rework used as SwitchVN's base
- [ptitSeb](https://github.com/ptitSeb) — Box64

## License

The installer scripts are GPLv3. Each component keeps its upstream license.
