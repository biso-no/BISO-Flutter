#!/usr/bin/env python3
"""Writes a release's notes in English and Norwegian, and judges its size.

Claude reads the commit messages since the previous release and writes short
notes for the people who use the app. It also says whether the release is a
minor one (something new for students) or a patch (fixes, polish, internal
work); next_version.py bumps the version by that. Major versions are only ever
chosen by hand.

If Claude Code is missing, not signed in, or fails, the notes fall back to the
commit subjects and the size to a patch, so a release never waits on Claude.

Claude runs through the Claude Code CLI so that it draws on a Claude
subscription, not API credits. CI signs it in with CLAUDE_CODE_OAUTH_TOKEN (from
`claude setup-token`); locally it uses whoever is signed in to `claude`.
ANTHROPIC_API_KEY is removed from its environment, because a set API key would
take precedence and bill credits instead.

Writes, under --out:
  play/whatsnew-en-US, play/whatsnew-no-NO  Google Play release notes (max 500 characters)
  testflight.txt                            TestFlight "What to Test" (max 4000 characters)
  github.md                                 the GitHub release body
and `bump` (patch or minor) and `bump_reason` to $GITHUB_OUTPUT, or prints them.

Run from the repository root:
  python3 tool/release/release_notes.py --out release-notes
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple

from next_version import previous_tag, released_versions

PLAY_LIMIT = 500
TESTFLIGHT_LIMIT = 4000
MAX_COMMITS = 200
BUMPS = ("patch", "minor")

# Release bookkeeping, not changes anyone would notice.
SKIPPED_SUBJECTS = re.compile(r"^chore\((release|version)\)")
CONVENTIONAL_PREFIX = re.compile(r"^\w+(\([^)]*\))?!?:\s*")

FALLBACK_EN = "• Bug fixes and improvements."
FALLBACK_NO = "• Feilrettinger og forbedringer."

SYSTEM_PROMPT = """\
You write the release notes shown in Google Play and TestFlight for BISO, the \
app of the student organisation at BI Norwegian Business School. Students use \
it for events, the BISO shop, volunteer jobs, expense reimbursements, \
membership and the member pass, chat and notifications.

You get the commit messages for one release, and the size of its diff. Write \
the notes the students read:

- Mention only what a student would notice: new features, visible \
improvements, and fixes to things that were broken. Leave out refactoring, \
tests, CI, dependency updates and other internal work, and never name code, \
packages, files or services.
- Write at most four lines, most important first, each starting with "• " and \
one short sentence long. If nothing in the release is visible to students, \
write a single line saying the update contains fixes and improvements.
- Describe only what the commits support. Don't guess at features or \
exaggerate them.
- Write an English version and a Norwegian (Bokmål) version that say the same \
things. The Norwegian should read as if written in Norwegian, not translated.
- Keep each version under 450 characters.

Then judge the release's size, which sets its version number:

