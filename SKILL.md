---
name: ccc
description: Run experiments on Digital Research Alliance of Canada (Compute Canada) clusters — Rorqual by default, also Fir, Narval, Nibi, Trillium, tamIA. Use whenever asked to run training/experiments "on the cluster", "on Compute Canada", "on the Alliance", "on Narval/Rorqual/Fir/Nibi", or to rsync code/data to a cluster, submit or debug Slurm jobs, or pull results back. Covers automation-node login and its command whitelist, def- vs rrg- allocations, module+virtualenv setup, GPU/CPU/memory ratios, MIG, OptiX and which clusters have RT cores, $SLURM_TMPDIR, job monitoring and cancellation.
---

# Compute Canada / Alliance clusters

**Read `config.sh` first** — it holds the username, PI, account and paths, and is the only
user-specific file in this skill. Everything below uses those values; the worked examples show one
user's (`yohanpg` / `jlalonde`) for readability, so substitute if `config.sh` says otherwise.

Default cluster **Rorqual**. **The account depends on whether the job asks for a GPU** — the RAC
award here is GPU-only (verified 2026-07-22, LOG.md):

- **GPU jobs → `$CC_ACCOUNT_GPU` = `rrg-<PI>`.** The RAC award, and the better priority. Use it.
- **CPU-only jobs → `$CC_ACCOUNT_CPU` = `def-<PI>`.** `rrg-` has no CPU allocation and a GPU-less
  submit under it is **rejected outright**, so this is not a preference — it is the only thing that
  works.

The workflow is always **rsync in → sbatch → poll → rsync out**. You never compute on a login node
and you never hold an interactive session.

Companion files:

- `config.sh` — **read this first.** Username, PI surname, default account and derived paths.
  Sourced by the scripts; the one file to edit when someone new adopts this skill.

- `references/clusters.md` — allocations, storage quotas, GPU models, per-GPU core/mem ratios, MIG
  shapes, time limits, OptiX / RT cores, which clusters an agent can even reach.
- `SETUP.md` — the human-only SSH setup. Access is already working (§1); if `ssh cc ls` fails,
  first check you did not pass `BatchMode=yes`, then ask the user — do not work around it.
- `scripts/submit.sh`, `scripts/fetch.sh` — rsync+sbatch and rsync-back, with the wrapper constraints
  below already encoded. Prefer these over hand-rolling.
- `scripts/fetch_wiki.py` — read Alliance wiki pages. **The wiki is behind an Anubis proof-of-work
  gate: `WebFetch` and plain `curl` both get "Access Denied".** This script solves the challenge (it
  is trivial — difficulty 2) and returns raw wikitext, so you can check a number yourself instead of
  asking the user to paste it. `python3 scripts/fetch_wiki.py Rorqual Using_GPUs_with_Slurm`
- `LOG.md` — troubleshooting log. Append durable, non-obvious findings.

Switch off Rorqual only if its queue is unusable (down, or pending times far beyond the job's
runtime) — and say so, because data staged on one cluster is not visible from another.
**Killarney and Vulcan have no automation node: an agent cannot use them at all**, even though they
are the only hardware-RT clusters and `aip-jlalonde` covers them. They are human-only until that
changes.

## 1. Connecting — automation node only

Regular login nodes require **MFA**, which you cannot satisfy. `ssh cc` reaches
`robot.rorqual.alliancecan.ca` with a constrained key. Other clusters with an automation node have
aliases — `cc-fir`, `cc-narval`, `cc-nibi`, `cc-tamia`, `cc-trillium`, `cc-trillium-gpu` — all using
the same key; `cc`
is Rorqual. **Use `cc` unless you have a stated reason to switch, and say so when you do.** There is
no alias for Killarney or Vulcan; they have no automation node.

**Access is live — `ssh cc ls` works.** Verified 2026-07-23 on **Rorqual, Narval and Trillium**.
Enrollment had not yet propagated to **Fir, tamIA or Nibi** on that date; if you need one of those and
it still fails, that is the propagation lag, not your config — it is human-only to chase (`SETUP.md`
step 4), so stay on Rorqual rather than debugging it.

### Never pass `BatchMode=yes`

**This is the one flag that will make you wrongly conclude the cluster is unreachable.** Even on a
working host, authentication is two-stage:

```
Authenticated using "publickey" with partial success.
debug1: Authentications that can continue: keyboard-interactive
Authenticated to robot.rorqual.alliancecan.ca using "keyboard-interactive".
```

Publickey alone only ever yields *partial* success. The server then opens a `keyboard-interactive`
stage and — for an enrolled automation account — sends **zero prompts**, so it passes silently. That
empty challenge *is* the automation exemption; it is not a publickey-only login.

So `-o BatchMode=yes` and `-o NumberOfPasswordPrompts=0` both disable that second stage and turn a
perfectly working host into `Permission denied`. The reflex to add them to a scripted ssh is exactly
wrong here. Nothing ever actually blocks on input, so the defaults are safe:

