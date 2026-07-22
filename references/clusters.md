# Per-cluster reference

Consult when picking a cluster, sizing a request, or debugging a resource/OptiX question.
Numbers are as documented by the Alliance wiki; re-verify with a probe job (§ *Probing*) if a value
looks wrong rather than trusting this file.

## Automation reachability

Login verified live 2026-07-23 with `timeout 30 ssh <alias> ls </dev/null` (never `BatchMode=yes`,
which fails on working hosts — SKILL.md §1).

| Cluster | Automation host | Agent-usable |
|---|---|---|
| **Rorqual** | `robot.rorqual.alliancecan.ca` | **yes — default, verified working** |
| Narval | `robot.narval.alliancecan.ca` | yes — verified working |
| Trillium (CPU) | `robot{1,2,3,4}.scinet.utoronto.ca` | yes — verified working; whole 192-core nodes only |
| Trillium (GPU) | `trig-robot1.scinet.utoronto.ca` | separate subcluster; not separately verified |
| Fir | `robot.fir.alliancecan.ca` | **not yet** — still MFA-denied 2026-07-23 (enrollment lag) |
| tamIA | `robot.tamia.ecpia.ca` | **not yet** — still MFA-denied 2026-07-23. Also **GPU jobs whole-node only**: 4×h100 or 8×h200 (below) |
| Nibi | `robot.nibi.alliancecan.ca` | **no** — closes the connection right after the publickey offer |
| **Killarney** | — | **no automation node — human-only** |
| **Vulcan** | — | **no automation node — human-only** |

The "not yet" rows are an enrollment/opt-in lag, not a config bug, and only a human can chase them
(`SETUP.md` steps 0 and 4). Re-test rather than assuming either way; Rorqual covers the default
workflow regardless.

Killarney and Vulcan are the only hardware-RT clusters and the `aip-jlalonde` grant covers them, but
**an agent cannot drive them at all** until they gain automation nodes. If a benchmark shows RT cores
would matter, say so and let the user run there manually; never silently switch.

## Allocations

A PI typically holds up to three kinds of RAP. Which ones exist, and which cluster the RAC award
sits on, are **per-user** — check CCDB rather than assuming. The rules below hold for anyone.

| Account | What it is | Priority |
|---|---|---|
| `def-<PI>` | Default RAP (Rapid Access Service) — every PI has one | low, best-effort, shared dynamically among all default accounts |
| **`rrg-<PI>`** | RAC competition award, valid on **one cluster only** | high, up to the awarded share |
| `aip-<PI>` | PAICE (AI environment) — Killarney / Vulcan / tamIA | separate pool |

Find yours in CCDB → *My Projects → My Resources and Allocations*; the string for `--account=` is the
*Group Name* column. `<PI>` is `CC_PI` in `config.sh`.

- `rrg-jlalonde` is valid **on Rorqual only**. A RAC account on any other cluster is rejected at
  submission, so "invalid account" usually means cluster/account mismatch, not a typo. Elsewhere use
  `def-jlalonde`.
- Heavy RAC use draws down a real annual grant and depresses its priority as usage accumulates;
  `def-` never depletes but starts far behind. Long/large runs → `rrg-`. Throwaway smoke tests → either.
- `aip-jlalonde` is effectively unusable by an agent: two of its three clusters have no automation
  node, and tamIA **schedules whole nodes only** (`--gpus=h100:4` or `--gpus=h200:8`, no MIG), so a
  1-GPU experiment costs 4 GPUs' worth of allocation there.
- Each PAICE cluster additionally needs a per-cluster access request in CCDB (*Intelligence
  artificielle* tab); holding the `aip-` RAP alone is not enough to log in.

### `_cpu` / `_gpu` suffixes

CPU and GPU use are tracked as separate allocations, so every account has two underlying Slurm
accounts: `def-jlalonde_cpu` / `def-jlalonde_gpu`, `rrg-jlalonde_cpu` / `_gpu`, etc.

- **Submitting:** pass the bare name (`--account=rrg-jlalonde`); Slurm routes to `_cpu` or `_gpu`
  based on whether the job requests a GPU. If you get `You are associated with multiple _cpu
  allocations…` (likely here — three RAPs), the message lists the exact accounts; pass one verbatim,
  suffix included.
