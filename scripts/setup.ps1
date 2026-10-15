# Windows twin of scripts/setup.sh: one-time setup of the toolkit next to this
# repo, no WSL needed.
#
#   <parent>\xboxrecomp     sp00nznet/xboxrecomp at $Base + patches\xboxrecomp-local.patch
#   <parent>\ssx3-recomp    this repo
#   ssx3-recomp\game\       your own rip: default.xbe + data\ (not in git)
#
# Needs git and Python 3.9+ on PATH. Creates xboxrecomp\.venv with capstone.
# Safe to re-run.
#   powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
# Native tools write progress to stderr, which "Stop" would turn into a
# fatal error under Windows PowerShell 5.1: exit codes are checked instead.
$ErrorActionPreference = "Continue"
$Base = "193e299"                    # v0.13.1 "Cut Short"
$Url = if ($env:XBOXRECOMP_URL) { $env:XBOXRECOMP_URL } else { "https://github.com/sp00nznet/xboxrecomp.git" }

$here = Split-Path -Parent $PSScriptRoot
$tk = Join-Path (Split-Path -Parent $here) "xboxrecomp"
$patch = Join-Path $here "patches\xboxrecomp-local.patch"

function RunGit { & git @args; if ($LASTEXITCODE) { throw "git $args failed" } }

if (-not (Test-Path (Join-Path $tk ".git"))) {
    # LF working tree, like upstream: the local patch is LF and would not
    # apply to CRLF files (core.autocrlf=true is the Windows default).
    RunGit clone -c core.autocrlf=false $Url $tk
}
$dirty = & git -C $tk status --porcelain --untracked-files=no
if (-not $dirty) {
    RunGit -C $tk checkout -q $Base
    RunGit -C $tk apply --whitespace=nowarn $patch
    "toolkit: $Base + local patch applied"
} else {
    & git -C $tk apply --reverse --check $patch 2>$null
    if ($LASTEXITCODE -eq 0) { "toolkit: local patch already applied" }
    else { Write-Warning "toolkit has other local changes; leaving it alone" }
}

$py = Join-Path $tk ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) {
    & python -m venv (Join-Path $tk ".venv")
    if ($LASTEXITCODE) { throw "python -m venv failed (is Python 3.9+ on PATH?)" }
}
& $py -c "import capstone" 2>$null
if ($LASTEXITCODE) {
    & $py -m pip install -q capstone==5.0.9
    if ($LASTEXITCODE) { throw "pip install capstone failed" }
}
& $py -c "import capstone; print('capstone ok')"