```bash
timeout 30 ssh cc ls </dev/null            # correct: redirect stdin, bound with timeout
ssh -o BatchMode=yes cc ls                 # WRONG — fails on a host that works
```

If you are testing reachability across clusters, use the first form or you will get six false
negatives in a row.

**Constraints you must design around** — they are enforced by the key, not by politeness:

- **No PTY** (`restrict`). `ssh -t`, `salloc`, `srun --pty`, `htop`, `tmux` do not work. Everything
  is non-interactive and batch.
- **No shell operators.** The wrapper runs `$SSH_ORIGINAL_COMMAND` unquoted, *not* via `eval`, so
  pipes, `&&`, `;`, redirects and command substitution arrive as literal arguments and fail.
  **One command, one `ssh`.**
- **No remote variable expansion**, for the same reason — `$USER`, `$HOME` arrive literal. Write
  `yohanpg` out.
- **No inner quoting.** Same reason again: the wrapper word-splits, so a quoted multi-word argument
  is *not* reassembled — it arrives as separate tokens with the quote characters still attached, and
  the command rejects the fragment. `squeue -o '%T %r'` fails with `Unrecognized option: %r'`. Any
  argument that needs to survive must be a single space-free token: `squeue -o %T,%r`.
- **No `~` expansion.** Always absolute paths: `/home/yohanpg/…`, never `cc:~/…`.
- **`from="a.b.c.*"`** — the key only works from the registered public IP. If auth suddenly fails,
  check `curl ifconfig.me` against the registered mask and try `ssh -4` (an IPv6 route will not match
  an IPv4 mask).
- **`command=` whitelist.** The stock `allowed_commands.sh` permits exactly:

  | Group | Commands |
  |---|---|
  | always | `ls` `cat` `cd` `echo` `uname` `id` `groups` |
  | file | `mv` `cp` `rm` `mkdir` |
  | python | `python` `python3` `python3.N` `python2` |
  | git / archive | `git` · `tar` `dar` `gzip` `zip` `bzip2` |
  | transfer | `rsync` `scp` `sftp-server` |
  | slurm | `squeue` `scancel` `sbatch` `scontrol` `sq` |

  Everything else is **rejected**, including `srun`, `salloc`, `seff`, `sacct`, `sacctmgr`, `sinfo`,
  `partition-stats`, `diskusage_report`, `module`, `virtualenv`, `nvidia-smi`, `tail`, `head`,
  `grep`, `find`, `awk`, `wc`. Use `cat` where you would reach for `tail`/`grep` and filter locally.
  Narrower wrappers (`transfer_commands.sh`, `slurm_commands.sh`, …) allow only their own group plus
  the "always" group.
- **A rejected command exits 0.** The wrapper prints `Command rejected by allowed_commands.sh: …`
  to *stdout* and returns success, so a rejection is indistinguishable from a working command unless
  you read the output. `JID=$(ssh cc "sbatch …")` on a rejection silently sets `JID` to the rejection
  sentence, which then flows into `squeue -j`, log filenames and `scancel`. **Never trust `$?` on an
  ssh call — grep its stdout for `Command rejected`.** `scripts/submit.sh` already does.
- Automation nodes are **not** for long-running processes. Never start training there.

```bash
ssh cc "squeue -u yohanpg"                                    # works
ssh cc "cat /home/yohanpg/links/scratch/myproj/run042/train.log"    # works
ssh cc "cd /some/dir && sbatch job.sh"                        # FAILS — && is literal
ssh cc 'squeue -u $USER'                                      # FAILS — $USER is literal
ssh cc "seff 12345"                                           # FAILS *with exit 0* — read stdout
```

**`python3` is whitelisted — use it instead of dragging whole files home.** A `.py` file rsync'd to
the cluster can be run on the automation node, which is far better than `cat`-ing a 200 MB log across
the wire to grep it locally:

```bash
rsync -azh --no-g --no-p scan_log.py cc:/home/yohanpg/scan_log.py
ssh cc "python3 /home/yohanpg/scan_log.py /home/yohanpg/links/scratch/myproj/run042/myproj-123456.out"
```

`python3 -c "…"` does **not** work — the wrapper word-splits, so `-c` receives only the first token.
Pass a file. Keep these to seconds of CPU (§9); they are a filter, not a workload.

The whitelist is a knob, not a law: `command=` can point at any script. If the workflow genuinely
needs `sacct`/`seff`/`srun`, propose widening it (`SETUP.md`) rather than accumulating hacks.

## 2. Where files go

| Space | Path | Backed up | Use for |
|---|---|---|---|
| home | `/home/yohanpg` | yes | code, job scripts, `requirements.txt` |
| project | `/home/yohanpg/links/projects/rrg-jlalonde/yohanpg` | yes | datasets, final results. Keep it *static* |
| scratch | `/home/yohanpg/links/scratch` | **no — purged after 60 days** | job outputs, checkpoints |
| node-local | `$SLURM_TMPDIR` | wiped at job end | staged data + venv during the job |

