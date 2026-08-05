#!/usr/bin/env python3
"""Check that the component repositories' cross-references match the lock.

SwitchVN-FFmpeg builds against a pinned envideo tag, and SwitchVN-Box64 checks
its ffmpeg8 wrapper minimums against a pinned FFmpeg tag. Both pins live in
those repositories' workflows and are maintained by hand.

Nothing enforces that they agree with switchvn.lock, and they have already
drifted once: retiring an envideo release deleted the tag SwitchVN-FFmpeg was
pinned to, which would have failed the next FFmpeg build at checkout.
"""

import re
import sys
import urllib.error
import urllib.request

RAW = "https://raw.githubusercontent.com/{repo}/{branch}/{path}"

# (label, repo, default branch, workflow path, variable, lock component it must equal)
PINS = [
    (
        "SwitchVN-FFmpeg ENVIDEO_REF",
        "BandiFee/SwitchVN-FFmpeg",
        "envideo",
        ".github/workflows/release.yml",
        "ENVIDEO_REF",
        "envideo",
    ),
    (
        "SwitchVN-Box64 FFMPEG_REF",
        "BandiFee/SwitchVN-Box64",
        "main",
        ".github/workflows/switchvn-release.yml",
        "FFMPEG_REF",
        "ffmpeg",
    ),
]


def lock_tags(path):
    tags = {}
    for raw in open(path):
        fields = raw.split()
        if len(fields) == 4 and not raw.lstrip().startswith("#"):
            tags[fields[0]] = fields[2]
    return tags


def fetch(repo, branch, path):
    url = RAW.format(repo=repo, branch=branch, path=path)
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.read().decode()


def main(lock_path):
    tags = lock_tags(lock_path)
    failed = False

    for label, repo, branch, path, var, component in PINS:
        want = tags.get(component)
        if want is None:
            print(f"::error::the lock has no '{component}' entry")
            failed = True
            continue

        try:
            text = fetch(repo, branch, path)
        except urllib.error.URLError as e:
            print(f"::error::cannot read {repo}/{path}: {e}")
            failed = True
            continue

        # Matches the `env:` entry, e.g.  ENVIDEO_REF: switchvn-envideo-1.0.0-1
        m = re.search(rf"^\s*{var}:\s*(\S+)\s*$", text, re.M)
        if not m:
            print(f"::error::{label} not found in {repo}/{path}")
            failed = True
            continue

        have = m.group(1).strip("'\"")
        if have == want:
            print(f"ok   {label} = {have}")
        else:
            print(f"FAIL {label} = {have}, lock says {want}")
            print(f"::error::{label} is {have} but the lock pins {component} at {want}")
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "switchvn.lock"))
