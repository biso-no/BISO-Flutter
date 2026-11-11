#!/usr/bin/env python3
"""Works out the version a release ships as.

The inputs are pubspec.yaml's `version:` line and the release tags, which look
like `v2.2.17+101` (release.yml creates one per release).

- `--bump auto`, used on every push to main: if pubspec.yaml carries a build
  number that no tag has reached, someone bumped it by hand and that version
  ships as it is. Otherwise the part named by `--suggested` goes up: `patch`
  (2.2.16+100 becomes 2.2.17+101) or `minor` (2.3.0+101). release_notes.py
  has Claude suggest it from the commits.
- `--bump patch|minor|major`, from a manual run: that part goes up and the
  suggestion is ignored.

Either way the count starts from the newer of pubspec.yaml and the last tag,
and the build number goes up by one. With no release tags yet, pubspec.yaml's
version is taken as already released.

Writes `version`, `build_number`, `tag` and `decided_by` (pubspec, claude or
manual) to $GITHUB_OUTPUT, or prints them when run outside GitHub Actions.
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
    """`bump` is patch, minor or major, or "as-is" to ship a hand-bumped pubspec.yaml."""
    last = max(released, key=lambda version: version.build, default=None)
    if bump == "as-is":
        if last is not None and current[:3] < last[:3]:
            sys.exit(f"pubspec.yaml's {current} is older than the released {last}")
        return current

    base = last if last is not None and last.build > current.build else current
    major, minor, patch = base.major, base.minor, base.patch
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    return Version(major, minor, patch, base.build + 1)


def hand_bumped(current: Version, released: list[Version]) -> bool:
    """Whether pubspec.yaml carries a build number no release has reached."""
    return bool(released) and current.build > max(version.build for version in released)


def previous_tag(released: list[Version]) -> str:
    """Where the next release's notes start: the last release tag, else the newest tag."""
    if released:
        return f"v{max(released, key=lambda version: version.build)}"
    return git("describe", "--tags", "--abbrev=0", "HEAD")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bump", choices=["auto", "patch", "minor", "major"], default="auto")
    parser.add_argument("--suggested", choices=["patch", "minor"], default="patch",
                        help="the part to bump under --bump auto (from release_notes.py)")
    parser.add_argument("--pubspec", type=Path, default=Path("pubspec.yaml"))
    args = parser.parse_args()

    released = released_versions()
    current = pubspec_version(args.pubspec)
    if args.bump != "auto":
        bump, decided_by = args.bump, "manual"
    elif hand_bumped(current, released):
        bump, decided_by = "as-is", "pubspec"
    else:
        bump, decided_by = args.suggested, "claude"

    version = next_version(current, released, bump)
    outputs = {
        "version": version.name,
        "build_number": str(version.build),
        "tag": f"v{version}",
        "decided_by": decided_by,
    }

    lines = "".join(f"{key}={value}\n" for key, value in outputs.items())
    print(lines, end="")
    if output_file := os.environ.get("GITHUB_OUTPUT"):
        with open(output_file, "a") as handle:
            handle.write(lines)


if __name__ == "__main__":
    main()