Quotas, per-cluster `$SLURM_TMPDIR` sizes, and the other RAPs' project directories:
`references/clusters.md`.

**Each RAP has its own project directory with its own quota** — `links/projects/rrg-jlalonde/` and
`links/projects/def-jlalonde/` are different filesystems, not aliases. Default to the **`rrg-`** tree,
matching the `rrg-` account GPU jobs run under: it is the RAC award's storage, and it is the
larger quota. Both are readable from any
job, so a job running under `rrg-` may still read something already staged under `def-` — just do not
scatter new data across both.

- **Stage datasets and the venv into `$SLURM_TMPDIR` at the start of every job.** Shared Lustre is
  bad at many-small-file I/O; a Python venv on `/home` alone can dominate startup time.
- `$SLURM_TMPDIR` is **375 GB by default on Rorqual, and that is not a ceiling** — `#SBATCH --tmp=xG`
  raises it to anything from 370 to 3360 GB (the GPU nodes carry a 3.84 TB NVMe). Ask for it when a
  dataset does not fit rather than falling back to reading off Lustre. Note the default is also not
  *guaranteed*: below a whole node, co-tenant jobs share that disk.
- Write checkpoints **straight to scratch**, not to `$SLURM_TMPDIR` — if the job hits its time limit
  the tail of the script never runs and anything node-local is lost.
- Never create a venv under scratch (partial purge), never leave results only there.
- Move many small files as a **tarball**. Both quotas and rsync care.
- Check quota with `diskusage_report` from inside a job — it is blocked on the automation node.

### rsync patterns

```bash
# Code up (small, frequent) — or just use scripts/submit.sh
rsync -azh --no-g --no-p --delete \
  --exclude '.git' --exclude '__pycache__' --exclude 'output/' \
  ./ cc:/home/yohanpg/links/projects/rrg-jlalonde/yohanpg/myproj/

# Dataset up (large, once). --partial so an interruption resumes.
rsync -azh --no-g --no-p --partial --info=progress2 \
  data.tar cc:/home/yohanpg/links/projects/rrg-jlalonde/yohanpg/data/

# Results back
rsync -azh --no-g --no-p --info=progress2 \
  cc:/home/yohanpg/links/scratch/myproj/run042/ ./results/run042/
```

`--no-g --no-p` is **required** when writing into `/project`: quotas are enforced by group ownership
and preserving it causes a bogus "Disk quota exceeded". `-a` implies `-p -g`, hence the overrides.

## 3. Environment: modules + virtualenv (never conda, never uv)

The cluster ships optimized wheels; conda/uv environments fight the module system and the MPI/CUDA
libraries. Use `module load` + `virtualenv`.

Build `requirements.txt` **once**. `module` and `virtualenv` are blocked on the automation node, so
run this as a short CPU-only `sbatch` job, or ask the user to run it on a real login node:

```bash
module load StdEnv/2023 python/3.11
ENVDIR=/tmp/$RANDOM
virtualenv --no-download $ENVDIR && source $ENVDIR/bin/activate
pip install --no-index --upgrade pip
pip install --no-index torch torchvision numpy   # --no-index = local wheelhouse only
pip freeze --local > requirements.txt            # entries look like 2.4.0+computecanada
deactivate && rm -rf $ENVDIR
```

Then **recreate the venv inside each job** on node-local disk — faster than reusing a shared-FS venv
and immune to filesystem hiccups.

`--no-index` is not optional: it forces the Alliance wheelhouse, built against the cluster's
CUDA/MKL. Dropping it lets pip pull a PyPI build that may silently not see the GPU. If a package is
genuinely absent from the wheelhouse, pre-download it locally and ship the `.whl`.

### Compute nodes have no internet

By site policy **Rorqual's compute nodes cannot reach the internet at all** — same on tamIA; Vulcan
allows only a Squid proxy with a domain whitelist. Login and automation nodes *do* have internet;
compute nodes do not. This is not a firewall you can negotiate with mid-job: a connection attempt
hangs until it times out and then fails, after you have already paid the queue wait.

So **anything the run needs over the network must be in place before `sbatch`**, and the only two
places to fetch it are your local machine (then rsync) or the automation node itself, where `git` and
`python3 -m pip download` are both whitelisted:

```bash
ssh cc "git clone --depth 1 https://github.com/foo/bar /home/yohanpg/links/scratch/src/bar"
ssh cc "python3 -m pip download some-pkg -d /home/yohanpg/links/scratch/wheels"
```

The usual casualties, all of which look like a hang rather than an error:

- `pip install` without `--no-index` — the real reason that flag is mandatory above
- weight downloads: `torch.hub`, `timm`/`transformers` pretrained, `load_state_dict_from_url`
- dataset auto-download paths in a dataloader
- `wandb` online mode, and any telemetry/version-check phone-home
- `git clone` / `git submodule update` from inside the job script

