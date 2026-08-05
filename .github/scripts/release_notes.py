#!/usr/bin/env python3
"""Build release notes from the lock, plus what moved since the previous tag.

Usage: release_notes.py <this-tag> [previous-lock]

The component table is the useful part of a SwitchVN release: the version
number only means "this combination was checked on hardware", so the notes have
to say which combination that is.
"""

import sys

LABELS = {
    "envideo": "envideo",
    "ffmpeg": "FFmpeg",
    "dxvk": "DXVK",
    "box64": "Box64",
    "proton": "Proton",
}
ORDER = ["proton", "box64", "ffmpeg", "envideo", "dxvk"]


def read(path):
    version, comps = None, {}
    for raw in open(path):
        if raw.lstrip().startswith("#"):
            continue
        f = raw.split()
        if len(f) == 2 and f[0] == "SWITCHVN_VERSION":
            version = f[1]
        elif len(f) == 4:
            comps[f[0]] = (f[1], f[2])
    return version, comps


def main(argv):
    tag = argv[1]
    version, comps = read("switchvn.lock")
    prev_comps = {}
    prev_version = None
    if len(argv) > 2 and argv[2]:
        try:
            prev_version, prev_comps = read(argv[2])
        except OSError:
            pass

    out = []
    out.append(f"SwitchVN {version} — one combination of components, checked together on hardware.")
    out.append("")
    out.append("| Component | Version |")
    out.append("| --- | --- |")
    for key in ORDER:
        if key not in comps:
            continue
        repo, ctag = comps[key]
        out.append(f"| [{LABELS[key]}](https://github.com/{repo}/releases/tag/{ctag}) | `{ctag}` |")

    if prev_comps:
        changed = [
            (LABELS[k], prev_comps[k][1], comps[k][1])
            for k in ORDER
            if k in comps and k in prev_comps and prev_comps[k][1] != comps[k][1]
        ]
        out.append("")
        if changed:
            out.append(f"### Changed since {prev_version}")
            out.append("")
            for label, old, new in changed:
                out.append(f"- **{label}**: `{old}` → `{new}`")
        else:
            out.append(f"No component changed since {prev_version}.")

    out.append("")
    out.append("### Install")
    out.append("")
    out.append("```bash")
    out.append(
        "curl -fsSL -o /tmp/install-switchvn.sh "
        "https://raw.githubusercontent.com/BandiFee/SwitchVN/main/install-switchvn.sh \\"
    )
    out.append("  && bash /tmp/install-switchvn.sh")
    out.append("```")
    out.append("")
    out.append(f"To install this version specifically once a newer one exists, add `--version {version}`.")

    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
