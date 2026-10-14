# The game's own state, as src/game_state.c publishes it in game_state.txt
# (vtable of the current app state object, its name, ms since start, seconds
# in this state). Dot-source and call:
#   . "$PSScriptRoot\game_state.ps1"; $s = Get-GameState $root
#   $s.Name, $s.Vt, $s.Seconds, $s.Sub, $s.Draws (total GPU draws)
#   ($null if the game is not publishing yet)
# Names: boot, intro, frontend (all menus), event_enter, loading, ingame.
function Get-GameState([string]$Root) {
    $f = Join-Path $Root "game_state.txt"
    try {
        $parts = (Get-Content -Path $f -ErrorAction Stop -TotalCount 1) -split " "
    } catch { return $null }
    if ($parts.Count -lt 4) { return $null }
    [pscustomobject]@{ Vt = $parts[0]; Name = $parts[1];
                       Ms = [long]$parts[2]; Seconds = [long]$parts[3];
                       Sub = $(if ($parts.Count -ge 5) { [long]$parts[4] } else { 0 });
                       Draws = $(if ($parts.Count -ge 6) { [long]$parts[5] } else { -1 }) }
}
