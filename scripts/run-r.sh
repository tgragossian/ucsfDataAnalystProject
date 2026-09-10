#!/bin/sh
# The conda R launcher does not quote paths containing spaces. Use its binary directly.
set -eu
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"
if [ -x .runtime/lib/R/bin/exec/R ]; then
  R_HOME="$PROJECT_ROOT/.runtime/lib/R"
  export R_HOME
  exec "$R_HOME/bin/exec/R" --vanilla --slave "$@"
fi
exec R --vanilla --slave "$@"

