# Compute Canada automation access — setup

One-time. Budget ~10 minutes plus a support ticket.

Regular login nodes require MFA, which an agent cannot satisfy. Agents connect instead to an
**automation node**, which accepts a constrained SSH key and no second factor.

**Sections marked `(*)` must be done by a human** — they need a browser, a passphrase, or an email.
Everything unmarked can be handed to an agent: just ask it to do that step.

## 0. Request access to the cluster itself (*)

Access is per-system opt-in — holding an allocation is not enough. Check and request at
<https://ccdb.alliancecan.ca/me/access_systems>. PAICE clusters (Killarney, Vulcan, tamIA) appear
under the *Intelligence artificielle* tab and may take up to an hour to take effect. Without this,
login fails no matter how correct the key is. This page also shows which clusters you currently have.

## 1. Generate a dedicated key (*)

One key per use — do not reuse your interactive login key.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/cc_automation -C "cc_automation"   # do set a passphrase
```

Unlock it once per login session so the agent is never prompted:

```bash
ssh-add ~/.ssh/cc_automation
```

With `AddKeysToAgent yes` in the SSH config (step 5) you can skip `ssh-add`: the first connection
prompts for the passphrase and adds the key itself, later ones are silent. Expect once per login
session — under VS Code, `SSH_AUTH_SOCK` points at a per-session agent that does not survive a reboot.

## 2. Compose the constrained key string

The *public* key with all three constraints prepended as literal text, all on **one line**:

```bash
IP3=$(curl -s ifconfig.me | cut -d. -f1-3)     # first 3 octets of the machine the AGENT runs on
printf 'restrict,from="%s.*",command="/cvmfs/soft.computecanada.ca/custom/bin/computecanada/allowed_commands/allowed_commands.sh" %s\n' \
  "$IP3" "$(cat ~/.ssh/cc_automation.pub)"
```

Output looks like:

```
restrict,from="132.203.32.*",command="/cvmfs/soft.computecanada.ca/custom/bin/computecanada/allowed_commands/allowed_commands.sh" ssh-ed25519 AAAAC3Nza... cc_automation
```

Run it on **the machine that will connect to the cluster** — if you VS Code into a lab machine, that
is the lab machine, not your laptop. They are often on different subnets, and a `from=` naming the
wrong one fails as an opaque `Permission denied (publickey)`.

- `restrict` — no port/agent/X11 forwarding, no PTY.
- `from=` — must name at least the first three octets of a **public** IP (`x.y.z.*` is accepted,
  `x.y.*.*` is not). A new IP means the key stops working and must be re-uploaded.
- `command=` — the wrapper that whitelists commands. `allowed_commands.sh` is the broadest stock
  option. Narrower variants exist (`transfer_commands.sh`, `slurm_commands.sh`, …), and `command=`
  can point at any script you write if you need more.

## 3. Upload it (*)

At <https://ccdb.alliancecan.ca/ssh_authorized_keys>. It must go in CCDB — a key in
`~/.ssh/authorized_keys` on the cluster is **not** accepted by automation nodes. Check the paste is
one unbroken line with no newline in the middle.

## 4. Request automation-node access (*)

Automation nodes are "available only by request". Email <support@tech.alliancecan.ca> and, as the
wiki asks, "explain in detail the type of automation you intend to use… what commands will be
executed and what tools or libraries you will be using to manage the automation." State the
originating IP too, since it must match `from=`. No turnaround time is published; it is a human
ticket, so do not plan around it being immediate.

## 5. Add the SSH config

On the machine the agent runs from — the same one whose IP you used above. Append to `~/.ssh/config`.
One CCDB key works on every cluster, so define an alias per automation node and share the settings:

```
# One alias per cluster with an automation node. `cc` = the default, Rorqual.
Host cc cc-rorqual
  HostName robot.rorqual.alliancecan.ca
Host cc-fir
  HostName robot.fir.alliancecan.ca
Host cc-narval
  HostName robot.narval.alliancecan.ca
Host cc-nibi
  HostName robot.nibi.alliancecan.ca