Pre-stage the caches and pin everything offline in the job script:

```bash
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 WANDB_MODE=offline
export TORCH_HOME=/home/yohanpg/links/projects/rrg-jlalonde/yohanpg/caches/torch
```

`WANDB_MODE=offline` writes a local run directory; `wandb sync` it afterwards from a machine that has
internet. If a job genuinely needs an exception, that is a support ticket, not a workaround.

`module spider <name>`, `avail_wheels torch`, `diskusage_report`, `sinfo -o "%G"` all run *inside a
job only*. Wrap them in a 2-minute CPU-only `sbatch` probe and `cat` the output — doing that once at
the start of a campaign is cheap and answers most environment questions in one go.

## 4. Job scripts

```bash
#!/bin/bash
#SBATCH --account=rrg-jlalonde      # RAC award: GPU jobs only. CPU-only jobs must use def- (§4)
#SBATCH --job-name=myproj_run042
#SBATCH --gpus-per-node=h100:1      # always name the model; bare "=1" may be rejected
#SBATCH --cpus-per-task=16          # the full Rorqual per-GPU ratio: free, feeds the dataloader (§5)
#SBATCH --mem=124G
#SBATCH --time=0-03:00              # DD-HH:MM. Shorter = starts sooner.
#SBATCH --output=/home/yohanpg/links/scratch/myproj/logs/%x-%j.out   # absolute — see below
set -euo pipefail

echo "host=$(hostname) jobid=$SLURM_JOB_ID tmpdir=$SLURM_TMPDIR"
module load StdEnv/2023 python/3.11 cuda/12.2

# venv on node-local disk
virtualenv --no-download $SLURM_TMPDIR/env
source $SLURM_TMPDIR/env/bin/activate
pip install --no-index --upgrade pip
pip install --no-index -r /home/yohanpg/links/projects/rrg-jlalonde/yohanpg/myproj/requirements.txt

# data on node-local disk
mkdir -p $SLURM_TMPDIR/data
tar -xf /home/yohanpg/links/projects/rrg-jlalonde/yohanpg/data/data.tar -C $SLURM_TMPDIR/data

OUT=/home/yohanpg/links/scratch/myproj/run042
mkdir -p $OUT

# GPU utilisation trace — the only usage record obtainable without sacct/seff (§5)
nvidia-smi --query-gpu=timestamp,name,utilization.gpu,utilization.memory,memory.used,power.draw \
  --format=csv -l 30 > $OUT/gpu_usage.csv &
SMI_PID=$!
trap 'kill $SMI_PID 2>/dev/null' EXIT

python -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"

# --out points at scratch so checkpoints survive a time-limit kill
python train.py \
  --data $SLURM_TMPDIR/data \
  --out $OUT \
  --workers $SLURM_CPUS_PER_TASK

# anything staged node-local must be copied out before the job ends
if [ -d $SLURM_TMPDIR/renders ]; then cp -r $SLURM_TMPDIR/renders $OUT/; fi
```

**Make `--output` an absolute path under scratch.** A relative `%x-%j.out` is resolved against
sbatch's working directory, and since you cannot `cd` through the wrapper (§1) that is whatever
`--chdir` says — or your home directory if you forget it. Logs then land somewhere you are not
looking, and you conclude the job produced nothing. An absolute scratch path is immune to that, and
keeps churn off the backed-up 500K-file project quota. **Slurm will not create the directory**: if it
is missing the job fails at launch with no log at all, so `mkdir -p` it in the same breath as
submitting (`scripts/submit.sh` does).

Submit — one command, one ssh, absolute paths, `--chdir` instead of `cd &&`:

```bash
bash .claude/skills/ccc/scripts/submit.sh ./myproj job.sh     # preferred; prints the JID
# equivalently, by hand — note the separate mkdir, since one ssh cannot do both:
ssh cc "mkdir -p /home/yohanpg/links/scratch/myproj/logs"
JID=$(ssh cc "sbatch --parsable --chdir=/home/yohanpg/links/projects/rrg-jlalonde/yohanpg/myproj /home/yohanpg/links/projects/rrg-jlalonde/yohanpg/myproj/job.sh")
```

Time limits and job-count caps: `references/clusters.md`. Short version — ask for the shortest
`--time` that plausibly fits (partitions are nested at 3 h / 12 h / 24 h / 72 h / 7 d, so a ≤3 h job
can run on every node), and use `--array=1-100%10` to cap concurrency.

### CPU-only jobs

Anything without a GPU — data prep, COLMAP, resizing, metric aggregation, archiving, environment
probes — belongs in a CPU-only job on the `_cpu` side of the allocation. Do not attach a GPU to a job
that will not use one; it bills a whole GPU bundle and queues far longer.

```bash
#SBATCH --account=def-jlalonde     # MUST be def- here: rrg- has no CPU allocation, submit is refused
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=0-02:00
```

