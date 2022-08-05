import time
from contextlib import contextmanager
from pathlib import Path
import argparse
from collections import defaultdict

from rich import box
from rich.align import Align
from rich.console import Console
from rich.live import Live
from rich.table import Table
from rich.text import Text

from xonsh.dirstack import with_pushd


parser = argparse.ArgumentParser(description='Status of a tree of repos.')
parser.add_argument("--fetch", help="fetch all remotes", default=False, action=argparse.BooleanOptionalAction)
parser.add_argument("--depth", help="depth", type=int, default=1)
args = parser.parse_args()


# vendored from xonsh.gitstatus
def parse_status(status):
    branch = ""
    ahead, behind = 0, 0
    untracked, changed, deleted, conflicts, staged = 0, 0, 0, 0, 0
    for line in status.splitlines():
        if line.startswith("##"):
            line = line[2:].strip()
            if "Initial commit on" in line:
                branch = line.split()[-1]
            elif "no branch" in line:
                branch = ""
            elif "..." not in line:
                branch = line
            else:
                branch, rest = line.split("...")
                if " " in rest:
                    divergence = rest.split(" ", 1)[-1]
                    divergence = divergence.strip("[]")
                    for div in divergence.split(", "):
                        if "ahead" in div:
                            ahead = int(div[len("ahead ") :].strip())
                        elif "behind" in div:
                            behind = int(div[len("behind ") :].strip())
        elif line.startswith("??"):
            untracked += 1
        else:
            if len(line) > 1:
                if line[1] == "M":
                    changed += 1
                elif line[1] == "D":
                    deleted += 1
            if len(line) > 0 and line[0] == "U":
                conflicts += 1
            elif len(line) > 0 and line[0] != " ":
                staged += 1
    return {
        "branch": branch,
        "ahead": ahead,
        "behind": behind,
        "untracked": untracked,
        "changed": changed,
        "deleted": deleted,
        "conflicts": conflicts,
        "staged": staged,
    }

console = Console()
table = Table(show_footer=False)
table_centered = Align.center(table)
table.add_column("org")
table.add_column("repo")
table.add_column("branch")
table.add_column("status")
table.add_column("dirty")
# console.clear()

def format_branch(branch):
    if branch in {'main', 'master', 'develop', 'gh-pages'}:
        color = 'green'
    else:
        color = 'red'
    return f'[{color}]{branch}[/{color}]'

def _format_dir(count, prefix):
    if count == 0:
        color = 'green'
    else:
        color = 'red'
    return f'[{color}]{prefix}{count} [/{color}]'

def format_aheadbehind(ahead, behind):
    return f'{_format_dir(ahead, "↑")} {_format_dir(behind, "↓")}'

targets = [Path(_).parent for _ in
           sorted($(find . -maxdepth @(args.depth + 1) -name .git -type d).split('\n'))
           if len(_)
           ]

by_org = defaultdict(list)
for t in targets:
    by_org[t.parent].append(t)

with Live(table_centered, console=console, screen=False, refresh_per_second=4):

    for org, repos in by_org.items():
        for f in repos:
            with with_pushd(f):
                if args.fetch:
                    !(git remote update).returncode
                status = parse_status($(git status --branch --porcelain))
                table.add_row(
                    str(f.parent),
                    str(f.name),
                    format_branch(status['branch']),
                    format_aheadbehind(status['ahead'], status['behind']),
                    '' if sum(status[k] for k in ['changed', 'deleted', 'conflicts']) == 0 else '+'
                )
        table.rows[-1].end_section = True
