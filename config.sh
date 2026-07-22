#!/bin/bash
# Per-user settings for the ccc skill. Everything user-specific lives here and nowhere else.
# Edit this file when handing the skill to someone new; the rest of the skill is generic.
# Sourced by scripts/*.sh, and read by agents to resolve `$CC_USER` / `$CC_ACCOUNT` in the docs.

# Alliance username (the one you log in with, not your email).
CC_USER=yohanpg

# PI's surname as it appears in the RAP group names: def-<PI>, rrg-<PI>, aip-<PI>.
CC_PI=jlalonde

# ------------------------------------------------------------------------------------

# Accounts, split by resource type: the RAC award on Rorqual is GPU-only (verified 2026-07-22).
# A GPU-less job under rrg- is rejected at submit, so CPU work has to go through def-.
# The rrg- award has the better priority — use it for anything with a GPU. See references/clusters.md.
CC_ACCOUNT_GPU=rrg-$CC_PI
CC_ACCOUNT_CPU=def-$CC_PI

# Back-compat alias for anything that just wants "the" account; GPU work is the common case.
CC_ACCOUNT=$CC_ACCOUNT_GPU

# Which RAP's project tree holds data. Each RAP has its own directory and its own quota, so keep
# this consistent with CC_ACCOUNT unless you have a reason not to.
CC_PROJECT_RAP=rrg-$CC_PI

# Default ssh alias -> default cluster. Aliases are defined in ~/.ssh/config (see SETUP.md):
# cc=Rorqual, cc-fir, cc-narval, cc-nibi, cc-tamia, cc-trillium, cc-trillium-gpu.
CC_HOST=${CC_HOST:-cc}

# Derived paths — no need to edit these.
CC_HOME=/home/$CC_USER
CC_PROJECT=$CC_HOME/links/projects/$CC_PROJECT_RAP/$CC_USER
CC_SCRATCH=$CC_HOME/links/scratch
