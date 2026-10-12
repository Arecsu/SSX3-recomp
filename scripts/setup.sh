#!/usr/bin/env bash
# One-time setup of the toolkit next to this repo, the way the work was done:
#
#   <parent>/xboxrecomp     sp00nznet/xboxrecomp at XBOXRECOMP_BASE + patches/xboxrecomp-local.patch
#   <parent>/ssx3-recomp    this repo
#   <parent>/SSX3           your own rip: default.xbe + data/ (not in git)
#
# Also creates xboxrecomp/.venv with capstone. Safe to re-run.
set -euo pipefail

XBOXRECOMP_BASE=193e299               # v0.13.1 "Cut Short"
XBOXRECOMP_URL=${XBOXRECOMP_URL:-https://github.com/sp00nznet/xboxrecomp.git}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT="$(dirname "$HERE")"
TK="$PARENT/xboxrecomp"

if [ ! -d "$TK/.git" ]; then
    git clone "$XBOXRECOMP_URL" "$TK"
fi
if [ -z "$(git -C "$TK" status --porcelain --untracked-files=no)" ]; then
    git -C "$TK" checkout -q "$XBOXRECOMP_BASE"
    git -C "$TK" apply "$HERE/patches/xboxrecomp-local.patch"
    echo "toolkit: $XBOXRECOMP_BASE + local patch applied"
elif git -C "$TK" apply --reverse --check "$HERE/patches/xboxrecomp-local.patch" 2>/dev/null; then
    echo "toolkit: local patch already applied"
else
    echo "toolkit has other local changes; leaving it alone" >&2
fi

# Python venv with capstone. This WSL box had no pip and no ensurepip, so the
# fallback makes a pip-less venv and unzips the official wheel into it after
# checking its hash.
if ! "$TK/.venv/bin/python" -c "import capstone" 2>/dev/null; then
    if python3 -m venv "$TK/.venv" 2>/dev/null && "$TK/.venv/bin/python" -m pip --version >/dev/null 2>&1; then
        "$TK/.venv/bin/python" -m pip install -q capstone==5.0.9
    else
        rm -rf "$TK/.venv"
        python3 -m venv --without-pip "$TK/.venv"
        WHL=capstone-5.0.9-py3-none-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
        SHA=273fd8d747d2e35c88f91450be51a603ecfaafb00d96d9f315dcb8689c86193e
        TMP="$(mktemp -d)"
        curl -sSL -o "$TMP/$WHL" "https://files.pythonhosted.org/packages/d1/39/17747862222bb062e86b501f1f148d5ff589b77908b080d30f7f085cbfb7/$WHL"
        echo "$SHA  $TMP/$WHL" | sha256sum -c -
        SP="$("$TK/.venv/bin/python" -c "import sysconfig; print(sysconfig.get_paths()['purelib'])")"
        python3 -m zipfile -e "$TMP/$WHL" "$SP"
        rm -rf "$TMP"
    fi
fi
"$TK/.venv/bin/python" -c "import capstone; print('capstone ok')"
