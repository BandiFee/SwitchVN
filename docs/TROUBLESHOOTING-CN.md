# 排查

[English](TROUBLESHOOTING.md) | [简体中文](TROUBLESHOOTING-CN.md)

按"最可能"到"最少见"排。每一节都先给判据,再给结论。

---

## 视频黑屏,但有声音

先确定是哪一层坏了。

```bash
/usr/local/bin/ffmpeg -hwaccel envideo -threads 1 -i 你的视频 -frames:v 3 \
    -f rawvideo -pix_fmt nv12 -y /tmp/t.nv12
tr -d '\0' < /tmp/t.nv12 | wc -c
```

- **输出 0** —— 系统组件那一层就不对,往下看。
- **输出非零** —— envideo/FFmpeg 是好的,问题在 Proton 侧,跳到本页的 Proton 小节。

### 装了两份 libenvideo

历史上最容易踩的一个。手动编译过一次装到 `/usr/local`,之后又装了别处的包,
两份同名库都在 ld 缓存里,加载到旧的那份就是黑屏且不报错。

```bash
ldconfig -p | grep libenvideo
```

只应有一行。多于一行就把旧的删掉再 `sudo ldconfig`。

### Box64 根本没在用原生 FFmpeg

Box64 的 ffmpeg8 包装层按 soname 绑定,并且要求一整组符号全部存在。少一个就
**静默**回落到模拟 x86 的库 —— 表现和"硬解没生效"一模一样,不会有任何报错。

```bash
ldconfig -p | grep -E 'libavcodec\.so\.62|libavutil\.so\.60'
```

两行都要有。缺了就重跑安装器,或确认 `/etc/ld.so.conf.d/switchvn.conf` 存在且
`sudo ldconfig` 跑过。

另外确认没有设 `BOX64_EMULATED_LIBS` 把 ffmpeg 列进去 —— 那会显式关掉包装层。

### 权限 / 设备节点

```bash
ls -l /dev/nvhost-nvdec /dev/nvmap
id -nG | tr ' ' '\n' | grep -x video
```

不在 `video` 组:`sudo usermod -aG video $USER`,然后**重新登录**(重开终端不够)。

### 重启之后又黑屏了

检查 `/usr/local` 的东西还在不在,以及 ld 缓存:

```bash
ls /usr/local/lib/aarch64-linux-gnu/libavcodec.so.62
ldconfig -p | grep -c libenvideo
```

如果 `switchvn.conf` 还在但缓存里没有,直接 `sudo ldconfig`。

---

## dmesg 里出现 `cdma_handle_timeout`

host1x 的命令提交超时了。通常意味着提交给硬件的命令缓冲不对,而不是驱动本身有问题。

如果你用的是自己编译的 envideo,确认包含了
`cmdbuf: account for host1x gather and reloc offsets`(commit `a7555fd`)。
少了这个补丁,所有编解码器都会出画面异常。

---

## 视频有画面但有横向 / 对角线撕裂

DXVK 那一层。确认 Proton 里的 DXVK 是 SwitchVN 版本:

```bash
ls -l ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-*/files/lib/wine/dxvk/x86_64-windows/d3d9.dll
```

应该是一条指向 `.../files/lib/switchvn-dxvk/x64/d3d9.dll` 的符号链接。

如果它指向 `~/.local/share/Steam/Switchdeck/DXVK/...`,说明 Switchdeck 把它换回去了 ——
重跑一次安装器(可以只跑 `--skip-system --skip-proton`)。

---

## 跳过 OP/ED 时游戏卡死或报 `Error Abort 0x80040211`

这两个都是 Proton 侧的补丁修的。确认你用的确实是 SwitchVN 的 Proton:

```bash
grep -c SwitchVN ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-3-SwitchVN-1/compatibilitytool.vdf
```

以及游戏属性里真的选中了它 —— Steam 的"默认兼容工具"设置不会覆盖单个游戏的设置,
反过来也一样,容易看错。

---

## Unity 游戏只有声音,没有画面

这是已知且**必须**这么处理的一件事,不是 bug。

Switchdeck 为了修 32 位游戏的顶点爆炸,会二进制改写 Proton 的 `win32u.so`,把
`VK_EXT_external_memory_host` 这个字符串改名废掉。副作用是 winevulkan 不再暴露
`VK_KHR_external_memory_win32`,于是 DXVK 无法导出共享纹理,Media Foundation 的
D3D 采样路径失效 —— 表现就是有声无画。

SwitchVN 的 Proton 在 aarch64 上默认设 `WINE_DO_NOT_CREATE_DXGI_DEVICE_MANAGER=1`,
让 MF 走系统内存样本路径绕开它。**在这套环境下这是必需项,不是临时绕过**,不要试图
"修好"共享纹理路径 —— 修好了顶点爆炸就回来了。

如果某个游戏你确实想关掉这个默认值,在 Steam 的兼容性选项里加
`mfdxgiman`(Proton 的 compat config),SwitchVN 就不会设那个变量了。

---

## 装完之后 Steam 里看不到 GE-Proton11-3-SwitchVN-1

必须**完全退出 Steam** 再用 Switchdeck 的启动器起来:

```bash
~/.local/share/Steam/launch-steam.sh
```

Steam 只在启动时扫一次 `compatibilitytools.d`。

---

## 想确认 GPU 到底有没有在解码

最可靠的是看日志:

```bash
grep -E 'trying envideo decoding|decoding in software|no usable envideo device' ~/steam-*.log
```

（需要启动选项 `WINEDEBUG=+dmo PROTON_LOG=1 %command%`。）

想看硬件那一侧,L4T 内核在 debugfs 里暴露了 NVDEC 的时钟,播放时应该被拉起来:

```bash
sudo find /sys/kernel/debug/clk -maxdepth 1 -name '*nvdec*'
# 找到之后
sudo cat /sys/kernel/debug/clk/<上面找到的名字>/clk_rate
```

不同内核版本的节点名不一样,所以先 `find` 再看。CPU 占用也是个粗略但有效的判据 ——
软解 1080p VC-1 会跑满一个核,硬解不会。

---

## 还是不行

开个 issue,附上:

```bash
uname -a
ldconfig -p | grep -E 'libenvideo|libavcodec|libavutil'
ls -l ~/.local/share/Steam/compatibilitytools.d/
ffprobe 你的视频 2>&1 | tail -20
```

以及带 `WINEDEBUG=+dmo PROTON_LOG=1` 跑出来的 `~/steam-*.log`。
视频的编解码器信息很重要 —— VC-1 / WMV3 / H.264 / MPEG-4 走的是不同的代码路径。
