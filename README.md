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

Prompts that trigger it:

```
Train this on Rorqual, 1 H100 for 8 hours. Give me the job ID.
Is job 12345678 still running? Show me the tail of its log.
Pull run042 back into ./results/.
It OOM'd at step 900 — bump the memory and resubmit.
How many CPUs should I ask for per GPU on Narval?
Does any cluster I can reach have RT cores for OptiX?
```
