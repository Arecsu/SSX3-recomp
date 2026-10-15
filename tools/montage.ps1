# Contact sheet of screenshots, labelled with their file names, for checking
# many shots in one image.
#   powershell -File tools\montage.ps1 -Out sheet.png -Files a.png,b.png,... [-Cols 3] [-W 480]
param([Parameter(Mandatory)][string]$Out, [Parameter(Mandatory)][string]$Files, [int]$Cols = 3, [int]$W = 480)
$list = @($Files -split ",")
Add-Type -AssemblyName System.Drawing
$H = [int]($W * 3 / 4)
$rows = [Math]::Ceiling($list.Count / $Cols)
$sheet = New-Object System.Drawing.Bitmap ($W * $Cols), ($H * $rows)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::Black)
$font = New-Object System.Drawing.Font "Consolas", 11
for ($i = 0; $i -lt $list.Count; $i++) {
    $img = [System.Drawing.Image]::FromFile((Resolve-Path $list[$i]))
    $x = ($i % $Cols) * $W; $y = [Math]::Floor($i / $Cols) * $H
    $g.DrawImage($img, $x, $y, $W, $H)
    $g.DrawString([IO.Path]::GetFileNameWithoutExtension($list[$i]), $font, [System.Drawing.Brushes]::Yellow, $x + 4, $y + 4)
    $img.Dispose()
}
$sheet.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"$($list.Count) shots -> $Out"