- "minor" when it gives students something new: a new screen, feature or \
capability, or a clearly different way of using an existing one.
- "patch" for everything else: fixes, small tweaks, copy and layout polish, \
performance, and internal work.
- Judge by what students get, not by the size of the diff: a large refactor is \
still a patch, and a small new feature is a minor. When in doubt, choose \
"patch".
- Give the reason in one short sentence.\
"""

SCHEMA = {
    "type": "object",
    "properties": {
        "en": {"type": "string", "description": "The notes in English"},
        "no": {"type": "string", "description": "The notes in Norwegian Bokmål"},
        "bump": {"type": "string", "enum": list(BUMPS), "description": "The release's size"},
        "bump_reason": {"type": "string", "description": "Why, in one short sentence"},
    },
    "required": ["en", "no", "bump", "bump_reason"],
    "additionalProperties": False,
}


class Commit(NamedTuple):
    sha: str
    subject: str
    body: str


class Release(NamedTuple):
    english: str
    norwegian: str
    bump: str
    bump_reason: str


class NotesUnavailable(Exception):
    pass


def git(*args: str) -> str:
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def commits_since(since: str) -> list[Commit]:
    revisions = [f"{since}..HEAD"] if since else ["-n", "30", "HEAD"]
    log = git("log", "--no-merges", f"--max-count={MAX_COMMITS}",
              "--format=%h%x1f%s%x1f%b%x1e", *revisions)
    commits = []
    for record in log.split("\x1e"):
        # Only newlines: str.strip() counts the \x1f separator as whitespace.
        record = record.strip("\n")
        if not record:
            continue
        sha, subject, body = record.split("\x1f", 2)
        if not SKIPPED_SUBJECTS.match(subject):
            commits.append(Commit(sha, subject.strip(), body.strip()))
    return commits


def diff_size(since: str) -> str:
    """For example "54 files changed, 3120 insertions(+), 410 deletions(-)"."""
    return git("diff", "--shortstat", f"{since}..HEAD").strip() if since else ""


def release_from_claude(commits: list[Commit], size: str) -> Release:
    if shutil.which("claude") is None:
        raise NotesUnavailable("Claude Code (the claude command) is not installed")

    changes = "\n\n".join(
        f"{commit.subject}\n{commit.body[:1500]}".strip() for commit in commits
    )
    prompt = f"Diff size: {size or 'unknown'}\n\nCommit messages:\n\n{changes}"
    environment = {key: value for key, value in os.environ.items() if key != "ANTHROPIC_API_KEY"}
    command = [
        "claude", "--print",
        "--model", "claude-opus-5-5",
        "--effort", "low",
        # Only this prompt: no coding-agent system prompt, tools or MCP servers.
        "--system-prompt", SYSTEM_PROMPT,
        "--tools", "",
        "--strict-mcp-config",
        "--no-session-persistence",
        "--output-format", "json",
        "--json-schema", json.dumps(SCHEMA),
    ]
    # An empty working directory, so no CLAUDE.md or project settings get read.
    with tempfile.TemporaryDirectory() as empty_directory:
        try:
            run = subprocess.run(
                command, input=prompt, capture_output=True, text=True, timeout=300,
                cwd=empty_directory, env=environment,
            )
        except subprocess.TimeoutExpired as error:
            raise NotesUnavailable("Claude Code did not answer within 5 minutes") from error

    try:
        output = json.loads(run.stdout)
    except json.JSONDecodeError as error:
        detail = (run.stderr or run.stdout).strip()[:300]
        raise NotesUnavailable(f"Claude Code exited with {run.returncode}: {detail}") from error
    if output.get("is_error") or run.returncode != 0:
        raise NotesUnavailable(f"Claude Code reported an error: {str(output.get('result'))[:300]}")

    try:
        answer = output.get("structured_output") or json.loads(output["result"])
        english, norwegian = answer["en"].strip(), answer["no"].strip()
        bump, reason = answer["bump"], " ".join(answer["bump_reason"].split())
    except (json.JSONDecodeError, KeyError, TypeError, AttributeError) as error:
        raise NotesUnavailable(f"the answer was not the expected JSON: {str(output)[:300]}") from error
    if not english or not norwegian:
        raise NotesUnavailable("the answer left a language empty")
    if bump not in BUMPS:
        bump, reason = "patch", f"Claude answered '{bump}', which is not a size, so this is a patch."
    return Release(english, norwegian, bump, reason)


def fallback_release(commits: list[Commit], reason: str) -> Release:
    subjects = [CONVENTIONAL_PREFIX.sub("", commit.subject) for commit in commits]
    english = "\n".join(f"• {subject[:1].upper()}{subject[1:]}" for subject in subjects)
    return Release(english or FALLBACK_EN, FALLBACK_NO, "patch", reason)


def fit(text: str, limit: int) -> str:
    """Drops whole lines from the end until the text fits the store's limit."""
    lines = text.splitlines()
    while lines and len("\n".join(lines)) > limit:
        lines.pop()
    return "\n".join(lines) if lines else text[: limit - 1] + "…"


def commit_list(commits: list[Commit]) -> str:
    return "\n".join(f"- {commit.subject} ({commit.sha})" for commit in commits)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--since", help="tag or commit the release starts after "
                        "(default: the previous release)")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    since = previous_tag(released_versions()) if args.since is None else args.since
    commits = commits_since(since)
    if not commits:
        release = fallback_release([], "Nothing changed since the previous release, so this is a patch.")
    else:
        try:
            release = release_from_claude(commits, diff_size(since))
        except NotesUnavailable as reason:
            # A GitHub Actions annotation, so the run's summary shows it.
            print(f"::warning::Release notes are the commit list: {reason}", file=sys.stderr)
            release = fallback_release(commits, "Claude was unavailable, so this is a patch.")

    english, norwegian = fit(release.english, PLAY_LIMIT), fit(release.norwegian, PLAY_LIMIT)
    commits_text = commit_list(commits) or "- (no changes)"

    play = args.out / "play"
    play.mkdir(parents=True, exist_ok=True)
    (play / "whatsnew-en-US").write_text(english + "\n")
    (play / "whatsnew-no-NO").write_text(norwegian + "\n")

    testflight = f"What's new\n{english}\n\nNytt i denne versjonen\n{norwegian}\n\nCommits\n{commits_text}"
    (args.out / "testflight.txt").write_text(fit(testflight, TESTFLIGHT_LIMIT) + "\n")

    (args.out / "github.md").write_text(
        f"## What's new\n\n{english}\n\n"
        f"## Nytt i denne versjonen\n\n{norwegian}\n\n"
        f"<details>\n<summary>Commits since {since or 'the start'}</summary>\n\n{commits_text}\n\n</details>\n"
    )

    print(f"English:\n{english}\n\nNorsk:\n{norwegian}\n")
    outputs = f"bump={release.bump}\nbump_reason={release.bump_reason}\n"
    print(outputs, end="")
    if output_file := os.environ.get("GITHUB_OUTPUT"):
        with open(output_file, "a") as handle:
            handle.write(outputs)


if __name__ == "__main__":
    main()