Billing differs from GPU jobs: with no GPU in the request the charge is `max(cores/1, mem_GB/4)`
core-equivalents — 4 GB per core is the reference bundle, and core-equivalents are a separate pool
from the RGU used for GPU work (§5). So here **trimming cores and memory genuinely saves
allocation**, unlike the GPU case: a 2-core 32 GB job is billed as 8 core-equivalents. Right-size
both.

Slurm appends the `_cpu` suffix itself: a GPU-less job under `--account=def-jlalonde` reports
`def-jlalonde_cpu`. That is expected, not a misrouted job.

**This is the one place the account differs from the GPU default**, and forgetting it produces the
`You cannot use this account` wall of text — whose list of "valid accounts" is filtered to the
resource type you asked for, so it comes back empty under `RAC accounts:` and reads as though the
RAC award does not exist. It does; it is just GPU-only. Switch to `def-` for the CPU job rather than
concluding anything about the allocation.

## 5. GPU sizing — you are billed for the max, not the sum

The Alliance charges GPU work in **Reference GPU Units (RGU)**, not in GPUs. On Rorqual one H100-80GB
is **12.2 RGU**, and the bundle rates are 1.31 cores and 10.2 GB per RGU — which is where the
"16 cores, 124 GB per H100" figure comes from (12.2 × 1.31, 12.2 × 10.2).

```
RGU charged = max( nGPUs × RGU_per_GPU , cores / cores_per_RGU , mem_GB / mem_per_RGU )
```

It is easier to reason in whole-H100 equivalents — divide through by 12.2. On Rorqual the free bundle
per H100 is then 16 cores : 124 GB (other clusters: `references/clusters.md`):

| Request | max(GPU, core, mem) | Charged |
|---|---|---|
| 1 GPU, 4 cores, 32 GB | max(1, 0.25, 0.26) | **1.0** H100-equivalent = 12.2 RGU |
| 1 GPU, **16 cores**, 124 GB | max(1, 1.0, 1.0) | **1.0** ← same price, 4× the workers |
| 1 GPU, 32 cores, 124 GB | max(1, **2.0**, 1.0) | **2.0** ← double, for cores you may not need |

Keep your own budget tally in GPU-hours (H100-equivalents) — it is the unit the prompt gives you. But
**CCDB, `sshare` and <https://portal.alliancecan.ca/slurm> all report RGU**, so those numbers run
~12.2× larger on Rorqual. That factor is a unit change, not a bug and not overspend.

**On a GPU job, cores and memory up to the bundle ratio are free.** Asking for 4 cores instead of 16
saves nothing at all — it just starves the dataloader, which is the most common cause of an idle GPU
here. Take the full ratio and derive workers from `$SLURM_CPUS_PER_TASK` rather than hardcoding, so
the script stays correct on clusters with different ratios. Going *over* the ratio is the only thing
that costs, and it costs steeply.

Where "request less" genuinely applies:

- **CPU-only jobs** — cores/memory *are* the binding term there (§4).
- **Memory beyond what you use**, even under the ratio: a large `--mem` restricts you to nodes that
  can satisfy it, so a leaner request is eligible for more nodes and backfills sooner. Size it from
  an earlier run's observed `MaxRSS`, plus headroom.
- **Multi-GPU jobs you can't saturate** — one well-fed GPU beats two half-idle, at half the cost.
- **MIG instead of a full GPU** when the work fits — that is the real lever on GPU-hours, not shaving
  cores. If a job uses less than half an H100/A100's compute *and* less than half its memory, request
  a MIG instance: it bills far less and starts much sooner. Shapes and limits in
  `references/clusters.md`.

### Confirm the GPU is actually being used

An idle GPU burning allocation is the single most common failure, and `srun`, `seff`, `sacct` and
`nvidia-smi` are all blocked from the automation node — so **build the measurement into the job
itself** (the `nvidia-smi … -l 30` block in §4). It needs no extra permissions and gives a better
record anyway. Note `seff` is useless from *inside* the job: accounting is not finalized until the
job exits, so it reports nothing usable. Read the trace back over the allowed `cat` and analyse
locally:

```bash
ssh cc "cat /home/yohanpg/links/scratch/myproj/run042/gpu_usage.csv" > gpu_usage.csv
ssh cc "cat /home/yohanpg/links/scratch/myproj/logs/myproj_run042-$JID.out" > job.out
```

Sustained `utilization.gpu` <50 % or VRAM <50 % → move to a MIG instance or fix the input pipeline
(usually too few dataloader workers, or data left on Lustre instead of `$SLURM_TMPDIR`). Low GPU
*and* low CPU means I/O-starved; low GPU with pegged CPU means the dataloader is the bottleneck.
Longer-term per-job curves: <https://portal.alliancecan.ca/slurm>.

## 6. Monitoring, budget, and cancelling

