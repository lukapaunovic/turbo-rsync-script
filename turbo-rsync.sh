#!/usr/bin/env bash
set -euo pipefail
# CONFIGURABLE
# Source directory (trailing slash = copy contents)
SRC="/path/to/source/"
# Destination (user@host:/path/)
DST="user@host:/path/to/destination/"
PAR="${PARALLEL:-3}"
BIG="64M"
USE_RELATIVE="${USE_RELATIVE:-1}"
DRY_RUN="${DRY_RUN:-0}"
# SSH options
SSHOPTS=(
  -T
  -o Compression=no
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=6
  -o TCPKeepAlive=yes
  -o IPQoS=throughput
)
# rsync base options
RSYNC_BASE_OPTS=(
  -a
  --info=progress2
  --stats
  --human-readable
)
# Dry-run switch
if [[ "$DRY_RUN" -eq 1 ]]; then
  RSYNC_BASE_OPTS+=(--dry-run)
  echo ">>> DRY-RUN MODE ENABLED"
fi
# Check rsync version (>= 3.0.0 because of --append-verify)
RSYNC_VER_RAW="$(rsync --version | head -n1 | grep -oE '[0-9]+(\.[0-9]+){0,2}' | head -n1)"
RSYNC_VER_NUM="$(awk -v v="$RSYNC_VER_RAW" 'BEGIN{
  n=split(v,a,".");
  maj=(n>=1?a[1]:0)+0;
  min=(n>=2?a[2]:0)+0;
  pat=(n>=3?a[3]:0)+0;
  print maj*10000 + min*100 + pat;
}')"
if [ -z "$RSYNC_VER_NUM" ] || [ "$RSYNC_VER_NUM" -lt 30000 ]; then
  echo "rsync $RSYNC_VER_RAW is too old (required >= 3.0.0 because of --append-verify)." >&2
  exit 1
fi
# Fallback for ionice/nice
if command -v ionice >/dev/null 2>&1; then
  NICE_LOCAL=(ionice -c2 -n7 nice -n 10)
else
  NICE_LOCAL=(nice -n 10)
fi
REMOTE_WRAPPER="ionice -c2 -n7 nice -n 10 rsync"
# Sanity
[[ -d "$SRC" ]] || { echo "SRC does not exist: $SRC" >&2; exit 1; }
echo "=== DRY RUN LIST (rsync -anv) ==="
rsync -anv -e "ssh ${SSHOPTS[*]}" "${SRC}" "${DST}"
echo "=== MAIN SYNC (resumable, without partial-dir) ==="
"${NICE_LOCAL[@]}" rsync "${RSYNC_BASE_OPTS[@]}" \
  --partial \
  --inplace \
  --append-verify \
  -e "ssh ${SSHOPTS[*]}" \
  --rsync-path="${REMOTE_WRAPPER}" \
  "${SRC}" "${DST}"
echo "=== PARALLEL SYNC (> ${BIG}) ==="
RELATIVE_OPT=()
[[ "$USE_RELATIVE" -eq 1 ]] && RELATIVE_OPT=(--relative)
ORIG_PWD="$PWD"
cd "$SRC"
find . -type f -size "+${BIG}" -print0 |
  xargs -0 -P "$PAR" -I{} \
    "${NICE_LOCAL[@]}" rsync "${RSYNC_BASE_OPTS[@]}" \
      --partial --inplace --append-verify \
      "${RELATIVE_OPT[@]}" \
      --rsync-path="${REMOTE_WRAPPER}" \
      -e "ssh ${SSHOPTS[*]}" \
      "{}" "$DST"
cd "$ORIG_PWD"
echo "=== SYNC COMPLETE ==="
