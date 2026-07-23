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

### `LD_LIBRARY_PATH` is unset — runtime `dlopen` of cuDNN sub-libraries fails
Rorqual / 2026-07-22. The CC software stack links with RPATH and **does not set `LD_LIBRARY_PATH` at
all** (`echo $LD_LIBRARY_PATH` after `module load StdEnv/2023 cuda/12.6 cudnn` → *unbound variable*).
Anything that resolves a library at runtime rather than at link time therefore fails, even with the
right module loaded. PyTorch 2.6 does exactly this for the split cuDNN 9 libraries:

```
Unable to load any of {libcudnn_engines_precompiled.so.9.2.1, ...so.9.2, ...so.9, ...so}
RuntimeError: ptrDesc->finalize()          # much later, inside a TorchScript conv
```

The second line is what you actually see — the first is a lone warning hundreds of lines earlier, and
the traceback printed is the *serialized* one from NVIDIA's machine at trace time, which sends you
looking in the wrong place entirely. Fix is one line in the job script:

```bash
export LD_LIBRARY_PATH=$EBROOTCUDNN/lib:${LD_LIBRARY_PATH:-}
```

Note torch names the cuDNN version it was *compiled* against (9.2.1) first, then falls back to
`.so.9`, so the newer `cudnn/9.10.0.56` module works fine. Do not chase the exact version — pinning
`cudnn/9.2.1.18` fails to load anyway, since it requires `cudacore/.12.2.2` and Rorqual's `opencv`
and `cuda/12.6` chain cannot satisfy it. Also: `cudnn` is a **separate module from `cuda`**; loading
only `cuda/12.6` gives `OSError: libcudnn.so: cannot open shared object file`.

### `opencv-python` is a stub wheel that kills the whole `pip install` line
Rorqual / 2026-07-22. `pip install --no-index opencv-python` fails with
`ERROR: Failed to build 'opencv-noinstall'` and a message telling you to `module load opencv/x.y.z`.
Because pip installs a batch atomically, one stub takes down every other package on the same command
line — the symptom is 20 packages "missing" when only one was refused. Use `module load
opencv/4.12.0` instead, and note **it swaps the loaded Python to 3.11.5**, so pin wheels for cp311
and create the venv *after* the module loads.

More generally: install pinned, must-have wheels in one `pip install`, and loop over the optional
ones separately (`pip install --no-index "$p" || echo MISS $p`) so a single absentee does not cost
you a job.

### Wheelhouse gaps are real, and the automation node has no `pip`
Rorqual / 2026-07-22. `megatron-core`, `better-profanity` and `retinaface-py` are absent from the
wheelhouse entirely (all three are hard imports for NVIDIA Cosmos). `transformer_engine` is present
but its companion `transformer_engine_torch` is a **separate wheel that nothing depends on** — pip
skips it and `import transformer_engine.pytorch` then dies on a bare `StopIteration` inside
`_load_library`, which globs its own directory for a `.so` that was never installed. Name it
explicitly.

For the genuinely absent ones: `ssh cc "python3 -m pip download …"` does **not** work — the
automation node's `python3` has no `pip` module (`No module named pip`), contradicting the obvious
reading of the whitelist. Download locally and rsync, or (for pure-Python packages) rsync the
directory straight out of a local env onto `PYTHONPATH`.

### Free GPUs are countable with `scontrol`, not `sinfo`
Rorqual / 2026-07-22. `sinfo` and `partition-stats` are blocked, but `scontrol -o show nodes` is
allowed and carries everything needed: `CfgTRES` has `gres/gpu:<model>=N`, `AllocTRES` has the
in-use count, and `State` flags `DOWN`/`DRAIN`. Free = Cfg − Alloc over non-drained nodes. The output
is ~780 lines (~1 MB) — fine to `cat` back and parse locally, and note there is **no `GresUsed`
field** on Slurm 25.11 here, so parse the TRES fields.


### Sudden `Permission denied` on ALL clusters mid-session = ssh-agent dropped the key passphrase
Rorqual+Narval+Trillium / 2026-07-22. After hours of working ssh, all three automation nodes began
denying simultaneously: `ssh -v` shows `Server accepts key: …cc_automation` then
`Permission denied (publickey,hostbased)`, with only `publickey,hostbased` offered and **no
`keyboard-interactive`** stage. IP unchanged and inside the mask, key perms 600. **Cause turned out
to be simple: the user's ssh-agent had dropped the decrypted key and just needed the passphrase
re-entered** (`ssh-add ~/.ssh/cc_automation`). It resolved the instant they did so. So this is *not*
an enrollment lapse and *not* a server outage — the "server accepts key" line is misleading (it means
the key is offered and known, not that auth passed), and the missing keyboard-interactive stage is
just what a locked/absent private key looks like from the client side. **When ssh suddenly fails on
every cluster at once with nothing changed locally, ask the user to re-add the key to their agent
before suspecting anything server-side** — it is the cheapest thing to rule out and was the answer
here. Running Slurm jobs keep going while the agent is locked; reconnect and resume once the key is
re-added (but a poor-man's-REPL job may hit its walltime while you are locked out — ours did).

Topology that produced this (worth knowing): the CC key lived on a **Linux workstation**, encrypted,
and `SSH_AUTH_SOCK` was a **VS Code agent-forward** of the user's *Mac* agent (tell-tale:
`ssh-add -l` lists a `/Users/<name>/...` key alongside the CC one). So the decrypted key is held in
the forwarded Mac agent and is lost on Mac reboot or a VS Code reconnect. **Because the agent runs
ssh non-interactively (`</dev/null`), a passphrase-locked key that is not already in the agent
hard-fails with `Permission denied` instead of prompting** — so from the agent's side an encrypted
key is all-or-nothing. Durable fixes, best first: (a) remove the passphrase on the key
(`ssh-keygen -p -f <key>`, empty new passphrase) — the automation key is already restricted by
`from=`/`command=`/`restrict`, and this makes non-interactive ssh immune to the whole problem;
(b) macOS Keychain (`ssh-add --apple-use-keychain` + `UseKeychain yes`) *only if the key is managed
on the Mac* — it is macOS-only and does nothing run on the Linux box. Propose, don't do: editing a
user's key is theirs to decide.