```bash
ssh cc "squeue -u yohanpg"                                # or: sq
ssh cc "squeue -j $JID -h -o %T"                          # PENDING / RUNNING / ...
ssh cc "squeue -j $JID -h -o %T,%r"                       # state + reason for pending
ssh cc "scontrol show job -dd $JID"
ssh cc "cat /home/yohanpg/links/scratch/myproj/logs/myproj_run042-$JID.out"
```

**Poll at a human cadence — every few minutes at most, never in a tight loop.** Frequent `squeue`
degrades the scheduler for everyone. Prefer `#SBATCH --mail-type=ALL --mail-user=...`. Job stdout is
buffered, so a quiet `.out` file does not mean the job is stuck.

**Before debugging anything cluster-side, check <https://status.alliancecan.ca/>.** Outages,
maintenance windows and degraded filesystems show up there, and it will save you from chasing a "bug"
that is a scheduled downtime. Per-cluster pages exist, e.g.
<https://status.alliancecan.ca/system/Rorqual>.

### Cancelling

```bash
ssh cc "scancel $JID"                          # one job
ssh cc "scancel $JID_1 $JID_2"
ssh cc "scancel -u yohanpg -t PENDING"         # all queued jobs
ssh cc "scancel -u yohanpg --name=myproj_run042"
ssh cc "scancel -u yohanpg"                    # everything of yours — confirm with the user first
```

Cancel promptly and deliberately:

- Job failed on a bug → `scancel` any sibling/array jobs with the same defect **before** fixing.
- Job is running but the GPU sits near 0 % → cancel, don't let it burn the budget to the time limit.
- Job stuck `PENDING` with reason `QOSMaxJobsPerUserLimit` / `AssocMaxJobsLimit` → too many
  submitted; cancel the surplus. Reason `Priority` or `Resources` just means "wait".
- Never `scancel` a job you did not submit, and never `scancel -u` another user.

### Budget discipline

The prompt gives you a compute budget in GPU-hours. Treat it as hard.

1. Before submitting, compute `bundles × --time` and subtract from the remaining budget, where
   `bundles = max(nGPUs, cores/ratio, mem/ratio)` (§5). **Trimming cores below the ratio saves
   nothing** — spend them on dataloader workers instead.
2. **MIG costs more than its compute share suggests.** The instance names describe compute (1/8, 2/8,
   3/8 of an H100) but billing does not follow them:

   | Instance | Compute share | RGU | Cost vs. a full H100 |
   |---|---|---|---|
   | `h100_1g.10gb` | 1/8 | 1.74 | **≈ 1/7** (0.14) |
   | `h100_2g.20gb` | 2/8 | 3.48 | **≈ 2/7** (0.29) |
   | `h100_3g.40gb` | 3/8 | 6.1 | **exactly 1/2** (0.50) |

   So a `3g` buys 3/8 of the compute for half the price. It is still the right call for smoke jobs and
   genuinely small work — it also starts much sooner — but budget it at 0.5 GPU-h per hour, not 0.375,
   and do not reach for `3g` on anything that could saturate a full GPU.
3. Always debug with a **short, small** job first: `--time=0-00:20` on a MIG instance with a tiny
   subset. Only scale up once the pipeline is green end-to-end.
4. Keep a running tally in your notes and report it. Stop and ask before exceeding the budget.
5. `--time` overruns silently kill the job; overestimates delay the start and waste nothing *if* the
   job exits early — so overestimate modestly rather than truncating a run.

## 7. Things that go wrong