- **Inspecting usage:** the suffix is mandatory. `sshare -l -A rrg-jlalonde_cpu` works,
  `sshare -l -A rrg-jlalonde` does not.

## Storage

| Space | Path (yohanpg) | Quota (default) | Backed up | Notes |
|---|---|---|---|---|
| home | `/home/yohanpg` | 50 GB, 500K files (fixed) | yes | code, job scripts, `requirements.txt` |
| project | `/home/yohanpg/links/projects/rrg-jlalonde/yohanpg` | 1 TB, 500K files per group | yes | datasets, final results. Keep it *static* |
| scratch | `/home/yohanpg/links/scratch` | 20 TB, 1M files | **no** | job outputs, checkpoints. **Purged after 60 days** |
| node-local | `$SLURM_TMPDIR` | Fir 7T · Nibi 3T · Narval 800G · Rorqual 375G (Trillium = RAMdisk) | n/a | fast local NVMe, deleted at job end |

Each RAP gets **its own project directory with its own quota** — `links/projects/rrg-jlalonde/` and
`links/projects/def-jlalonde/` are different symlinks into different `/lustre` project trees, not
aliases for one another. Default to the `rrg-` tree to match the default
`--account=rrg-jlalonde`. All of them are readable from any job regardless of which account it runs
under, so an existing dataset under `def-` is still usable — just don't scatter new data across both.

`$SLURM_TMPDIR` sizes above are defaults, not ceilings. On Rorqual `#SBATCH --tmp=xG` takes it from
370 up to 3360 GB (GPU nodes have a 3.84 TB NVMe). The default is also not guaranteed: a job smaller
than a whole node shares that disk with co-tenants.

## GPU model specifiers

`h100` (Fir, Nibi, Rorqual, Trillium, Killarney) · `a100` (Narval) · `l40s` (Killarney, Vulcan) ·
`mi300a` (Nibi) · `h200` (tamIA).

Always name the model — an unqualified `--gpus-per-node=1` may be rejected or land on an arbitrary
instance. To list what a cluster actually has, from inside a probe job:

```bash
sinfo -o "%G" | grep gpu | sed 's/gpu://g' | sed 's/),/\n/g' | cut -d: -f1 | sort | uniq
```

## Single GPU vs whole node

Two different shapes of request, and they land in **different partitions**. The scheduler splits each
cluster into *by-core* nodes (jobs taking part of a node) and *by-node* nodes (jobs taking all of it).
A single-GPU job is only eligible for the by-core subset; a whole-node job gets the by-node subset,
which is why the wiki says a job that "can efficiently use an entire node and its associated GPUs"
will "probably experience shorter wait times".

**Single GPU** — the default, and correct for almost all of our work:

```bash
#SBATCH --gpus-per-node=h100:1
#SBATCH --cpus-per-task=16          # ≤ the per-GPU ratio below
#SBATCH --mem=124G
```

**Whole node** — only when the run genuinely saturates every GPU on it:

```bash
#SBATCH --nodes=1
#SBATCH --gpus-per-node=h100:4      # every GPU on the node
#SBATCH --cpus-per-task=64          # every core
#SBATCH --mem=0                     # all available memory on the node
#SBATCH --exclusive
```

Choosing between them:

- **Cost is the whole node either way.** A whole-node job is billed for *all* its GPUs, so an
  idle GPU on a 4-GPU node is 4× the RGU burn for the same result. Shorter queueing does not make it
  cheaper — it makes it faster to start and more expensive to run.
- **Take a whole node only if the job scales across its GPUs** (multi-GPU training that actually keeps
  all of them busy), or if by-core queueing is genuinely blocking you and you have the budget.
- **Never take a whole node to run one single-GPU process.** Pack it instead: a job array of
  single-GPU jobs gets the same throughput at a quarter of the cost.
- **MIG is the opposite lever** — smaller than one GPU, cheaper still. Reach for that before you
  reach for whole nodes.

### tamIA is whole-node only

**tamIA does not accept single-GPU requests at all.** Site policy: *"Chaque tâche doit utiliser tous
les GPUs des serveurs alloués, soit 4 pour les h100 et 8 pour les h200."* Every job must use all GPUs
of the servers it is allocated — `--gpus=h100:4` or `--gpus=h200:8`, and no MIG.

