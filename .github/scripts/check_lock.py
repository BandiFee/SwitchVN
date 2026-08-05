#!/usr/bin/env python3
"""Validate switchvn.lock structurally.

The installer parses this file with awk on whitespace, so anything malformed
tends to produce a confusing failure late in an install rather than an obvious
one here.
"""

import sys

# Everything the installer looks up by name. Missing one of these is a hard
# error, not a warning: install-switchvn.sh dies on an absent entry.
REQUIRED = {"envideo", "ffmpeg", "dxvk", "box64", "proton"}


def main(path):
    version = None
    seen = {}
    errors = []

    for lineno, raw in enumerate(open(path), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        fields = line.split()
        if fields[0] == "SWITCHVN_VERSION":
            if len(fields) != 2:
                errors.append(f"{path}:{lineno}: SWITCHVN_VERSION takes exactly one value")
            elif version is not None:
                errors.append(f"{path}:{lineno}: SWITCHVN_VERSION given more than once")
            else:
                version = fields[1]
            continue

        if len(fields) != 4:
            errors.append(
                f"{path}:{lineno}: expected 4 fields (name repo tag asset), got {len(fields)}"
            )
            continue

        name, repo, tag, asset = fields
        if name in seen:
            errors.append(f"{path}:{lineno}: '{name}' already defined on line {seen[name]}")
        seen[name] = lineno

        if "/" not in repo:
            errors.append(f"{path}:{lineno}: '{repo}' is not owner/repo")

        # The installer derives the Proton directory name from the asset name
        # and refuses anything that would not match Switchdeck's GE-Proton11*
        # glob, which is what drives its vertex-explosion patch.
        if name == "proton" and not asset.startswith("GE-Proton11"):
            errors.append(
                f"{path}:{lineno}: proton asset must start with GE-Proton11, got '{asset}'"
            )
        if name == "proton" and not tag.startswith("GE-Proton11"):
            errors.append(
                f"{path}:{lineno}: proton tag must start with GE-Proton11, got '{tag}'"
            )

    if version is None:
        errors.append(f"{path}: no SWITCHVN_VERSION")

    missing = REQUIRED - seen.keys()
    if missing:
        errors.append(f"{path}: missing component(s): {', '.join(sorted(missing))}")

    for e in errors:
        print(f"::error::{e}")
    if errors:
        return 1

    print(f"ok   SWITCHVN_VERSION {version}")
    for name in sorted(seen):
        print(f"ok   {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "switchvn.lock"))
