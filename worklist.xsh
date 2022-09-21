import os
from pathlib import Path
import gidgethub
from functools import wraps

import asyncio

import aiohttp
from gidgethub.aiohttp import GitHubAPI
import yaml

import json

with open(Path("~/.config/hub").expanduser(), "r") as f:
    oauth_token = f.read()

# TODO use envdirs
cache_path = Path("~/.cache/tacaswell/worklist.json").expanduser()

if cache_path.exists():
    with open(cache_path, 'r') as fin:
        cache = json.load(fin)
else:
    cache = {}

if "GITHUB_USERNAME" in os.environ:
    requester = os.getenv("GITHUB_USERNAME")
else:
    raise ValueError('"GITHUB_USERNAME" env var must be set to proceed.')

def ensure_gh_binder(func):
    """Ensure a function has a github API object

    Assumes the object comes in named 'gh'

    If *gh* is in the kwargs passed to the wrapped function, just pass
    though.

    If *gh* is not on kwargs, create one based on global values and
    pass it in.

    There is probably a better way to collect the values for the
    default api object.

    """

    @wraps(func)
    async def inner(*args, **kwargs):
        # if we get a gh API object, just use it
        if "gh" in kwargs:
            return await func(*args, **kwargs)

        # else, make one
        async with aiohttp.ClientSession() as session:
            gh = GitHubAPI(
                session,
                requester,
                oauth_token=oauth_token,
                cache=cache
            )
            return await func(*args, **kwargs, gh=gh)

    return inner


@ensure_gh_binder
async def get_pulls(org: str, repo: str, *, gh: GitHubAPI):
    data = []
    async for d in gh.getiter(
            f"/repos/{org}/{repo}/issues{{?state}}", {"state": "open"}
    ):
        data.append(d)
        if len(data) % 100 == 0:
            await asyncio.sleep(1)
    return data

pulls = asyncio.run(get_pulls("matplotlib", "matplotlib"))

with open(cache_path, 'w') as fout:
    json.dump(cache, fout)

with open('/tmp/pulls.json', 'w') as fout:
    json.dump(pulls, fout, indent='  ')
