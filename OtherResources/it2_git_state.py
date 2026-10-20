# Git state for a directory on a host reached through SSH Integration.
#
# iTerm2 runs this on the remote with the Python that runs the framer, as a background job, and
# reads one line from its output: MARKER followed by base64 of a JSON object. A pty sits between
# this process and iTerm2, so nothing but that line may matter: stray output, \r\n line endings
# and stderr are all tolerated.
#
# Locally the same information comes from libgit2 (pidinfo/iTermGitClient.m). That file is the
# specification: every field here means what it means there, and ModernTests'
# RemoteGitStateParityTests compares the two on real repositories.
#
# Argument: base64 of a JSON object {"path", "base", "stats", "timeout"}.
# Result: {"repo": false} when the path is in no repository (or HEAD is unborn), {"timeout": true}
# when the deadline passed, or the state.
#
# Python 3.7 or newer (the framer's minimum). No third-party modules. Works with git as old as
# 1.8: newer forms are tried first, and older ones used when git does not know them.

import base64
import json
import os
import subprocess
import sys
import time

MARKER = "it2-git-state:"


class Timeout(Exception):
    pass


class Git:
    def __init__(self, cwd, deadline):
        self.cwd = cwd
        self.deadline = deadline
        self.env = dict(os.environ)
        # Never take index.lock: this is a passive observer of a repository someone is using.
        self.env["GIT_OPTIONAL_LOCKS"] = "0"
        self.env["GIT_TERMINAL_PROMPT"] = "0"
        self.env["LC_ALL"] = "C"
        for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            self.env.pop(name, None)

    def __call__(self, *args):
        """stdout as bytes, or None if git failed or is missing."""
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise Timeout()
        command = ["git", "-c", "core.quotepath=false", "-c", "color.ui=false"] + list(args)
        try:
            proc = subprocess.run(command, cwd=self.cwd, env=self.env,
                                  stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, timeout=remaining)
        except subprocess.TimeoutExpired:
            raise Timeout()
        except OSError:
            return None
        if proc.returncode != 0:
            return None
        return proc.stdout


def existing_directory(path):
    # A directory the shell reported may be gone since; libgit2 walks up to its parent.
    path = os.path.abspath(path or "/")
    while not os.path.isdir(path):
        parent = os.path.dirname(path)
        if parent == path:
            break
        path = parent
    return path


def decode(b):
    """None for bytes that are not UTF-8: libgit2's path skips such files, and JSON cannot carry
    them."""
    try:
        return b.decode("utf-8")
    except UnicodeDecodeError:
        return None


def records(output):
    """NUL-terminated records of a -z listing."""
    parts = output.split(b"\0")
    if parts and parts[-1] == b"":
        parts.pop()
    return parts


# Index column of porcelain v2, as libgit2's status flags map it in iTermGitFileStatusForEntry.
# A copy has no flag of its own there and reads as a new file.
INDEX_KINDS = {"A": "added", "M": "modified", "D": "deleted", "R": "renamed",
               "T": "typechange", "C": "added"}
WORKDIR_KINDS = {"M": "modified", "D": "deleted", "T": "typechange", "A": "untracked"}


def parse_status(output):
    """Branch info, counts, and HEAD-relative per-file entries from `status --porcelain=v2 -z`."""
    info = {"oid": None, "head": None, "ab": None}
    entries = []
    untracked = 0
    deleted = 0
    count = 0
    parts = records(output)
    i = 0
    while i < len(parts):
        line = decode(parts[i])
        i += 1
        if line is None:
            # Still counts toward dirty, as libgit2's count pass sees every entry.
            count += 1
            continue
        if line.startswith("# "):
            fields = line[2:].split(" ")
            if fields[0] == "branch.oid":
                info["oid"] = fields[1]
            elif fields[0] == "branch.head":
                info["head"] = " ".join(fields[1:])
            elif fields[0] == "branch.ab" and len(fields) == 3:
                info["ab"] = (fields[1].lstrip("+"), fields[2].lstrip("-"))
            continue
        kind = line[:1]
        if kind == "?":
            count += 1
            untracked += 1
            continue
        original = None
        if kind == "1":
            fields = line.split(" ", 8)
            xy, score, path = fields[1], None, fields[8]
        elif kind == "2":
            fields = line.split(" ", 9)
            xy, score, path = fields[1], fields[8], fields[9]
            original = decode(parts[i]) if i < len(parts) else None
            i += 1
        elif kind == "u":
            fields = line.split(" ", 10)
            count += 1
            entries.append((fields[10], "none", "conflicted"))
            continue
        else:
            continue
        count += 1
        x, y = xy[0], xy[1]
        if y in ("A", "R"):
            # Added with intent to add (git add -N): libgit2 sees an empty file staged and the
            # content in the work tree. It finds no renames in the work tree, so one renamed
            # there is the original deleted plus the new path.
            if y == "R":
                deleted += 1
                if original is not None:
                    entries.append((original, "none", "deleted"))
            entries.append((path, "added", "modified"))
            continue
        if y == "D":
            deleted += 1
        index = INDEX_KINDS.get(x, "none")
        if x == "R" and score != "R100":
            # libgit2 adds the modified flag to a rename whose content changed, and modified wins.
            index = "modified"
        workdir = WORKDIR_KINDS.get(y, "none")
        if index != "none" or workdir != "none":
            entries.append((path, index, workdir))
    return info, entries, count, untracked, deleted


