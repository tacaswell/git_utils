import json
from rich.table import Table
from rich.console import Console

with open('/tmp/pulls.json', 'r') as fin:
    pulls = json.load(fin)


tbl = Table("author", "title", "draft", "url")
for p in pulls:
    if p["author_association"] == "FIRST_TIME_CONTRIBUTOR":
        tbl.add_row(
            p['user']['login'],
            p['title'][:45],
            {True: 'X', False:''}[p['draft']],
            p['html_url']
            )


console = Console()
console.print(tbl)
