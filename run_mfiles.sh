#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config / Arguments
# =========================
usage() {
  cat <<EOF
Usage:
  $0 -i /path/to/mfiles -o /path/to/results

Notes:
  - Each .m file is called as a function with no inputs (basename is the function name).
  - All outputs created during the run (MATLAB's current folder) are collected into the results folder.
EOF
}

INPUT_DIR=""
RESULTS_DIR=""

while getopts ":i:o:h" opt; do
  case "$opt" in
    i) INPUT_DIR="$OPTARG" ;;
    o) RESULTS_DIR="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
  esac
done

if [[ -z "${INPUT_DIR}" || -z "${RESULTS_DIR}" ]]; then
  usage; exit 1
fi

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "ERROR: INPUT_DIR does not exist: $INPUT_DIR" >&2
  exit 1
fi

mkdir -p "$RESULTS_DIR"

# Prefer MATLAB -batch if available; fall back to -nodisplay/-r
matlab_batch() {
  # usage: matlab_batch "MATLAB_COMMANDS"
  local cmd="$1"
  if command -v matlab >/dev/null 2>&1; then
    if matlab -batch "exit" >/dev/null 2>&1; then
      matlab -batch "$cmd"
    else
      matlab -nodisplay -nosplash -nodesktop -r "$cmd"
    fi
  else
    echo "ERROR: 'matlab' not found in PATH." >&2
    return 127
  fi
}

# =========================
# Run each .m as a function
# =========================
shopt -s nullglob

# Find only top-level .m files in INPUT_DIR (avoid hidden)
mapfile -d '' MFILES < <(find "$INPUT_DIR" -maxdepth 1 -type f -name "*.m" -print0)

if [[ ${#MFILES[@]} -eq 0 ]]; then
  echo "No .m files found in: $INPUT_DIR"
  exit 0
fi

for mfile in "${MFILES[@]}"; do
  base="$(basename "$mfile")"
  func="${base%.m}"
  ts="$(date +%Y%m%d_%H%M%S)"
  workdir="$(mktemp -d)"
  outdir="${RESULTS_DIR}/${func}_${ts}"
  mkdir -p "$outdir"

  echo "=== Running function: $func  (from $base) ==="
  echo "  workdir: $workdir"
  echo "  outdir : $outdir"

  log="${outdir}/console.log"

  # Compose MATLAB commands:
  # 1) add INPUT_DIR (and subfolders) to path
  # 2) cd to a clean workdir so all outputs land there
  # 3) feval the function with no args
  # 4) on error, write an ERROR.txt into workdir
  # 5) exit MATLAB
  matlab_cmd=$(
    cat <<MAT
try
    addpath(genpath('$INPUT_DIR'));
    cd('$workdir');
    feval('$func');   % call function with no inputs
catch ME
    fid = fopen(fullfile('$workdir','ERROR.txt'),'w');
    fprintf(fid, '%s\\n\\n%s\\n', ME.identifier, getReport(ME, 'extended', 'hyperlinks', false));
    fclose(fid);
end
exit
MAT
  )

  # Run MATLAB and capture console output
  {
    echo "----- MATLAB START $(date) -----"
    echo "Calling function: $func"
    echo "Working dir: $workdir"
    echo "Path added : $INPUT_DIR"
  } >>"$log"

  if ! matlab_batch "$matlab_cmd" >>"$log" 2>&1; then
    echo "WARNING: MATLAB returned a non-zero exit code for $func. See $log" >&2
  fi

  # Move ALL files from workdir into outdir (captures .mat, .png, .csv, .pptx, etc.)
  shopt -s dotglob nullglob
  files=( "$workdir"/* )
  if [[ ${#files[@]} -gt 0 ]]; then
    for f in "${files[@]}"; do
      # Skip directories named '.' or '..' just in case
      [[ "$(basename "$f")" == "." || "$(basename "$f")" == ".." ]] && continue
      mv "$f" "$outdir"/
    done
  fi
  shopt -u dotglob nullglob

  # Also save a copy of the source .m alongside outputs for traceability
  cp "$mfile" "$outdir/${base}"

  # Clean temp
  rmdir "$workdir" 2>/dev/null || true

  echo "=== Done: $func -> $outdir ==="
done

echo "All functions processed."