Host cc-tamia
  HostName robot.tamia.ecpia.ca
Host cc-trillium
  HostName robot2.scinet.utoronto.ca
Host cc-trillium-gpu
  HostName trig-robot1.scinet.utoronto.ca

# Shared settings for all of the above.
Host cc cc-*
  User yohanpg                    # your Alliance username — must match CC_USER in config.sh
  IdentityFile ~/.ssh/cc_automation
  IdentitiesOnly yes
  AddKeysToAgent yes
  RequestTTY no
  ServerAliveInterval 60
```

Order matters: SSH takes the **first** value it finds for each keyword, so the per-cluster
`HostName` blocks must come before the shared `Host cc cc-*` block. `cc-*` does not match plain
`cc`, which is why `cc` is listed explicitly in both.

There is no Killarney or Vulcan alias — those clusters have no automation node.

Then verify:

```bash
ssh cc ls                              # should list your home directory
ssh cc "echo hello"                    # allowed
ssh cc "whoami"                        # should be REJECTED — confirms the wrapper is active
```

Each cluster is a separate opt-in (step 0), so an alias only works once you have access to that
cluster; `ssh cc-fir ls` failing while `ssh cc ls` works usually means Fir access was never
requested, not that the config is wrong.

The rejection message names the wrapper script you were actually given, which may be narrower than
`allowed_commands.sh`. Tell the agent which one you have.

Once `ssh cc ls` works, you are done.

### Reading a failure

Run `ssh -4 -v cc "echo OK"` and look at the last few `debug1:` lines. The three outcomes are
distinguishable and mean different things:

| What you see | Meaning |
|---|---|
| `Server accepts key` → `partial success` → `Authenticated … using "keyboard-interactive"` → `echo OK` output | **working.** The partial success and the second stage are normal — see below |
| No `Server accepts key`; ends `Permission denied (publickey)` | the key is not in CCDB, or `from=` does not match your current public IP (`curl ifconfig.me`), or you connected over IPv6 against an IPv4 mask — retry with `ssh -4` |
| `Server accepts key` → **`Authenticated using "publickey" with partial success`** → `Permission denied (keyboard-interactive,hostbased)` | either you passed `BatchMode=yes` (see below), or the node is demanding real MFA and the session is not being treated as automation |

**A successful automation login still shows `partial success`.** Publickey is only ever the first
factor; the node then opens a `keyboard-interactive` stage and, for an enrolled account, sends **zero
prompts**, so it passes silently. That empty challenge is what enrollment buys. Consequence:
`ssh -o BatchMode=yes` and `-o NumberOfPasswordPrompts=0` disable the second stage and fail on a host
that works — **never use them here.** Rule out your own flags with `ssh cc ls </dev/null` before
reading the row above as an access problem.

If it fails *without* those flags, authentication genuinely succeeded and MFA is genuinely being
enforced. It means one of:

- the automation-node request (step 4) has not been granted yet — it is a human support ticket with
  no published turnaround; or
- the key went into CCDB's ordinary **SSH Keys** page rather than
  <https://ccdb.alliancecan.ca/ssh_authorized_keys>. An ordinary key still authenticates on the robot
  host but does not confer automation status, so MFA is still enforced. Check which page it is under
  and, if it is the wrong one, re-upload the constrained string from step 2 to the authorized-keys
  page; or
- the constraints were stripped or reflowed during the paste, so CCDB stored it as a plain key.

An agent cannot resolve any of these. There is no `-o` flag, no retry, and no alternate host that
works around it. Note enrollment propagates **per cluster and not simultaneously**: as of 2026-07-23
Rorqual, Narval and Trillium were live while Fir and tamIA still failed this way, so one cluster
failing while another works is expected and is not a config error.

## Widening the wrapper (*)

If the agent keeps hitting the whitelist, `command=` can point at **any** script you write. Adding
`seff`, `sacct`, `sinfo`, `diskusage_report` and a read-only `srun --overlap` for monitoring is a
small, defensible change — and better than the agent accumulating workarounds. It needs a re-upload
in CCDB (step 3), and possibly a support ticket.
