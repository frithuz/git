# Repository instructions

- Keep the Git compiler flags and source pins shared by Debian and OCI outputs.
- Keep multi-command Docker `RUN` steps in Bash scripts under `scripts/` or `test/`.
- Start Bash scripts with `set -euo pipefail`; format with shfmt and check with shellcheck.
- Never add `Co-Authored-By` trailers to commits.
- Run `task check` and the relevant container verification targets before completing changes.
- Publishing and deployment require repository configuration documented in README.md.
