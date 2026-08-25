# SwitchVN

[English](README.md) | [简体中文](README-CN.md)

Nintendo Switch(switchroot Ubuntu)上的 Galgame / 视觉小说视频硬件解码。

Switch 的 Tegra X1 有 NVDEC 硬件解码器,但 Wine/Proton 走不到它,中间挡着两件事:
winedmo 只会向 FFmpeg 要软解;而 Box64 下的 x86 Proton 根本不知道系统里有原生的
ARM FFmpeg,就算装了能硬解的 FFmpeg 也会被逐条指令模拟。结果就是 OP/ED 掉帧、
卡顿,甚至黑屏。

SwitchVN 把整条链路接通 —— 一个 Box64 包装层把 x86 的 FFmpeg 调用转到原生 ARM 库上、
FFmpeg 里的 envideo hwaccel、以及 winedmo 主动去要它 —— 并顺带修掉了路上撞到的一串 bug。

**面向普通用户:一条命令。** 没装
[SwitchVN-Switchdeck](https://github.com/BandiFee/SwitchVN-Switchdeck) 的话它会一并装上,
装了的话就不动它。

```bash
curl -fsSL -o /tmp/install-switchvn.sh https://raw.githubusercontent.com/BandiFee/SwitchVN/main/install-switchvn.sh \
  && bash /tmp/install-switchvn.sh
```

---

## 装了会得到什么

| 效果 | SwitchVN 的工作 |
| --- | --- |
| x86 Proton 的 FFmpeg 调用落到原生 ARM 库上,不再被模拟 | Box64 ffmpeg8 包装层 |
| 兼容的视频走 NVDEC 硬解,不支持的流自动回落软解 | winedmo + envideo 集成 |
| 视频不再因 Tegra host 偏移或 VC-1/WMV3 scratch 映射问题而黑屏 | envideo + FFmpeg 修复 |
| 跳过或停止 OP/ED 不再卡死或报 `Error Abort 0x80040211` | DirectShow 流与分配器生命周期修复 |
| 播放时不再有撕裂 | DXVK D3D9 呈现模式 |
| Unity 游戏视频有画面而不只有声音 | aarch64 上默认走 MF 系统内存路径 |
| 旧式 MPEG graph 能正确协商视频,并提供完整的 MP1/MP2 音频类型 | DirectShow/Quartz 兼容性修复 |
| Media Foundation 程序可以选择由 winedmo 和 envideo 支撑的 H.265/HEVC 解码器 | HEVC MFT 注册与媒体类型支持 |
| WMP ActiveX 播放能嵌入、缩放并正确清理 DirectShow 视频窗口 | `GE-Proton11-5-SwitchVN-2` 的 WMP/DirectShow 集成 |

### 硬件解码能力

当前 FFmpeg 构建启用了以下 envideo 硬件解码器:

| 编码 | FFmpeg hwaccel |
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

这个列表表示 SwitchVN 构建启用了对应解码器,并不保证每种封装、编码 Profile、Level
或分辨率都能硬解。设备与视频流兼容时 winedmo 会使用 envideo,否则自动回落软解。
下文的 `.wmv`、`.asf`、`.mpg`、`.mp4` 等扩展名只是播放路径示例,不是对整个封装
格式的无条件承诺。

### 播放路径

| 路径 | 代码支持 | 已记录的真机验证 |
| --- | --- | --- |
| DirectShow/Quartz | ASF/WMV 与旧式 MPEG graph;MPEG sequence header 恢复、Colour 转换和完整 MP1/MP2 媒体类型 | 已验证 VC-1/WMV3 播放和旧式 MPEG + MP2 OP 播放 |
| qasf/WM Reader | 安全的停止/跳过顺序和分配器关闭 | 已验证 VC-1/WMV3 停止、跳过回归 |
| Media Foundation | Unity 所需的 aarch64 系统内存交付;通过 winedmo/envideo 注册 H.265/HEVC 解码器 | 已验证 Unity 系统内存路径;HEVC 专项真机覆盖待补 |
| WMP ActiveX | `GE-Proton11-5-SwitchVN-2` 中 DirectShow 视频窗口的所有权、嵌入、缩放、显隐和清理 | 代码已实现;专项真机回归待补 |

### 性能

| 编码 | 素材 | 软解 CPU 时间 | NVDEC CPU 时间 | 降幅 | 状态 |
| --- | --- | ---: | ---: | ---: | --- |
| VC-1 | 1080p、20 秒 | 13.42s | 3.34s | 75.1% | 已实测 |
| H.264/AVC | 同方法素材 | TBD | TBD | TBD | 尚未测量 |
| H.265/HEVC | 同方法素材 | TBD | TBD | TBD | 尚未测量 |
| MPEG-1/2 Video | 同方法素材 | TBD | TBD | TBD | 尚未测量 |
| MPEG-4 Part 2 | 同方法素材 | TBD | TBD | TBD | 尚未测量 |
| WMV3 | 同方法素材 | TBD | TBD | TBD | 尚未测量 |
| VP8/VP9 | 同方法素材 | TBD | TBD | TBD | 尚未测量 |
| MJPEG | 同方法素材 | TBD | TBD | TBD | 尚未测量 |

`TBD` 表示还没有同口径的测量记录,不代表解码器不支持或测试失败。

---

## 前置条件

- Nintendo Switch,运行 switchroot Ubuntu(aarch64,Ubuntu 24.04 系)
- 别的都不需要 —— 缺 [SwitchVN-Switchdeck](https://github.com/BandiFee/SwitchVN-Switchdeck)
  (Steam、Box64、启动器)时安装器会问你要不要装
- 当前用户在 `video` 组里(`id -nG | grep video`,不在就
  `sudo usermod -aG video $USER` 然后重新登录)
- 存在 `/dev/nvhost-nvdec` 和 `/dev/nvmap`

安装器会逐条检查这些,缺什么会直接告诉你。

---

## 安装

```bash
curl -fsSL -o /tmp/install-switchvn.sh https://raw.githubusercontent.com/BandiFee/SwitchVN/main/install-switchvn.sh \
  && bash /tmp/install-switchvn.sh
```

它做五件事:

1. 把原生 aarch64 的 **envideo** 和 **FFmpeg** 装进 `/usr/local`(需要 sudo)。
2. 装带 ffmpeg8 包装层的 **Box64**,它把 x86 Proton 里的 `libavcodec.so.62` /
   `libavutil.so.60` 重定向到上面那两个原生库。版本很关键,见下文。
3. 把 **GE-Proton11-5-SwitchVN-2** 解到 `~/.local/share/Steam/compatibilitytools.d/`。
4. 把修好的 **DXVK** 放进 Proton 目录内部,再做符号链接。
5. 自检:`libenvideo.so` 只能有一份,两个 FFmpeg soname 必须在 ld 缓存里。

第 2 步会顶掉已装的 pi-apps `box64-tegrax1` —— 包里声明了对它的
`Conflicts`/`Replaces`,所以 dpkg 会直接替换,而不是拒绝覆盖 `/usr/bin/box64`。

可用参数:`-y` 不询问,`--skip-system` / `--skip-proton` / `--skip-dxvk` 跳过某一部分;
`--skip-switchdeck` 完全不碰 Switchdeck,`--reinstall-switchdeck` 强制重装。

Switchdeck 已经装了的话,安装器只会**问你**要不要重装,因为重装会清掉 Steam 的大部分
配置。`-y` **不会**替你答应这一条 —— 它的意思是「别再问我」,不是「是,清掉」。

### 版本

SwitchVN 的版本号代表**一组在真机上一起验过的组件组合**,不是功能版本。这几个组件
不是独立的:libavcodec 链接 `libenvideo.so`,而后者 SONAME 里没有版本号,加载器
来者不拒,配错了不会报链接错误,只会解码出错。

组合记在 [switchvn.lock](switchvn.lock) 里,作为每个 release 的资产发布。安装器先取
对应版本的 lock,再按里面写死的 tag 下载组件。

```bash
bash /tmp/install-switchvn.sh                  # 最新版
bash /tmp/install-switchvn.sh --version 0.1.3  # 指定版本
```

重装时会打印哪些组件要变;如果某份 lock 只动了 envideo 和 FFmpeg 中的一个,直接拒绝。

想试还没发布的组合,把 `SWITCHVN_LOCK` 指向一个 lock 文件或 URL —— 候选版就是这么
在打 tag 之前验证的:

```bash
SWITCHVN_LOCK=https://raw.githubusercontent.com/BandiFee/SwitchVN/next/switchvn.lock \
  bash /tmp/install-switchvn.sh
```

装完之后:

1. 用 Switchdeck 的启动器重启 Steam:`~/.local/share/Steam/launch-steam.sh`
2. 在游戏的 **属性 → 兼容性** 里勾选强制使用兼容工具,选 **GE-Proton11-5-SwitchVN-2**

### 为什么 DXVK 要塞进 Proton 目录里

`launch-steam.sh` 每次启动 Steam 都会把所有 Proton 的 `wine/dxvk` 从
`$STEAMROOT/Switchdeck/DXVK` 重新链一遍,所以只放进 Proton 目录的话下次启动就会被顶掉。
SwitchVN 因此也会填充 `Switchdeck/DXVK` —— 这也正是 SwitchVN-Switchdeck 要去掉上游那段
DXVK 下载的原因:留着的话,上游 DXVK-Sarek 一发新版就会把那个目录覆盖成原版。

而这段重链有个幂等判断:`d3d11.dll` 和 `d3d12.dll`
**同时**已经是符号链接就整块跳过。所以安装器把 DLL 放在
`$PROTON/files/lib/switchvn-dxvk/`,把 Proton 的 `dxvk/` 和 `vkd3d-proton/`
目录做成指向那里的符号链接 —— Switchdeck 于是不再碰这个 Proton 的 DXVK。

顶点爆炸补丁是独立的一段 `find`,不受影响,仍然照常应用。这也是为什么 Proton
目录名必须以 `GE-Proton11` 开头,安装器会检查这一点。

---

## 验证硬解真的生效了

命令行一层:

```bash
/usr/local/bin/ffmpeg -hwaccel envideo -threads 1 -i 某个视频.wmv -frames:v 3 -f rawvideo -pix_fmt nv12 -y /tmp/t.nv12
tr -d '\0' < /tmp/t.nv12 | wc -c
```

输出非零就说明 envideo + FFmpeg 那层是好的;为 0 说明系统组件没装对。

游戏一层 —— 把启动选项设成:

```
WINEDEBUG=+dmo PROTON_LOG=1 %command%
```

播完过场动画后:

```bash
grep -E 'trying envideo decoding|decoding in software|no usable envideo device' ~/steam-*.log
```

看到 `trying envideo decoding for <codec>` 且下面没有回落行,就是成功了。

---

## 卸载

```bash
curl -fsSL -o /tmp/uninstall-switchvn.sh https://raw.githubusercontent.com/BandiFee/SwitchVN/main/uninstall-switchvn.sh \
  && bash /tmp/uninstall-switchvn.sh
```

按安装时记下的文件清单删除,不会误删 `/usr/local` 里别的东西。Switchdeck 本身不动。

---

## 出问题了

看 [docs/TROUBLESHOOTING-CN.md](docs/TROUBLESHOOTING-CN.md)。

## 自己编译

看 [docs/BUILDING-CN.md](docs/BUILDING-CN.md);发版流程见
[docs/RELEASING-CN.md](docs/RELEASING-CN.md)。组件仓库:

| 仓库 | 内容 |
| --- | --- |
| [SwitchVN-ProtonGE](https://github.com/BandiFee/SwitchVN-ProtonGE) | winedmo/envideo 硬解;DirectShow 生命周期、MPEG/Colour 与 MP1/MP2 修复;aarch64 MF、HEVC 支持和 WMP ActiveX 视频嵌入 |
| [SwitchVN-Box64](https://github.com/BandiFee/SwitchVN-Box64) | ffmpeg8 原生包装层 —— libavcodec 62、libavformat 62、libavutil 60、libswscale 9、libswresample 6 重定向到 ARM 构建 |
| [SwitchVN-FFmpeg](https://github.com/BandiFee/SwitchVN-FFmpeg) | FFmpeg envideo 分支的 aarch64 构建,含 VC-1/WMV3 scratch map CPU 可写修复 |
| [SwitchVN-Envideo](https://github.com/BandiFee/SwitchVN-Envideo) | host1x gather/reloc 偏移修复 |
| [SwitchVN-DXVK-Sarek](https://github.com/BandiFee/SwitchVN-DXVK-Sarek) | D3D9 呈现模式 vsync 修复 |
| [SwitchVN-Switchdeck](https://github.com/BandiFee/SwitchVN-Switchdeck) | 去掉 DXVK 下载的 Switchdeck,把 `Switchdeck/DXVK` 让给 SwitchVN |

## 致谢

上面列出的 SwitchVN 专属集成与兼容性修复由 BandiFee / Jianhao Fei 在这些 fork 中
编写和维护;它们建立在以下上游项目与作者的工作之上:

- [averne](https://github.com/averne) —— envideo 和 FFmpeg envideo 硬件解码器
- [SildurFX](https://github.com/SildurFX) —— Switchdeck
- [pythonlover02](https://github.com/pythonlover02) —— DXVK-Sarek
- [GloriousEggroll](https://github.com/GloriousEggroll) —— Proton-GE 和 SwitchVN 使用的媒体栈重构基础
- [ptitSeb](https://github.com/ptitSeb) —— Box64

## 许可

安装脚本为 GPLv3。各组件沿用其上游许可。
