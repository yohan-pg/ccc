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

### Narval's automation node has no Slurm binaries in `PATH`
Narval / 2026-07-22. `ssh cc-narval ls` works, but every Slurm command dies inside the wrapper:

```
allowed_commands.sh: line 75: squeue: command not found
```

Same for `sbatch` and `scontrol`. This is *not* the whitelist — line 75 is the `$SSH_ORIGINAL_COMMAND`
call inside the wrapper's `squeue*|scancel*|sbatch*|scontrol*|sq*` branch, so the command was
*accepted* and then not found on `PATH` (a rejection prints `Command rejected by …` instead).

The binaries do exist — `ls /opt/software/slurm/bin` on the same node lists `sbatch`, `squeue`,
`sacct`… — but **calling one by absolute path is rejected**, because the wrapper matches on the
command as typed and `/opt/...` matches no branch:

```
Command rejected by allowed_commands.sh: /opt/software/slurm/bin/squeue --version
```

So there is no client-side workaround, and the wiki
(`Automation_in_the_context_of_multifactor_authentication`, fetched 2026-07-22) does not mention it —
it lists Narval's robot host with no caveat. Rorqual's robot node has the same binaries and no
`/usr/bin/squeue` either, yet resolves them, so this is a per-node `PATH` difference and looks like a
Narval-side misconfiguration worth a support ticket. Until then Narval is **transfer-only** for an
agent: rsync in, nothing else. Submit from Rorqual, or have the user submit on a Narval login node.

### Free GPUs are countable with `scontrol`, not `sinfo`
Rorqual / 2026-07-22. `sinfo` and `partition-stats` are blocked, but `scontrol -o show nodes` is
allowed and carries everything needed: `CfgTRES` has `gres/gpu:<model>=N`, `AllocTRES` has the
in-use count, and `State` flags `DOWN`/`DRAIN`. Free = Cfg − Alloc over non-drained nodes. The output
is ~780 lines (~1 MB) — fine to `cat` back and parse locally, and note there is **no `GresUsed`
field** on Slurm 25.11 here, so parse the TRES fields.

