#!/bin/bash
# Per-user settings for the ccan skill. Everything user-specific lives here and nowhere else.
# Edit this file when handing the skill to someone new; the rest of the skill is generic.
# Sourced by scripts/*.sh, and read by agents to resolve `$CC_USER` / `$CC_ACCOUNT` in the docs.

# Alliance username (the one you log in with, not your email).
CC_USER=yohanpg

# PI's surname as it appears in the RAP group names: def-<PI>, rrg-<PI>, aip-<PI>.
CC_PI=jlalonde

# ------------------------------------------------------------------------------------

# Default account for jobs. The RAC award (rrg-) has far better priority but is valid only on the
# cluster it was awarded on; def- works everywhere at low priority. See references/clusters.md.
CC_ACCOUNT=rrg-$CC_PI

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
