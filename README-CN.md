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

| 变化 | 修在哪 |
| --- | --- |
| x86 Proton 的 FFmpeg 调用落到原生 ARM 库上,不再被模拟 | Box64 ffmpeg8 包装层 |
| 视频走 NVDEC 硬解,CPU 占用大幅下降 | winedmo + envideo |
| 视频不再黑屏 | envideo host1x gather/reloc 偏移修复 |
| WMV3 / VC-1 不再黑屏 | FFmpeg envideo VC-1 空指针修复 |
| 跳过 OP/ED 不再卡死 | qasf dmowrapper 加锁顺序 |
| 跳过时不再报 `Error Abort 0x80040211` | winedmo wm_reader 分配器处理 |
| 播放时不再有撕裂 | DXVK D3D9 呈现模式 |
| Unity 游戏视频有画面而不只有声音 | aarch64 上默认走 MF 系统内存路径 |

实测 1080p VC-1、20 秒素材:CPU 时间 13.42s → 3.34s。

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
3. 把 **GE-Proton11-3-SwitchVN-1** 解到 `~/.local/share/Steam/compatibilitytools.d/`。
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
bash /tmp/install-switchvn.sh --version 1.0    # 指定版本
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
2. 在游戏的 **属性 → 兼容性** 里勾选强制使用兼容工具,选 **GE-Proton11-3-SwitchVN-1**

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
| [SwitchVN-ProtonGE](https://github.com/BandiFee/SwitchVN-ProtonGE) | winedmo envideo 硬解、qasf 死锁修复、wm_reader 修复、aarch64 MF 回退 |
| [SwitchVN-Box64](https://github.com/BandiFee/SwitchVN-Box64) | ffmpeg8 原生包装层 —— libavcodec 62、libavformat 62、libavutil 60、libswscale 9、libswresample 6 重定向到 ARM 构建 |
| [SwitchVN-FFmpeg](https://github.com/BandiFee/SwitchVN-FFmpeg) | 带 `--enable-envideo` 的 FFmpeg,VC-1 空指针修复 |
| [SwitchVN-Envideo](https://github.com/BandiFee/SwitchVN-Envideo) | host1x gather/reloc 偏移修复 |
| [SwitchVN-DXVK-Sarek](https://github.com/BandiFee/SwitchVN-DXVK-Sarek) | D3D9 呈现模式 vsync 修复 |
| [SwitchVN-Switchdeck](https://github.com/BandiFee/SwitchVN-Switchdeck) | 去掉 DXVK 下载的 Switchdeck,把 `Switchdeck/DXVK` 让给 SwitchVN |

## 致谢

- [averne](https://github.com/averne) —— envideo
- [SildurFX](https://github.com/SildurFX) —— Switchdeck
- [pythonlover02](https://github.com/pythonlover02) —— DXVK-Sarek
- [GloriousEggroll](https://github.com/GloriousEggroll) —— Proton-GE
- [ptitSeb](https://github.com/ptitSeb) —— Box64

## 许可

安装脚本为 GPLv3。各组件沿用其上游许可。
