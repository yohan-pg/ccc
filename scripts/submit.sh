#!/bin/bash
# Sync a code directory to the cluster and submit a job script from it. Prints the job ID.
# Usage: submit.sh <local-code-dir> <job-script-relative-to-that-dir>
# Encodes the wrapper constraints: absolute remote paths, no shell operators over ssh,
# --no-g --no-p for /project group quotas.
set -euo pipefail

LOCAL_DIR=${1:?usage: submit.sh <local-code-dir> <job-script-relative-path>}
JOB_REL=${2:?usage: submit.sh <local-code-dir> <job-script-relative-path>}

source "$(dirname "${BASH_SOURCE[0]}")/../config.sh"

# Project space is reached via ~/links/ — /home/$CC_USER/projects does NOT exist.
# Each RAP is a separate tree with its own quota; CC_PROJECT_RAP picks which one.
PROJ=$(basename "${LOCAL_DIR%/}")
REMOTE_DIR=$CC_PROJECT/$PROJ
LOG_DIR=$CC_SCRATCH/$PROJ/logs

rsync -azh --no-g --no-p --delete \
  --exclude '.git' --exclude '__pycache__' --exclude 'output/' --exclude '*.pyc' \
  "${LOCAL_DIR%/}/" "$CC_HOST:$REMOTE_DIR/"

# The wrapper prints "Command rejected by ..." on stdout and still exits 0, so a refused command
# looks exactly like a successful one. Every ssh call must be judged by its output, not by $?.
# Do NOT add -o BatchMode=yes here. A working automation login authenticates in two stages
# (publickey -> "partial success" -> a zero-prompt keyboard-interactive); BatchMode disables the
# second stage and fails against a host that works. </dev/null is the safe way to be scripted.
cc_run() {
  local out
  out=$(ssh "$CC_HOST" "$1" </dev/null)
  if [[ $out == *"Command rejected by"* ]]; then
    echo "automation wrapper refused: $1" >&2
    echo "$out" >&2
    exit 1
  fi
  printf '%s' "$out"
}

# sbatch does not create the --output directory; a missing one kills the job with no log at all
cc_run "mkdir -p $LOG_DIR" >/dev/null

# One command, one ssh: the wrapper runs $SSH_ORIGINAL_COMMAND without eval, so no && or ;
JID=$(cc_run "sbatch --parsable --chdir=$REMOTE_DIR $REMOTE_DIR/$JOB_REL")

[[ $JID =~ ^[0-9]+ ]] || { echo "sbatch did not return a job id: $JID" >&2; exit 1; }

echo "$JID"
echo "host:       $CC_HOST" >&2
echo "remote dir: $REMOTE_DIR" >&2
echo "log dir:    $LOG_DIR  (job script wants #SBATCH --output=$LOG_DIR/%x-%j.out)" >&2