# Porcelain v1's XY for an unmerged path.
UNMERGED_XY = ("DD", "AU", "UD", "UA", "DU", "AA", "UU")


def parse_status_v1(output, oid):
    """parse_status for `status --porcelain -b -z`, from git before 2.11, which has no v2. `oid`
    is HEAD's, or None when HEAD is unborn. v1 gives no rename score, so a rename reads as renamed
    even if its content changed too."""
    info = {"oid": oid, "head": None, "ab": None}
    entries = []
    untracked = 0
    deleted = 0
    count = 0
    parts = records(output)
    i = 0
    while i < len(parts):
        raw = parts[i]
        line = decode(raw)
        i += 1
        if line is None:
            count += 1
            if raw[:1] in (b"R", b"C") or raw[1:2] in (b"R", b"C"):
                i += 1  # The original path.
            continue
        if line.startswith("## "):
            branch = line[3:]
            counts = None
            if branch.endswith("]") and " [" in branch:
                branch, counts = branch[:-1].rsplit(" [", 1)
            ab = None
            if "..." in branch:
                branch = branch.split("...", 1)[0]
                # An upstream whose branch is gone has no ahead/behind in v2.
                if counts != "gone":
                    ahead, behind = "0", "0"
                    for item in (counts or "").split(", "):
                        words = item.split(" ")
                        if len(words) == 2 and words[0] == "ahead":
                            ahead = words[1]
                        elif len(words) == 2 and words[0] == "behind":
                            behind = words[1]
                    ab = (ahead, behind)
            if branch == "HEAD (no branch)":
                info["head"] = "(detached)"
            else:
                info["head"] = branch
            info["ab"] = ab
            continue
        if len(line) < 4:
            continue
        xy, path = line[:2], line[3:]
        if xy == "??":
            count += 1
            untracked += 1
            continue
        if xy == "!!":
            continue
        original = None
        if xy[0] in ("R", "C") or xy[1] in ("R", "C"):
            # The original path. A work-tree rename (of an intent-to-add file) has R second.
            original = decode(parts[i]) if i < len(parts) else None
            i += 1
        count += 1
        if xy in UNMERGED_XY:
            entries.append((path, "none", "conflicted"))
            continue
        x = xy[0] if xy[0] != " " else "."
        y = xy[1] if xy[1] != " " else "."
        if y in ("A", "R"):
            # As in parse_status.
            if y == "R":
                deleted += 1
                if original is not None:
                    entries.append((original, "none", "deleted"))
            entries.append((path, "added", "modified"))
            continue
        if y == "D":
            deleted += 1
        index = INDEX_KINDS.get(x, "none")
        workdir = WORKDIR_KINDS.get(y, "none")
        if index != "none" or workdir != "none":
            entries.append((path, index, workdir))
    return info, entries, count, untracked, deleted


def parse_name_status(output):
    """(letter, path) for each change in `diff --name-status -z`, the new path for a rename."""
    result = []
    parts = records(output)
    i = 0
    while i < len(parts):
        status = decode(parts[i]) or ""
        i += 1
        if status[:1] in ("R", "C"):
            i += 1  # old path
        if i >= len(parts):
            break
        path = decode(parts[i])
        i += 1
        if path is not None:
            result.append((status[:1], path))
    return result


def parse_numstat(output):
    """path -> (inserted, deleted) from `diff --numstat -z --no-renames`. Binary counts as 0."""
    result = {}
    for record in records(output):
        fields = (decode(record) or "").split("\t", 2)
        if len(fields) != 3:
            continue
        inserted = int(fields[0]) if fields[0].isdigit() else 0
        removed = int(fields[1]) if fields[1].isdigit() else 0
        result[fields[2]] = (inserted, removed)
    return result


BASE_KINDS = {"A": "added", "D": "deleted", "M": "modified", "R": "renamed", "U": "conflicted"}


def repo_state(git_dir):
    # Same precedence as libgit2's git_repository_state.
    def exists(name):
        return os.path.exists(os.path.join(git_dir, name))
    if exists("rebase-merge"):
        return "rebase"
    if exists("rebase-apply/rebasing"):
        return "rebase"
    if exists("rebase-apply"):
        return "apply"
    if exists("MERGE_HEAD"):
        return "merge"
    if exists("REVERT_HEAD"):
        return "revert"
    if exists("CHERRY_PICK_HEAD"):
        return "cherrypick"
    if exists("BISECT_LOG"):
        return "bisect"
    return "none"


