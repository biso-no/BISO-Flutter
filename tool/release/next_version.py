#!/usr/bin/env python3
"""Works out the version a release ships as.

The inputs are pubspec.yaml's `version:` line and the release tags, which look
like `v2.2.17+101` (release.yml creates one per release).

- `--bump auto`, used on every push to main: if pubspec.yaml carries a build
  number that no tag has reached, someone bumped it by hand and that version
  ships as it is. Otherwise both the patch number and the build number go up
  by one, so 2.2.16+100 becomes 2.2.17+101.
- `--bump patch|minor|major`, from a manual run: that part goes up, counting
  from the newer of pubspec.yaml and the last tag, and the build number goes up
  by one.

With no release tags yet, pubspec.yaml's version is taken as already released.

Writes `version`, `build_number`, `tag` and `previous_tag` to $GITHUB_OUTPUT,
or prints them when run outside GitHub Actions. `previous_tag` is where the
release notes start: the last release tag, or the newest tag of any name.
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

VERSION_PATTERN = re.compile(r"^(\d+)\.(\d+)\.(\d+)\+(\d+)$")
TAG_PATTERN = re.compile(r"^v(\d+\.\d+\.\d+\+\d+)$")


class Version(NamedTuple):
    major: int
    minor: int
    patch: int
    build: int

    @classmethod
    def parse(cls, text: str) -> "Version":
        match = VERSION_PATTERN.match(text)
        if not match:
            sys.exit(f"'{text}' is not a version like 1.2.3+45")
        return cls(*(int(part) for part in match.groups()))

    @property
    def name(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"

    def __str__(self) -> str:
        return f"{self.name}+{self.build}"


def git(*args: str) -> str:
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def pubspec_version(path: Path) -> Version:
    for line in path.read_text().splitlines():
        if line.startswith("version:"):
            return Version.parse(line.removeprefix("version:").strip())
    sys.exit(f"{path} has no version: line")


def released_versions() -> list[Version]:
    tags = git("tag", "--list", "v*").splitlines()
    return [Version.parse(match[1]) for tag in tags if (match := TAG_PATTERN.match(tag))]


def next_version(current: Version, released: list[Version], bump: str) -> Version:
    last = max(released, key=lambda version: version.build, default=None)

    if bump == "auto":
        if last is not None and current.build > last.build:
            if current[:3] < last[:3]:
                sys.exit(f"pubspec.yaml's {current} is older than the released {last}")
            return current
        bump = "patch"

    base = last if last is not None and last.build > current.build else current
    major, minor, patch = base.major, base.minor, base.patch
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    return Version(major, minor, patch, base.build + 1)


def previous_tag(released: list[Version]) -> str:
    if released:
        return f"v{max(released, key=lambda version: version.build)}"
    return git("describe", "--tags", "--abbrev=0", "HEAD")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bump", choices=["auto", "patch", "minor", "major"], default="auto")
    parser.add_argument("--pubspec", type=Path, default=Path("pubspec.yaml"))
    args = parser.parse_args()

    released = released_versions()
    version = next_version(pubspec_version(args.pubspec), released, args.bump)
    outputs = {
        "version": version.name,
        "build_number": str(version.build),
        "tag": f"v{version}",
        "previous_tag": previous_tag(released),
    }

    lines = "".join(f"{key}={value}\n" for key, value in outputs.items())
    print(lines, end="")
    if output_file := os.environ.get("GITHUB_OUTPUT"):
        with open(output_file, "a") as handle:
            handle.write(lines)


if __name__ == "__main__":
    main()