The consequence is blunt: **the cheapest possible GPU job on tamIA costs 4 GPUs.** A one-GPU
experiment that costs 1 GPU-hour on Rorqual costs 4 GPU-hours there. Do not use tamIA for
single-GPU work — that is the reason to stay on Rorqual even though tamIA is at Université Laval and
reachable by an agent.

Trillium is the near-miss: its **GPU** subcluster schedules "by whole GPU (no MIG), or by whole node",
so single-GPU requests *are* allowed there; only its **CPU** subcluster is whole-node
(192-core) only. Note Trillium splits into two subclusters with separate login *and* automation
nodes — `robot{1,2,3,4}.scinet.utoronto.ca` for CPU, `trig-robot1.scinet.utoronto.ca` for GPU — so
`cc-trillium` reaches the CPU side; use `cc-trillium-gpu` for GPU work.

## Max cores and memory **per GPU**

Exceeding these makes the job unschedulable in practice and bills you for resources you strand.

| Cluster | GPU | RGU per GPU | Recommended per GPU |
|---|---|---|---|
| **Rorqual** | H100-80GB | 12.2 | **16 cores, 124 GB** |
| Fir | H100-80GB | 12.2 | 12 cores, 280 GB |
| Narval | A100-40GB | 4.0 | 12 cores, 124 GB |
| Nibi | H100-80GB | 12.2 | 14 cores, 250 GB |
| Trillium | H100-80GB | 12.2 | 24 cores, 188 GB (4 GPUs/node; single-GPU allowed) |

### Billing is in RGU, not GPUs

The allocation unit is the **Reference GPU Unit**. Per-RGU bundle rates, one ratio per cluster:

| Cluster | Cores per RGU | Memory per RGU |
|---|---|---|
| Fir | 0.98 | 23.6 GB |
| Narval | 3.00 | 31.1 GB |
| Nibi | 1.15 | 20.5 GB |
| **Rorqual** | **1.31** | **10.2 GB** |
| Trillium | 1.97 | 15.4 GB |

`RGU charged = max( nGPUs × RGU_per_GPU , cores / cores_per_RGU , mem_GB / mem_per_RGU )`. The
"recommended per GPU" column above is just `RGU_per_GPU ×` those rates. Keep your own tally in
GPU-hours, but expect CCDB, `sshare` and the portal to read ~12.2× higher on the H100 clusters.

## MIG (fractional GPUs)

| Instance | Compute share / VRAM | RGU (cost vs. full H100) | Recommended cores, mem (Rorqual / Nibi / Fir) |
|---|---|---|---|
| `h100_1g.10gb` | 1/8, 10 GB | 1.74 (**≈1/7**) | 2c 15G / 2c 31G / 1c 35G |
| `h100_2g.20gb` | 2/8, 20 GB | 3.48 (**≈2/7**) | 4c 31G / 4c 62G / 3c 70G |
| `h100_3g.40gb` | 3/8, 40 GB | 6.1 (**exactly 1/2**) | 8c 62G / 6c 124G / 6c 140G |

**The names describe compute, not price.** A `3g` gives 3/8 of an H100 for half the cost, so it is a
worse deal per FLOP than it looks — still right for smoke jobs and small work (and it starts much
sooner), wrong for anything that could saturate a full GPU. Narval MIG: `a100_1g.5gb` 0.57,
`a100_2g.10gb` 1.14, `a100_3g.20gb` 2.0, `a100_4g.20gb` 2.3 RGU (full A100 = 4.0).

Full specifiers like `nvidia_h100_80gb_hbm3_1g.10gb` also work.

```bash
#SBATCH --gpus=h100_3g.40gb:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=62G
```

Limits: **at most one MIG instance per job** (multi-MIG jobs are rejected at submission — use a job
array or a full GPU). No CUDA IPC, no NVLink, no graphics APIs.

## Internet access from compute nodes

| Cluster | Compute nodes |
|---|---|
| **Rorqual** | **none** — site policy, exceptions by support ticket only |
| tamIA | **none** — same policy |
| Vulcan | Squid proxy, domain whitelist; ask support to add a domain |
| Fir, Narval, Nibi, Trillium | not documented as blocked — verify with a probe job before relying on it |

Login and automation nodes do have internet; compute nodes are the restricted ones. Everything a run
fetches must be staged beforehand — see the offline env vars in `SKILL.md` §3. Also worth knowing:
`crontab` is not offered on Rorqual or tamIA.