def find_git_dir(git):
    """The repository's git directory, absolute, or None outside a repository."""
    git_dir = git("rev-parse", "--absolute-git-dir")
    # Before git 2.13, rev-parse echoes an option it doesn't know and succeeds.
    if git_dir is not None and (decode(git_dir) or "").strip().startswith("/"):
        return decode(git_dir).strip()
    # Before git 2.13 there is only --git-dir, which may be relative to the working directory.
    git_dir = git("rev-parse", "--git-dir")
    if git_dir is None:
        return None
    return os.path.join(git.cwd, decode(git_dir).strip())


def read_status(git):
    """parse_status's result, or None if git can't say."""
    options = ("--branch", "-z", "--untracked-files=all", "--ignore-submodules=all")
    status = git("status", "--porcelain=v2", *options)
    if status is not None:
        return parse_status(status)
    # Before git 2.11 there is only porcelain v1.
    status = git("status", "--porcelain", *options)
    if status is None:
        return None
    oid = git("rev-parse", "--verify", "--quiet", "HEAD")
    return parse_status_v1(status, decode(oid).strip() if oid is not None else None)


def collect(request, deadline):
    git = Git(existing_directory(request.get("path")), deadline)
    git_dir = find_git_dir(git)
    if git_dir is None:
        return {"repo": False}

    status = read_status(git)
    if status is None:
        return {"repo": False}
    info, entries, count, untracked, deleted = status
    unmerged = set(path for path, _, workdir in entries if workdir == "conflicted")
    if info["oid"] in (None, "(initial)"):
        # Unborn HEAD: libgit2 has no head reference and reports no state.
        return {"repo": False}
    branch = info["oid"] if info["head"] in (None, "(detached)") else info["head"]
    ahead, behind = info["ab"] if info["ab"] else ("", "")

    result = {
        "branch": branch,
        "ahead": ahead,
        "behind": behind,
        "dirty": count > 0,
        "adds": untracked,
        "deletes": deleted,
        "repoState": repo_state(git_dir),
    }

    stats = bool(request.get("stats"))
    if stats:
        result["files"] = [list(e) for e in entries]
        changes = git("-c", "diff.relative=false", "diff", "--no-ext-diff", "--no-renames", "-z",
                      "--name-status", "HEAD", "--")
        lines = git("-c", "diff.relative=false", "diff", "--no-ext-diff", "--no-renames", "-z",
                    "--numstat", "HEAD", "--")
        if changes is not None and lines is not None:
            numstat = parse_numstat(lines)
            added = untracked
            modified = 0
            removed = 0
            inserted_lines = 0
            deleted_lines = 0
            for letter, path in parse_name_status(changes):
                if path in unmerged:
                    # libgit2 reports a conflict as its own kind, which these counts skip.
                    continue
                if letter == "A":
                    added += 1
                elif letter == "D":
                    removed += 1
                elif letter == "T":
                    # Without its typechange option libgit2 splits this into a deletion and an
                    # addition, neither of which counts lines.
                    added += 1
                    removed += 1
                elif letter == "M":
                    modified += 1
                    plus, minus = numstat.get(path, (0, 0))
                    inserted_lines += plus
                    deleted_lines += minus
            result["stats"] = {"filesAdded": added, "filesModified": modified,
                               "filesDeleted": removed, "linesInserted": inserted_lines,
                               "linesDeleted": deleted_lines}

    base = request.get("base") or ""
    if base and base != "HEAD":
        # Does the base name a tree? If not, keep the HEAD-relative list, as libgit2 does.
        if git("rev-parse", "--verify", "--quiet", base + "^{tree}") is not None:
            changes = git("-c", "diff.relative=false", "diff", "--no-ext-diff", "-M", "-z",
                          "--name-status", base + "^{tree}", "--")
            if changes is not None:
                files = []
                for letter, path in parse_name_status(changes):
                    if path in unmerged:
                        files.append([path, "none", "conflicted"])
                    elif letter == "T":
                        # libgit2 splits a typechange into a deletion and an addition here too.
                        files.append([path, "none", "deleted"])
                        files.append([path, "none", "added"])
                    elif letter in BASE_KINDS:
                        files.append([path, "none", BASE_KINDS[letter]])
                result["files"] = files
    return result


def main():
    try:
        request = json.loads(base64.b64decode(sys.argv[1]).decode("utf-8"))
        deadline = time.monotonic() + float(request.get("timeout") or 10)
        try:
            result = collect(request, deadline)
        except Timeout:
            result = {"timeout": True}
    except Exception as e:
        result = {"error": type(e).__name__ + ": " + str(e)}
    encoded = base64.b64encode(json.dumps(result).encode("utf-8")).decode("ascii")
    sys.stdout.write("\n" + MARKER + encoded + "\n")
    sys.stdout.flush()


# Run as a script, or by exec as iTerm2 runs it; tests import it.
if __name__ == "__main__":
    main()
