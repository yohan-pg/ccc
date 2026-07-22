# Claude for Compute Canada

A [Claude Code](https://claude.com/claude-code) skill for running experiments on
[Digital Research Alliance of Canada](https://docs.alliancecan.ca/wiki/Technical_documentation)
(Compute Canada) clusters: rsync in, `sbatch`, poll, rsync out — without an agent ever touching a
login node.

## Use it

Drop this directory into `~/.claude/skills/ccan` (or a project's `.claude/skills/ccan`), then:

1. Put your username and PI in [`config.sh`](config.sh).
2. Follow [`SETUP.md`](SETUP.md) — some steps are human-only and marked `(*)`: they need a browser,
   a passphrase, or an email to support.

Then just ask Claude to run something on the cluster.
