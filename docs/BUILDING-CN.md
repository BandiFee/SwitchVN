# 自己编译

[English](BUILDING.md) | [简体中文](BUILDING-CN.md)

普通用户不需要看这一页 —— 用 `install-switchvn.sh` 装预编译的就行。

四个组件的构建位置不一样:

| 组件 | 在哪构建 | 大概耗时 |
| --- | --- | --- |
| envideo | Switch 上原生,或 `ubuntu-24.04-arm` | 1 分钟 |
| FFmpeg | 同上 | 20~40 分钟(Switch 上) |
| DXVK | 任意机器交叉编译(mingw-w64) | 5 分钟 |
| Proton | x86_64 PC + Docker | 数小时,需 60~100GB 磁盘 |

每个仓库都有 `.github/workflows/release.yml`,推一个 `switchvn-*` tag(Proton 是
`GE-Proton*-*`)就会自动构建并上传 release 资产。下面是手工复现同样步骤的做法。

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

两个选项都不能改:

- **`--recursive` 是必须的**,有嵌套子模块(`open-gpu-kernel-modules`)。少了它
  meson 会在配置阶段就停下。
- **`-Dtegra-drm=false`**。tegra-drm 后端在 L4T 内核上所有提交都返回 `ENOTTY`,
  用它等于没有硬解。nvgpu 后端才是能用的那条路。

`--libdir=lib` 是为了让 `envideo.pc` 落在 `/usr/local/lib/pkgconfig`,FFmpeg 的
configure 才找得到。

---

## FFmpeg

需要先装好 envideo(上一节)。

```bash
git clone https://github.com/BandiFee/SwitchVN-FFmpeg.git
cd SwitchVN-FFmpeg
PKG_CONFIG_PATH=/usr/local/lib/pkgconfig ./configure \
    --prefix=/usr/local \
    --libdir=/usr/local/lib/aarch64-linux-gnu \
    --shlibdir=/usr/local/lib/aarch64-linux-gnu \
    --enable-shared --disable-static \
    --enable-envideo --disable-doc
grep '^#define CONFIG_ENVIDEO 1' config.h   # 必须命中
make -j$(nproc)
sudo make install
sudo ldconfig
```

**不要加 `--disable-everything` 之类的裁剪。** Box64 的 ffmpeg8 包装层在接管之前
会检查一整组必需符号,少一个就静默回落到模拟 x86 的库 —— 看起来就跟硬解没生效
一模一样,而且不会有任何报错。

装完确认 Box64 要找的两个 soname 在:

```bash
ldconfig -p | grep -E 'libavcodec\.so\.62|libavutil\.so\.60'
```

如果 `/usr/local/lib/aarch64-linux-gnu` 不在 ld 搜索路径里,加一条:

```bash
echo /usr/local/lib/aarch64-linux-gnu | sudo tee /etc/ld.so.conf.d/switchvn.conf
sudo ldconfig
```

---

## DXVK

在任意 x86_64 Linux 上交叉编译,不需要 Switch。

```bash
git clone --recursive https://github.com/BandiFee/SwitchVN-DXVK-Sarek.git
cd SwitchVN-DXVK-Sarek
./package-release.sh switchvn-local /tmp/dxvk-out
```

需要 `mingw-w64`、`meson`、`glslang-tools`。`--recursive` 同样是必须的
(Vulkan-Headers、SPIRV-Headers)。

产物是 `x32/` + `x64/` 布局。`ddraw.dll` 只有 32 位 —— Windows 从来没有 64 位的
DirectDraw 运行时,这是设计如此,不是构建失败。

---

## Proton

最麻烦的一个。需要 x86_64 机器、Docker、60~100GB 空闲磁盘。

```bash
git clone https://github.com/BandiFee/SwitchVN-ProtonGE.git
cd SwitchVN-ProtonGE
git submodule update --init --recursive --force
./patches/protonprep-valve-staging.sh
mkdir build && cd build
../configure.sh --build-name=GE-Proton11-3-SwitchVN-1 --container-engine=docker
make -j$(nproc) redist
```

### 必须知道的几件事

**`--build-name` 必须以 `GE-Proton11` 开头。** Switchdeck 的 `launch-steam.sh` 按
目录名匹配来决定要不要打顶点爆炸补丁(把 `win32u.so` 里的
`VK_EXT_external_memory_host` 改名废掉)。名字对不上,32 位游戏的模型就会炸开。

**`protonprep-valve-staging.sh` 里各处用了 `|| true`。** 补丁应用失败不会让脚本
退出。CI 里加了一步显式检查(`.github/workflows/_job_build.yml`),手工构建的话
自己确认一下:

```bash
grep -q transform_init_hw_decoding wine/dlls/winedmo/unix_transform.c
grep -q "Decommit the output allocators" wine/dlls/qasf/dmowrapper.c
grep -q "no longer committed" wine/dlls/winedmo/wm_reader.c
grep -q '"mfdxgiman" not in self.compat_config' proton
```

四条全过才是完整的 SwitchVN 构建。

**`git submodule update --recursive --force` 里的 `--force` 不能省。** 半初始化的
子模块会让构建在 `openfst/configure.ac` 找不到之类的地方失败,信息完全指不到病根。

**在 macOS 上准备补丁的话要用 GNU patch。** Apple 的 `/usr/bin/patch` 会静默改坏
这套补丁系列。`brew install gpatch`,然后用 `gpatch`。

### 已知的坑

- 子模块的 mtime 变化会触发 xz 的 maintainer-mode 重新生成,而 `build-aux/missing`
  不存在,报 `aclocal.m4 Error 127`。清掉重来:
  `rm -rf build/src-xz build/obj-xz-* build/.xz-*`
- 磁盘满了会伪装成各种莫名其妙的编译错误(最常见的是 xz 和 kaldi)。先
  `df -h` 再怀疑代码。

---

## 各仓库的关键提交

出问题时用来确认自己的 checkout 是否包含修复:

| 仓库 | 提交 | 修的是 |
| --- | --- | --- |
| SwitchVN-Envideo | `a7555fd` | host1x gather/reloc 少算 `mem_offset` —— 影响所有编解码器,表现为黑屏 |
| SwitchVN-FFmpeg | `a16722a5` | VC-1 引擎 scratch map 需要 CPU 可写,否则 memset 空指针 |
| SwitchVN-DXVK-Sarek | `972cd8f3` | D3D9 `CreatePresenter` 写死了非 vsync 呈现模式,导致撕裂 |
| SwitchVN-ProtonGE | `483cd991` | winedmo 通过 envideo 硬解 |
| SwitchVN-ProtonGE | `b88b43b4` | qasf dmowrapper 在持锁状态下 decommit 造成死锁 |
| SwitchVN-ProtonGE | `773849b2` | wm_reader 把已 decommit 的分配器当作流结束 |
| SwitchVN-ProtonGE | `4dbdca72` | aarch64 上让 MF 走系统内存样本 |
