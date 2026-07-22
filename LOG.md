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

### `rrg-jlalonde` is GPU-only — the "no RAC account" reading was wrong
Rorqual / 2026-07-22. A **CPU-only** smoke job with `#SBATCH --account=rrg-jlalonde` was rejected at
submit, listing an empty `RAC accounts:`. This was first written up here as "there is no `rrg-`
compute allocation at all" and the default was flipped to `def-` everywhere. **That conclusion was
wrong**, and the error message is what made it look right.

`sbatch --test-only` (free, submits nothing) isolates it — same script, only the GPU request differs:

```
--account=rrg-jlalonde --cpus-per-task=1 --mem=2G            -> rejected, "RAC accounts:" empty
--account=rrg-jlalonde --gpus-per-node=h100:1 --mem=124G     -> accepted, partition gpubase_bygpu_b1
--account=def-jlalonde --gpus-per-node=h100:1 --mem=124G     -> accepted (control)
```

The award is **GPU-only**. Slurm resolves a bare account to `_cpu` or `_gpu` by whether the job asks
for a GPU, so a CPU job under `rrg-` resolves to `rrg-jlalonde_cpu`, which does not exist. The
account list in the error is **filtered to the resource type requested**, which is why `RAC accounts:`
comes back empty and reads as "you have no RAC award" rather than "not for this resource type". The
full error does say `may not have a resource allocation of the type requested` — that line is the
one that matters, and it is easy to skim past in the wall of text.

So: `rrg-` for GPU jobs (better priority, it is the RAC award), `def-` for CPU-only. `config.sh` now
carries `CC_ACCOUNT_GPU` / `CC_ACCOUNT_CPU` instead of a single default.

**Method note:** the original diagnosis came from one failed submit and no control. `--test-only`
costs nothing and would have caught it immediately — vary one factor and test both directions before
concluding an allocation is dead.

Storage is separate and unaffected either way: both `def-jlalonde` and `rrg-jlalonde` project trees
exist, and `CC_PROJECT_RAP` stays on `rrg-`. Any job can read either.
