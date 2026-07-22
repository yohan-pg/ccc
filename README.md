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
Launch the learning-rate sweep on Rorqual overnight, one job per config.
Anything from last night finish? Summarize the final losses.
Job 12345678 has been pending 6 hours — is my request unreasonable?
The 4-GPU run died at step 900 with CUDA OOM. Diagnose and resubmit.
Bring back the checkpoints and metrics for run042 so I can plot them.
How many CPUs and how much memory per GPU should I ask for on Narval?
```
