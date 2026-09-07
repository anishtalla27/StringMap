#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
environment_dir="$script_dir/.venv-homr"

if [ -n "${STRINGMAP_PYTHON:-}" ]; then
  python_executable="$STRINGMAP_PYTHON"
elif command -v python3.12 >/dev/null 2>&1; then
  python_executable=$(command -v python3.12)
else
  python_executable=$(command -v python3)
fi

"$python_executable" -c 'import sys; assert sys.version_info[:2] == (3, 12), "Use Python 3.12 for the pinned HOMR runtime."'
"$python_executable" -m venv "$environment_dir"
"$environment_dir/bin/python" -m pip install --upgrade pip
"$environment_dir/bin/python" -m pip install -r "$script_dir/requirements-lock.txt"
"$environment_dir/bin/python" "$script_dir/patch_homr.py"

"$environment_dir/bin/python" "$script_dir/models.py" --download
printf '\nInstalled. Start with:\n  OMR_ENV=development OMR_DATA_DIR=/tmp/stringmap-omr %s -m uvicorn --app-dir %s production:configured_app --factory --host 127.0.0.1 --port 8765 --no-access-log\n' "$environment_dir/bin/python" "$script_dir"
