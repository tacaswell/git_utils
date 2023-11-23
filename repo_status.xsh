import time
from contextlib import contextmanager
from pathlib import Path
import argparse
from collections import defaultdict

from rich import box
from rich.align import Align
from rich.console import Console
from rich.live import Live
from rich.tree import Tree
from rich.text import Text

from xonsh.dirstack import with_pushd


OK_BRANCHES = {'main', 'master', 'develop'}


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
tree = Tree("Repos")


def format_branch(branch):
    if branch in OK_BRANCHES:
        color = 'green'
    else:
        color = 'red'
    return f'[{color}]{_trim_name(branch)}[/{color}]'

def _format_dir(count, prefix, postfix=' ', format_number=lambda x: x):
    if count == 0:
        color = 'green'
    else:
        color = 'red'
    count = format_number(count)
    return f'[{color}]{prefix}{count}{postfix}[/{color}]'

def format_aheadbehind(ahead, behind):
    return f'{_format_dir(ahead, "↑")} {_format_dir(behind, "↓")} '

def format_changes(*vals):
    return ' '.join(
            _format_dir(v, '', '', lambda x: {0: '-'}.get(x, x)) for v in vals
    )

def _trim_name(name, max_len=14):
    if len(name) < 15:
        return f'{name:<15}'
    return name[:max_len - 1] +'…'

if __name__ == '__main__':

    parser = argparse.ArgumentParser(description='Status of a tree of repos.')
    parser.add_argument(
        "--fetch",
        help="fetch all remotes",
        default=False,
        action=argparse.BooleanOptionalAction
    )
    parser.add_argument(
        "--skip-all-green",
        help="Maybe skip if no modified files.",
        default=False,
        action=argparse.BooleanOptionalAction
    )
    parser.add_argument("--depth", help="depth", type=int, default=1)
    args = parser.parse_args()

    targets = [Path(_).parent for _ in
               sorted($(find . -maxdepth @(args.depth + 1) -name .git -type d).split('\n'))
               if len(_)
               ]

    by_org = defaultdict(list)
    for t in targets:
        by_org[t.parent].append(t)

    with Live(tree, console=console, screen=False, refresh_per_second=4):
        for org, repos in by_org.items():
            node = tree
            for part in str(org).split('/'):
                try:
                    node, = (n for n in node.children if n.label == part)
                except ValueError:
                    node = node.add(part)
            for f in repos:
                with with_pushd(f):
                    if args.fetch:
                        !(git remote update).returncode
                    status = parse_status($(git status --branch --porcelain))
                    dirty_count = sum(
                        status[k]
                        for k in ['changed', 'deleted', 'conflicts', 'untracked']
                    )
                    if (args.skip_all_green and
                        dirty_count == 0 and
                        status['branch'] in OK_BRANCHES and
                        status['ahead'] + status['behind'] == 0
                    ):
                        continue

                    node.add('\t'.join(
                        [
                            _trim_name(f.name),
                            format_branch(status['branch']),
                            format_aheadbehind(status['ahead'], status['behind']),
                            format_changes(
                                status['changed'],
                                status['deleted'],
                                status['conflicts'],
                                status['untracked']
                            )
                        ]
                    )
                )
