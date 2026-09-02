#!/usr/bin/env bash
# Record an input lost to error isolation.
#
# conf/error_isolation.config ignores exit codes 1 and 2 on the QC and
# classification processes so one bad file cannot stop a run. Nothing then
# said which file was lost: the trace row is FAILED but names the sample, the
# manifest lists failed SAMPLES, and aggregation_stats.json cannot see a QC
# failure because batch ids are assigned after QC (nanometa_live round-4
# audit, H20). This script runs as the process's afterScript -- after the
# command has exited, with its exit status -- and writes one JSON marker per
# ignored failure under <outdir>/pipeline_info/lost_inputs/.
#
# Usage: nanometanf_lost_input_marker.sh <exit_status> <outdir> <process> <sample> <batch_id> <attempt>
#
# The staged inputs are the symlinks in the task work directory; their
# targets are the real input paths. Only FASTQ-like names are recorded so a
# database or reference symlink is not listed as a lost input.
set -u
rc="${1:-0}"
outdir="${2:-}"
process="${3:-unknown}"
sample="${4:-unknown}"
batch_id="${5:-}"
attempt="${6:-1}"

case "$rc" in
    1|2) ;;
    *) exit 0 ;;
esac
[ -n "$outdir" ] || exit 0

stage="${process##*:}"
marker_dir="${outdir}/pipeline_info/lost_inputs"
mkdir -p "$marker_dir" 2>/dev/null || exit 0
workdir="$(pwd)"
hash="${workdir##*/}"

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

files=""
for link in ./*; do
    [ -L "$link" ] || continue
    case "$link" in
        *.fastq|*.fastq.gz|*.fq|*.fq.gz) ;;
        *) continue ;;
    esac
    target="$(readlink "$link")"
    [ -n "$files" ] && files="${files}, "
    files="${files}\"$(json_escape "$target")\""
done

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
safe_sample="$(printf '%s' "$sample" | tr -c 'A-Za-z0-9._-' '_')"
marker="${marker_dir}/${stage}.${safe_sample}.${hash}.json"
tmp="${marker}.tmp"
cat > "$tmp" <<EOF
{
  "stage": "$(json_escape "$stage")",
  "process": "$(json_escape "$process")",
  "sample": "$(json_escape "$sample")",
  "batch_id": "$(json_escape "$batch_id")",
  "attempt": ${attempt},
  "exit_status": ${rc},
  "input_files": [${files}],
  "work_dir": "$(json_escape "$workdir")",
  "written_at": "${stamp}"
}
EOF
mv -f "$tmp" "$marker"
exit 0
