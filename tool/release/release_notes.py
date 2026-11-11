#!/usr/bin/env python3
"""Writes the release notes for a release, in English and Norwegian.

Claude turns the commit messages since the previous release into short notes
for the people who use the app. If Claude Code is missing, not signed in, or
fails, the notes fall back to the commit subjects, so a release never waits on
its notes.

Claude runs through the Claude Code CLI so that it draws on a Claude
subscription, not API credits. CI signs it in with CLAUDE_CODE_OAUTH_TOKEN (from
`claude setup-token`); locally it uses whoever is signed in to `claude`.
ANTHROPIC_API_KEY is removed from its environment, because a set API key would
take precedence and bill credits instead.

Writes, under --out:
  play/whatsnew-en-US, play/whatsnew-no-NO  Google Play release notes (max 500 characters)
  testflight.txt                            TestFlight "What to Test" (max 4000 characters)
  github.md                                 the GitHub release body

Run from the repository root:
  release_notes.py --since v2.2.16+100 --version 2.2.17+101 --out release-notes
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

PLAY_LIMIT = 500
TESTFLIGHT_LIMIT = 4000
MAX_COMMITS = 200

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

You get the commit messages for one release. Write the notes the students read:

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
- Keep each version under 450 characters.\
"""

NOTES_SCHEMA = {
    "type": "object",
    "properties": {
        "en": {"type": "string", "description": "The notes in English"},
        "no": {"type": "string", "description": "The notes in Norwegian Bokmål"},
    },
    "required": ["en", "no"],
    "additionalProperties": False,
}


class Commit(NamedTuple):
    sha: str
    subject: str
    body: str


class NotesUnavailable(Exception):
    pass


def commits_since(since: str) -> list[Commit]:
    revisions = [f"{since}..HEAD"] if since else ["-n", "30", "HEAD"]
    log = subprocess.run(
        ["git", "log", "--no-merges", f"--max-count={MAX_COMMITS}",
         "--format=%h%x1f%s%x1f%b%x1e", *revisions],
        capture_output=True, text=True, check=True,
    ).stdout
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


def notes_from_claude(version: str, commits: list[Commit]) -> tuple[str, str]:
    if shutil.which("claude") is None:
        raise NotesUnavailable("Claude Code (the claude command) is not installed")

    changes = "\n\n".join(
        f"{commit.subject}\n{commit.body[:1500]}".strip() for commit in commits
    )
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
        "--json-schema", json.dumps(NOTES_SCHEMA),
    ]
    # An empty working directory, so no CLAUDE.md or project settings get read.
    with tempfile.TemporaryDirectory() as empty_directory:
        try:
            run = subprocess.run(
                command,
                input=f"Release {version}. Commit messages:\n\n{changes}",
                capture_output=True, text=True, timeout=300,
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
        notes = output.get("structured_output") or json.loads(output["result"])
        english, norwegian = notes["en"].strip(), notes["no"].strip()
    except (json.JSONDecodeError, KeyError, TypeError, AttributeError) as error:
        raise NotesUnavailable(f"the answer was not the expected JSON: {str(output)[:300]}") from error
    if not english or not norwegian:
        raise NotesUnavailable("the answer left a language empty")
    return english, norwegian


def fallback_notes(commits: list[Commit]) -> tuple[str, str]:
    subjects = [CONVENTIONAL_PREFIX.sub("", commit.subject) for commit in commits]
    english = "\n".join(f"• {subject[:1].upper()}{subject[1:]}" for subject in subjects)
    return english or FALLBACK_EN, FALLBACK_NO


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
    parser.add_argument("--since", default="", help="tag or commit the release starts after")
    parser.add_argument("--version", required=True, help="the release, e.g. 2.2.17+101")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    commits = commits_since(args.since)
    if not commits:
        english, norwegian = FALLBACK_EN, FALLBACK_NO
    else:
        try:
            english, norwegian = notes_from_claude(args.version, commits)
        except NotesUnavailable as reason:
            # A GitHub Actions annotation, so the run's summary shows it.
            print(f"::warning::Release notes are the commit list: {reason}", file=sys.stderr)
            english, norwegian = fallback_notes(commits)

    english, norwegian = fit(english, PLAY_LIMIT), fit(norwegian, PLAY_LIMIT)
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
        f"<details>\n<summary>Commits</summary>\n\n{commits_text}\n\n</details>\n"
    )
    print(f"English:\n{english}\n\nNorsk:\n{norwegian}")


if __name__ == "__main__":
    main()
