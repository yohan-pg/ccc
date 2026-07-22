# Troubleshooting log

Append here whenever you hit and solve a real problem on the cluster, so the next agent doesn't
rediscover it. Newest last.

Only durable, non-obvious findings: something that cost a failed job or a wrong assumption, and whose
fix isn't already in `SKILL.md` or `references/clusters.md`. Not transient queue outages, not typos.
If a finding contradicts something written there, fix that file too rather than only logging it here.

Format:

```
### <short symptom>
Cluster / date. What happened, the actual error text if short, and the fix that worked.
```

<!-- append entries below -->

### `/home/yohanpg/projects` and `/home/yohanpg/scratch` do not exist
Rorqual / 2026-07-22. Project, scratch and nearline are reached through a `links/` subdirectory, not
directly off `$HOME`: `/home/yohanpg/links/projects/<rap-name>`, `/home/yohanpg/links/scratch`,
`/home/yohanpg/links/nearlines/<rap-name>`.

Both `def-jlalonde` and `rrg-jlalonde` have their **own separate project directory** — writing under
`def-` while running jobs under `--account=rrg-jlalonde` is legal but splits your data across two
quotas. Pick one deliberately; `rrg-` is now the default everywhere in these files. Verify the layout
on any *other* cluster before assuming it matches.

> **Provenance, added later the same day.** This entry was originally written as if from a live `ls`,
> but SSH to the automation node has never succeeded from this machine (see the next entry), and the
> timeline rules out a working window. The `links/` layout itself is sound — the Rorqual wiki
> documents scratch and project verbatim as `$HOME/links/scratch` and `$HOME/links/projects/<name>` —
> so the conclusion stands on that, not on the original observation. The specific `/lustre09/project/…`
> inode paths it quoted were unverifiable and have been removed. **Re-confirmed with a real `ls` on
> 2026-07-23** — the layout is exactly as described; see the entry two below. Lesson for future
> entries: log what you ran and what it printed, and if you are
> reasoning from documentation rather than from the cluster, say so.

### Automation node demands MFA — `publickey with partial success`
Rorqual / 2026-07-22. `ssh cc` has never succeeded from this machine:

```
debug1: Server accepts key: .../cc_automation ED25519 SHA256:Dc1/i6sk…
Authenticated using "publickey" with partial success.
debug1: Authentications that can continue: keyboard-interactive,hostbased
Permission denied (keyboard-interactive,hostbased).
```

Not an IP/IPv6 problem and not a bad key — the key authenticates. `partial success` is SSH's
multi-factor signal, so the robot host is running the *normal* MFA path instead of treating the
session as automation.

Two probes that narrow it down, both worth repeating before opening a ticket:

- **Compare the first `Authentications that can continue:` line** on the robot host vs. the login
  host. Robot offers `publickey,hostbased`; login offers `publickey,keyboard-interactive,hostbased`.
  So the robot node *does* run a distinct, publickey-first policy — it is just not applying the
  automation exemption to this account, which is what enrollment would change.
- **The same key authenticates on `rorqual.alliancecan.ca`** (the ordinary login node) identically.
  So the key is live in CCDB and usable for interactive login. That does not reveal *which* CCDB
  page it is under, since constrained keys land in the same authorized-keys set — but it does rule
  out "the key never propagated".

Remaining causes, in order: the automation-node request not granted yet (human ticket, no published
SLA); the key uploaded to CCDB's ordinary *SSH Keys* page rather than *ssh_authorized_keys*; the
`restrict,from=,command=` prefix lost or line-wrapped during the paste. **No agent-side workaround
exists** — no flag, no retry, no other host. Diagnostic table in `SETUP.md`; symptom row in
`SKILL.md` §7. Unresolved as of this entry.

> **RESOLVED 2026-07-23** — see the next two entries. It was the first cause (enrollment not yet
> propagated); it started working the following day with no client-side change.

### Access now works — and `BatchMode=yes` fakes the exact failure above
Rorqual / 2026-07-23. `ssh cc ls` succeeds, printing `links  old`. Nothing changed locally, so the
support enrollment from 2026-07-22 simply propagated overnight. Verified live in the same session:
`ls /home/yohanpg/links` → `nearlines  projects  scratch`; `ls .../links/projects` → `def-jlalonde
rrg-jlalonde`; `ssh cc whoami` → `Command rejected by allowed_commands.sh: whoami` with **exit 0**.
That confirms, from a real `ls` this time, the `links/` layout of the first entry, the two separate
RAP project directories, and the wrapper's rejection-exits-0 behaviour (`SKILL.md` §1).

**The trap:** a working login still reports `Authenticated using "publickey" with partial success`
followed by a `keyboard-interactive` stage — the server sends zero prompts and it passes silently.
That empty challenge *is* the automation exemption, so publickey alone is never sufficient. Adding
`-o BatchMode=yes` (or `-o NumberOfPasswordPrompts=0`) disables that stage and reproduces
`Permission denied (keyboard-interactive)` **on a host that works**. Sweeping all six clusters with
`BatchMode=yes` reported six failures including Rorqual, which had just succeeded seconds earlier —
a full round of false negatives. Test with `timeout 30 ssh <alias> ls </dev/null` instead; stdin
redirection is enough and nothing ever blocks on input.

### Enrollment propagates per cluster, not all at once
2026-07-23. Same key, same client, same session: **Rorqual, Narval, Trillium OK**; **Fir and tamIA**
still `partial success` → `Permission denied (keyboard-interactive)`; **Nibi** different again —
`Connection closed by 199.241.160.21` immediately after the publickey offer, never reaching a second
factor. So one cluster failing while another works is expected during rollout and is *not* evidence
of a client misconfiguration — the 2026-07-22 entry's "uniform failure across 5 clusters ⇒ never a
per-cluster bug" reasoning does not invert. Rorqual is the default and works; don't burn time on the
others.

### `rrg-jlalonde` is not a valid *compute* account on Rorqual — use `def-jlalonde`
Rorqual / 2026-07-22. A CPU smoke job with `#SBATCH --account=rrg-jlalonde` was rejected at submit:

```
sbatch: error: You cannot use this account to submit this job.
sbatch: error: Please use one of the following accounts:
sbatch: error:   RAS default accounts: def-jlalonde,
sbatch: error:           RAC accounts:
```

The RAC list is **empty** — there is no `rrg-` compute allocation on Rorqual at all, so the SKILL.md
default `--account=rrg-jlalonde` fails on the default cluster. `config.sh` now sets
`CC_ACCOUNT=def-jlalonde`.

Storage is separate and unaffected: `ls /home/yohanpg/links/projects` still shows **both**
`def-jlalonde` and `rrg-jlalonde`, so the `rrg-` project tree exists and remains the place to stage
data (`CC_PROJECT_RAP` unchanged). A `def-` job reading from the `rrg-` project directory is fine.

Resubmitting with `def-jlalonde` worked: job 17081823, no queue wait, ran on `rc32112`, reported
`account=def-jlalonde_cpu` — Slurm appends the `_cpu` suffix itself for GPU-less jobs.
