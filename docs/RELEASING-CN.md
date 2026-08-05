# 发版

[English](RELEASING.md) | [简体中文](RELEASING-CN.md)

SwitchVN 的版本号代表**一组在真机上一起验过的组件组合**。所以发版的主体是"验证一个
候选组合",打 tag 只是最后一步。

贯穿下面所有内容的一条规则:**`main` 上永远是最后一个验过的组合**。候选放在 `next`,
验过了才合进来。

---

## 四步

### 1. 构建组件

改完组件,打 `<上游版本>-<修订号>` 的 tag 推上去,CI 自动构建并发布资产。

```bash
git -C SwitchVN-Envideo tag -a switchvn-envideo-1.0.0-2 -m "..."
git -C SwitchVN-Envideo push origin switchvn-envideo-1.0.0-2
```

上游没动就递增修订号;上游升级了就重新从 `-1` 开始(`switchvn-ffmpeg-8.2-1`)。

**envideo 和 FFmpeg 必须同进同退。** `libenvideo.so` 的 SONAME 没有版本号,libavcodec
装的是哪份就加载哪份,不管它当初对着谁编译;配错了不报链接错误,只会解码出错。所以
动了 envideo 就必须重发 FFmpeg,而且要**先**改 SwitchVN-FFmpeg workflow 里的
`ENVIDEO_REF`。安装器会拒绝只动其中一个的 lock,CI 也会检查这个 pin。

| 改了什么 | 还要重发什么 |
| --- | --- |
| envideo | FFmpeg(先改它的 `ENVIDEO_REF`) |
| FFmpeg | Box64,如果包装层的最低版本表变了(改 `FFMPEG_REF`) |
| Box64 / DXVK / Proton | 无 |

Proton 最贵 —— 4 核 runner 上要几小时。它的 tag 必须保留 `GE-Proton11` 前缀,因为
Switchdeck 的 `launch-steam.sh` 是按目录名 glob 来决定要不要打顶点爆炸补丁的。

### 2. 把候选放到 `next`

```bash
git switch -c next        # 或:git switch next && git merge main
# 改 switchvn.lock:新的组件 tag、新的 SWITCHVN_VERSION
git commit -am "Candidate for SwitchVN 1.1"
git push origin next
```

推 `next` 会跑 CI:lock 格式、每个资产 URL 可下载、跨仓库 pin 与 lock 一致。

### 3. 在 Switch 上验证

```bash
SWITCHVN_LOCK=https://raw.githubusercontent.com/BandiFee/SwitchVN/next/switchvn.lock \
  bash /tmp/install-switchvn.sh
```

先核对自报版本和 lock 对得上。FFmpeg 报的是 commit 而不是 8.1.1 —— 它的版本串来自
`git describe`,而 fork 里没有上游的版本 tag。这比版本号定位得更准:

```bash
pkg-config --modversion envideo           # 1.0.0-SwitchVN-N
/usr/local/bin/ffmpeg -version | head -1  # ... <commit>-SwitchVN-N
box64 -v | head -1                        # Box64 arm64 v0.4.5-SwitchVN-N ...
ls -d ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-3-SwitchVN-N
```

然后跑回归清单。这五项都是这个项目真实出过的 bug,而且 **CI 一项都验不了** ——
GitHub runner 上没有 Tegra:

1. 视频能出画面
2. 跳过 OP/ED 不卡死
3. 跳过时不报 `Error Abort 0x80040211`
4. 播放时无撕裂
5. Unity 游戏有画面,而不是只有声音配一张静止画

再加解码链路本身:

```bash
/usr/local/bin/ffmpeg -hwaccel envideo -threads 1 -i 某个.wmv -frames:v 3 \
    -f rawvideo -pix_fmt nv12 -y /tmp/t.nv12
tr -d '\0' < /tmp/t.nv12 | wc -c          # 非零
```

不同编解码器走不同代码路径,VC-1、WMV3、H.264、MPEG-4 值得分别试。

### 4. 打 tag

```bash
git switch main && git merge next
git push origin main
git tag -a v1.1 -m "SwitchVN 1.1"
git push origin v1.1
```

tag 触发 release workflow:重跑全部校验、断言 tag 和 `SWITCHVN_VERSION` 一致、
生成含组件表和"相对上一版变了什么"的 release notes、把 `switchvn.lock` 作为资产上传。

**那个资产才是用户拿到的东西** —— 安装器解析的是
`releases/latest/download/switchvn.lock`,所以在这一步之前,改动不会影响任何人。

---

## 版本号

- **次版本**(1.0 → 1.1):任意组件的 tag 变了
- **主版本**(1.x → 2.0):用户必须手动做点什么才能升 —— 重装 Switchdeck、路径变了、
  需要先卸载再装

tag 是 `v1.1`,lock 里的 `SWITCHVN_VERSION` 是不带 `v` 的 `1.1`,CI 会断言两者一致。

---

## 发版出错了怎么办

**不要删 tag 再推。** GitHub 的 release 挂在 tag 上,删 tag 会把 release 一起删掉 ——
这个项目已经因此出现过"构建全绿但 release 是空的"。

正确做法是往前修:发一个新的修订号。如果确实要在没人拿到之前重来,先删 release
(`gh release delete <tag> --cleanup-tag`)再重打 tag —— 并且记住**所有钉着那个 tag
的地方都要在同一次改动里更新**。
