# Claude for Compute Canada

A [Claude Code](https://claude.com/claude-code) skill for running experiments on
[Digital Research Alliance of Canada](https://docs.alliancecan.ca/wiki/Technical_documentation)
(Compute Canada) clusters: rsync in, `sbatch`, poll, rsync out — without an agent ever touching a
login node.

## Use it

Drop this directory into `~/.claude/skills/ccc` (or a project's `.claude/skills/ccc`), then:

1. Put your username and PI in [`config.sh`](config.sh).
2. Follow [`SETUP.md`](SETUP.md) — some steps are human-only and marked `(*)`: they need a browser,
   a passphrase, or an email to support.

Then just ask Claude to run something on the cluster.

## Examples

```
Launch a learning-rate sweep on Rorqual overnight, one job per config.
Launch a learning-rate sweep on Rorqual, batched into 4 hour jobs, fix any issues along the way.
Which clusters have GPUs free right now?
Did anything finish last night? Summarize the final losses.
The sweep has been pending all morning — am I asking for too much?
Bring the results back and plot validation loss against learning rate.
Break down the compute we burned last month by project and major subtask.
```