| Symptom | Cause |
|---|---|
| `Permission denied (publickey)` from automation node | wrong key, IP changed, or IPv6 vs the `from=` mask — try `ssh -4`; else `SETUP.md` |
| `Permission denied (keyboard-interactive,…)` after `Authenticated using "publickey" with partial success` | **first suspect your own ssh flags**: `BatchMode=yes` or `NumberOfPasswordPrompts=0` kill the silent keyboard-interactive stage and produce this exact error on a working host (§1). Retry as `ssh cc ls </dev/null` before concluding anything. If it fails without those flags, the node really is demanding MFA — the key is fine, but automation enrollment or the CCDB *authorized-keys* upload is not (`SETUP.md` steps 3–4, human-only) |
| Rorqual works but `cc-fir` / `cc-tamia` fails the same way | enrollment propagates per cluster and lagged on those two as of 2026-07-23; also a per-cluster access opt-in (`SETUP.md` step 0). Use Rorqual |
| `cc-nibi` closes the connection right after the publickey offer | distinct from the MFA case — Nibi was rejecting the session outright as of 2026-07-23. Human-only; use Rorqual |
| `PTY allocation request failed` | expected: `restrict` key. Don't use `-t`, `salloc`, `srun --pty` |
| Command "rejected" over ssh | not in the whitelist (§1), or you used `&&` / a pipe / a redirect |
| A `$JID` that is a sentence, `scancel`/`squeue` complaining about it | the sbatch was rejected and **exited 0** (§1) — check ssh stdout, not `$?` |
| `squeue -u $USER` returns nothing or errors | `$USER` is not expanded remotely — write `yohanpg` |
| Job fails instantly, `.out` never created | `--output` names a directory that does not exist — Slurm won't `mkdir` it (§4) |
| Job hangs then dies on a download / `wandb` / `from_pretrained` | compute nodes have no internet (§3) — pre-stage and set the offline env vars |
| ssh/rsync remote path not found | `~` does not expand under the wrapper — use `/home/yohanpg/…` |
| `You are associated with multiple ... allocations` | pass `--account=` explicitly, suffix included |
| `You cannot use this account to submit this job`, `RAC accounts:` empty | almost always a **CPU-only job submitted under `rrg-`** — the RAC award is GPU-only, and the account list in that error is filtered to the resource type requested, so it looks like the RAC does not exist. Use `def-jlalonde` for CPU work, keep `rrg-jlalonde` for GPU (§4) |
| Builds fine, then fails in `optixInit()` | OptiX host lib is in the driver; GPU nodes only. Run it in a job, not on a login/automation node |
| Ray tracing slower than the local RTX box | H100/A100 have no RT cores — software BVH traversal. Expected |
| `Disk quota exceeded` writing to /project | rsync preserved group — add `--no-g --no-p` |
| Job dies at ~the time limit with no output | staged results never copied out of `$SLURM_TMPDIR` |
| torch sees no GPU | venv built without `--no-index`, or `cuda` module not loaded |
| `OOM` / `oom-kill` in the .out | raise `--mem` toward the per-GPU ceiling, not past it |
| Data loading is the bottleneck | data left on Lustre; stage to `$SLURM_TMPDIR` and raise `--cpus-per-task` to the per-GPU ratio — free (§5) |
| Job charged ~2× what you expected | cores or memory exceeded the per-GPU bundle ratio (§5) |
| Files vanished from scratch | 60-day purge — scratch is not storage |

## 8. Debugging without an interactive session

There are no interactive nodes available to an agent without MFA — you are sbatch-only. Do not let
that turn into a queue full of jobs that die in 30 seconds. In order of effectiveness:

1. **Fail locally first.** Import errors, path bugs, arg-parsing, shape math — reproduce on the local
   box, or on CPU. Most job failures never needed a GPU to find.
2. **Smoke job before scale job. Always.** `--time=0-00:20`, a `1g.10gb` MIG, one batch, one epoch,
   `--output=smoke-%j.out`. It lands in the ≤3 h partition and typically starts within minutes, costs
   ~0.04 GPU-h, and catches the environment-level failures (missing wheel, no CUDA, OOM, bad path)
   that are exactly what a PTY would have caught.
3. **Make jobs self-diagnosing**, since you get one shot at the log. Start every script with
   `set -euo pipefail` and echo the state you would otherwise have poked at interactively:
   ```bash
   echo "host=$(hostname) jobid=$SLURM_JOB_ID tmpdir=$SLURM_TMPDIR"
   nvidia-smi
   python -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"
   python -c "import sys; print(sys.executable)"
   ls -la $SLURM_TMPDIR/data
   ```
4. **Batch your uncertainty.** If unsure between four configs, submit a 4-task array of smoke jobs
   rather than four sequential guess-and-check rounds. Latency is the scarce resource, not slots.
5. **Poor-man's REPL** (when you genuinely need to iterate on a live GPU): submit one job that polls
   a directory in scratch, executes any script it finds there, and writes output back.
   ```bash
   # inside the job
   mkdir -p $CMDQ/in $CMDQ/out
   while [ ! -f $CMDQ/stop ]; do
     for f in $CMDQ/in/*.sh; do
       [ -e "$f" ] || continue
       bash "$f" > $CMDQ/out/$(basename $f).out 2>&1; rm "$f"
     done
     sleep 5
   done
   ```
   You then `rsync` a script in and `cat` the result out — both allowed. This burns allocation while
   idling, so give it a short `--time` and a MIG instance, and only use it when steps 1–4 have failed
   to isolate something. It is a workaround, not the default.

If the workflow keeps hitting the wrapper's limits, the fix is to **widen the wrapper**, not to
accumulate hacks. Raise it with the user: `command=` can point at a custom script, and adding `seff`,
`sacct`, `sinfo`, `diskusage_report` and a read-only `srun --overlap` for monitoring is a small,
defensible change. That is a decision for the user (and possibly a support ticket), so propose it
rather than doing it.

## 9. Hard rules

- Never run training, data prep, or anything over ~10 CPU-minutes / 4 GB RAM on a login or automation
  node. Compile-scale work only; everything else goes through `sbatch`.
- Never use conda or uv on the cluster. `module load` + `virtualenv --no-download` + `pip --no-index`.
- Never touch another user's jobs.
- Never leave results only on scratch.
- Report back with: job IDs, the cluster, the **absolute path** to the run directory on the cluster,
  the local path results were synced to, and GPU-hours consumed vs. budget.

