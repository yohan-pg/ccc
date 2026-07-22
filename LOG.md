# Troubleshooting log

Append here whenever you hit and solve a real problem on the cluster, so the next agent doesn't
rediscover it. Newest last.

Only durable, non-obvious findings: something that cost a failed job or a wrong assumption, and whose
fix isn't already in `SKILL.md` or `references/clusters.md`. Not transient queue outages, not typos.
If a finding contradicts something written there, fix that file too rather than only logging it here.
Log what you actually ran and what it printed; if you are reasoning from documentation rather than
from the cluster, say so.

Format:

```
### <short symptom>
Cluster / date. What happened, the actual error text if short, and the fix that worked.
```

<!-- append entries below -->

### `/home/yohanpg/projects` and `/home/yohanpg/scratch` do not exist
Rorqual / 2026-07-23. Project, scratch and nearline hang off a `links/` subdirectory, not off `$HOME`
directly. `ls /home/yohanpg/links` → `nearlines  projects  scratch`; `ls .../links/projects` →
`def-jlalonde  rrg-jlalonde`. So: `/home/yohanpg/links/projects/<rap-name>/yohanpg`,
`/home/yohanpg/links/scratch`, `/home/yohanpg/links/nearlines/<rap-name>`. Verify the layout on any
*other* cluster before assuming it matches.

Each RAP has its **own project directory and quota**, so writing under `def-` while submitting with
`--account=rrg-jlalonde` is legal but splits your data across two quotas. Pick one deliberately —
`rrg-` is the default in `config.sh`.