## Time limits

7 days max on Fir/Narval/Nibi/Rorqual, 24 h on Trillium **and on tamIA**. Partitions are nested at
3 h / 12 h / 24 h / 72 h / 7 d — a job asking for ≤3 h can run on every node, a 7-day job on a small
fraction. Ask for the shortest limit that plausibly fits, and checkpoint + resubmit rather than
requesting a week.

Rorqual and tamIA also set a *minimum*: jobs should be at least one hour, or five minutes for test
jobs. A 20-minute smoke job is fine; a stream of 60-second ones is not.

Job count limit: ≤1000 pending+running jobs (each array task counts). Use `--array=1-100%10` to cap
concurrency. Space out `sbatch` calls by ≥1 s if scripting many.

## OptiX / hardware ray tracing

The SDK is a module on every cluster (AVX2 and AVX512 stacks): `optix/6.5.0`, `7.7.0`, **`8.0.0`**.
Load it alongside CUDA; no need to vendor headers.

```bash
module load StdEnv/2023 cuda/12.2 optix/8.0.0
export OptiX_INSTALL_DIR=$EBROOTOPTIX     # set by the module; CMake wants the SDK root
```

**The host implementation lives in the driver (`libnvoptix.so.1`), not in the SDK.** It exists only
on GPU compute nodes, so `optixInit()` fails on login and automation nodes. You can *compile* OptiX
code anywhere with CUDA; you can only *run* it inside a GPU job. A build that links fine and then
dies at init is almost always this.

### Which clusters have RT cores

| Cluster | GPU | Architecture | RT cores | OptiX |
|---|---|---|---|---|
| Killarney *(human-only)* | L40S-48GB | Ada AD102 | **yes (3rd gen)** | hardware-accelerated |
| Vulcan *(human-only)* | L40S-48GB | Ada AD102 | **yes (3rd gen)** | hardware-accelerated |
| Fir, Nibi, Rorqual, Trillium | H100-80GB | Hopper GH100 | **none** | works — software traversal |
| Killarney (perf tier) | H100-80GB | Hopper GH100 | **none** | works — software traversal |
| Narval | A100-40GB | Ampere GA100 | **none** | works — software traversal |
| tamIA | H100 / H200 | Hopper | **none** | works — software traversal |
| Nibi | **MI300A** | AMD CDNA3 | n/a | **no CUDA, no OptiX at all** |

Datacenter Hopper and Ampere (GH100, GA100) ship **zero** RT cores — unlike their consumer
counterparts, and contrary to a lot of secondhand spec tables that claim H100 has 128. OptiX still
runs correctly there: NVIDIA's position is that "OptiX will run on the CUDA cores for any supported
GPU that does not come with RT cores, including the A100." BVH build and traversal execute on the
SMs instead of dedicated hardware.

Consequences:

- **Do not assume an H100 beats the local RTX card on a ray-tracing workload.** For
  BVH-traversal-bound code a consumer RTX GPU with RT cores can outperform an H100 that has none.
  Before committing real budget, run one short benchmark job and compare against local wall-clock on
  identical settings. If the cluster is slower per-GPU, the win is *parallelism across many jobs*,
  not per-run speed — plan the campaign that way.
- **Never request `mi300a` for OptiX work.** It is AMD; CUDA does not exist there.
- Every agent-reachable cluster is RT-core-free, so there is no ray-tracing reason to leave Rorqual.
- OptiX under **MIG** is unverified. It is CUDA-based rather than a graphics API, so it should work,
  but confirm with a 10-minute smoke job before building a campaign on it.
- Compute nodes are headless, and on Rorqual they have no internet at all (see above). Interactive
  viewers, OpenGL/Vulkan paths, and on-the-fly asset downloads will not work — offline/batch
  rendering only.

## Probing

`module spider <name>`, `avail_wheels torch`, `diskusage_report`, `sinfo -o "%G"`, `sacctmgr`,
`seff <jobid>` are all **blocked on the automation node** and must run inside a job. Wrap them in a
2-minute CPU-only `sbatch` probe and `cat` the output. Doing that once at the start of a campaign is
cheap and answers most environment questions in one go.

Profilers (Nsight etc.) need DCGM off on Narval/Rorqual: submit with `DISABLE_DCGM=1`.