## 10. How to end a turn

**Always close with a one-line compute report**, even if the task used none:

```
Compute: 3 jobs on Rorqual, 4.2 GPU-h used, 15.8 of 20 GPU-h remaining.
Compute: none used.
```

**If jobs are still queued or running when you stop**, make that the final line of the message, on
its own line, verbatim:

```
Waiting on queue.
```

Only when something is genuinely still in flight — it is the at-a-glance signal that the user just
needs to wait rather than read. List the job IDs above it so they can check themselves.

## 11. Reading the documentation, and keeping these files current

### Where to look things up

**The wiki is readable — use `scripts/fetch_wiki.py`.** `docs.alliancecan.ca` is behind Anubis
proof-of-work protection, so `WebFetch` and plain `curl` both get an "Access Denied" page (HTTP 200
with a ~4 KB challenge body, so an unchecked fetch *looks* like success — grep for `not a bot`).
That gate exists to make mass scraping expensive, not to keep you out: the script pays the
proof-of-work, which is what a browser does silently, and returns raw wikitext.

```bash
python3 .claude/skills/ccc/scripts/fetch_wiki.py Rorqual Using_GPUs_with_Slurm
# -> Rorqual.wiki, Using_GPUs_with_Slurm.wiki  (MediaWiki source, tables intact)
```

Solve once per session and fetch only the pages you need — don't loop over the wiki. Useful pages:
`Running_jobs`, `Using_GPUs_with_Slurm`, `Multi-Instance_GPU`, `Storage_and_file_management`,
`Python`, `Allocations_and_compute_scheduling`, `Job_scheduling_policies`,
`Automation_in_the_context_of_multifactor_authentication`, and one per cluster (`Rorqual`, `Fir`,
`Nibi`, `Narval`, `Trillium`, `TamIA`, `Killarney`, `Vulcan`).

Sources in order of authority:

1. **A CPU-only probe job** — `sinfo -o "%G"`, `module spider`, `avail_wheels`, `diskusage_report`,
   `sshare`. Live values beat documentation, and a probe costs almost nothing (§ CPU-only jobs).
2. **The wiki**, via the script above — for policy and anything not observable from a login shell.
3. **`raw.githubusercontent.com`** — not gated. `ComputeCanada/software-stack-custom` holds the
   deployed wrapper at `bin/computecanada/allowed_commands/allowed_commands.sh`, the primary source
   for §1. (Re-verified 2026-07-22: §1's table is exact. The sftp case matches the full path
   `/usr/libexec/openssh/sftp-server*`, not a bare `sftp-server`.)
4. **<https://status.alliancecan.ca/>** for outages — returns 403 to `WebFetch`; ask the user to
   check it if a cluster is behaving strangely.

Only ask the user to paste something if all of the above fail.

### Keeping the files current

**Last verified: 2026-07-23.**

Clusters, quotas and ratios change. **If that date is a day or more old, re-check the numbers before
you rely on them**, and update the files in place — then bump the date above. Worth verifying:

- GPU models and Slurm specifiers per cluster, and whether any cluster was added or retired
- the per-GPU core/memory bundle ratios (§5) and the billing rule
- quotas, `$SLURM_TMPDIR` sizes, time limits, max queued jobs
- the automation wrapper's command whitelist (§1)
- module versions — `python`, `cuda`, `optix`
- which clusters have an automation node (Killarney and Vulcan gaining one would change the
  ray-tracing story materially)

Most of these live in `references/clusters.md`, not here.

**Only alert the user if a change is an actual problem** for the work in hand — a retired cluster, an
expired or moved allocation, a ratio change that invalidates job scripts you are about to submit, a
whitelist that no longer permits your workflow. Routine drift (a new module version, a reworded doc)
gets fixed silently in the files, not reported.

### When a command in this skill turns out to be wrong, fix it here

**These files are yours to edit — a wrong command is a bug to repair, not a finding to report.** If
something in this skill fails and you work out the correct form, the job is not done until the
correct form is *in this file*. Do it in the same turn, while you still have the evidence:

1. **Verify the replacement actually works** against the cluster before writing it down. Never
   substitute a guess for a command you just watched fail.
2. **Edit the offending line in place.** Do not leave the broken command sitting next to a warning
   about it — the next agent will copy the line, not the caveat.
3. **Fix the cause, not just the instance.** One bad command usually means a constraint is missing
   or under-stated somewhere earlier; add it there too, so the whole class of mistake is covered.
4. **`LOG.md` is for durable findings about the *cluster*** — an allocation that does not exist, a
   host that refuses connections, a policy that surprised you. A typo or a wrong flag in this skill
   does not belong there; it belongs in a corrected line. Logging it instead of fixing it leaves the
   trap in place.
5. **Mention it in one line at the end of the turn**, after it is fixed. Do not ask permission first
   — for a verified correction, just make it.

---

Docs: <https://docs.alliancecan.ca/wiki/Technical_documentation>
