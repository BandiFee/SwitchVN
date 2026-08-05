# Releasing

[English](RELEASING.md) | [简体中文](RELEASING-CN.md)

A SwitchVN version names one combination of components that was checked
together on hardware. Cutting a release is therefore mostly about testing a
candidate combination, and only then tagging it.

The rule that shapes everything below: **`main` always holds the last
combination that was verified.** Candidates live on `next` until they pass.

---

## The four steps

### 1. Build the component

Change the component, then tag it `<upstream-version>-<revision>` and push the
tag. CI builds and publishes the release asset.

```bash
git -C SwitchVN-Envideo tag -a switchvn-envideo-1.0.0-2 -m "..."
git -C SwitchVN-Envideo push origin switchvn-envideo-1.0.0-2
```

Bump the revision when the upstream base has not moved; reset it to `-1` when
it has (`switchvn-ffmpeg-8.2-1`).

**envideo and FFmpeg move together.** `libenvideo.so` has an unversioned
SONAME, so libavcodec loads whatever copy is installed no matter what it was
compiled against; a mismatch misdecodes instead of failing to link. Touching
envideo means retagging FFmpeg too, and updating `ENVIDEO_REF` in
SwitchVN-FFmpeg's workflow first. The installer refuses a lock that moves only
one of them, and CI checks the pin.

| Changed | Also rebuild |
| --- | --- |
| envideo | FFmpeg (update its `ENVIDEO_REF` first) |
| FFmpeg | Box64, if its wrapper minimums moved (update `FFMPEG_REF`) |
| Box64, DXVK, Proton | nothing else |

Proton is the expensive one — hours on a four-core runner. Its tag must keep
the `GE-Proton11` prefix, because Switchdeck's `launch-steam.sh` decides
whether to apply its vertex-explosion patch by globbing the directory name.

### 2. Put the candidate on `next`

```bash
git switch -c next        # or: git switch next && git merge main
# edit switchvn.lock: new component tags, new SWITCHVN_VERSION
git commit -am "Candidate for SwitchVN 1.1"
git push origin next
```

Pushing `next` runs CI: lock format, every locked asset downloadable, and the
cross-repository pins matching the lock.

### 3. Test it on the Switch

```bash
SWITCHVN_LOCK=https://raw.githubusercontent.com/BandiFee/SwitchVN/next/switchvn.lock \
  bash /tmp/install-switchvn.sh
```

Check the reported versions match the lock. FFmpeg reports a commit rather
than 8.1.1 — its version comes from `git describe`, and the fork carries no
upstream release tags — which pins the build more precisely than a release
number would:

```bash
pkg-config --modversion envideo           # 1.0.0-SwitchVN-N
/usr/local/bin/ffmpeg -version | head -1  # ... <commit>-SwitchVN-N
box64 -v | head -1                        # Box64 arm64 v0.4.5-SwitchVN-N ...
ls -d ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-3-SwitchVN-N
```

Then the regression list. All five have been real bugs here, and none of them
can be caught by CI — there is no Tegra on a GitHub runner:

1. Video shows a picture at all
2. Skipping an opening does not hang the game
3. Skipping does not raise `Error Abort 0x80040211`
4. No tearing during playback
5. A Unity title shows the video rather than audio over a frozen frame

Plus the decode path itself:

```bash
/usr/local/bin/ffmpeg -hwaccel envideo -threads 1 -i something.wmv -frames:v 3 \
    -f rawvideo -pix_fmt nv12 -y /tmp/t.nv12
tr -d '\0' < /tmp/t.nv12 | wc -c          # non-zero
```

Codecs take different paths — VC-1, WMV3, H.264 and MPEG-4 are worth testing
separately.

### 4. Tag it

```bash
git switch main && git merge next
git push origin main
git tag -a v1.1 -m "SwitchVN 1.1"
git push origin v1.1
```

The tag triggers the release workflow, which re-runs every check, asserts the
tag matches `SWITCHVN_VERSION`, generates notes listing the components and what
changed since the previous tag, and attaches `switchvn.lock` as an asset.

That asset is what users get: the installer resolves
`releases/latest/download/switchvn.lock`, so nothing reaches them until this
step.

---

## Numbering

- **Minor** (1.0 → 1.1): any component tag changed.
- **Major** (1.x → 2.0): the user has to do something by hand to upgrade —
  reinstall Switchdeck, a path moved, uninstall-then-install required.

The tag is `v1.1`; `SWITCHVN_VERSION` in the lock is `1.1` without the `v`. CI
asserts they agree.

---

## If a release goes wrong

**Do not delete and re-push a tag.** A GitHub release is owned by its tag, so
deleting the tag deletes the release — that has already emptied a release here
while the build stayed green.

Fix forward with a new revision instead. If a release really has to be redone
before anyone has it, delete the release first (`gh release delete <tag>
--cleanup-tag`), then re-tag — and remember that anything pinning that tag has
to be updated in the same change.
