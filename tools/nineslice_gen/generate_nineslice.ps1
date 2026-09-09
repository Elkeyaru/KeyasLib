<#
    generate_nineslice.ps1 - bakes KeyasCSS's runtime 9-slice atlas.

    KeyasCSS draws rounded rectangles, borders and drop shadows at ANY box
    size by 9-slicing two small source blocks in this atlas: the four
    corners are drawn at a fixed pixel size, the four edges are stretched
    along one axis, the centre is stretched both ways. Tinting at draw time
    gives any colour, so one white atlas covers every colour the UI needs.

    This is an offline dev tool (Windows + .NET). The PNG it writes,
    common/media/ui/KeyasLib/keyas_ui_9slice.png, DOES ship inside the mod
    - it is the one asset KeyasCSS needs at runtime.

    Layout of the 128 x 64 atlas (origin top-left):

      ( 0, 0, 64, 64)  ROUND  - opaque white rounded square, corner radius
                                RADIUS, anti-aliased edge, transparent
                                outside. Used for solid fills, borders and
                                the border-radius mask.
      (64, 0, 64, 64)  SHADOW - white rounded square, same radius, blurred
                                by BLUR so the 9-slice edges fade out.
                                Used for box-shadow.

    Regenerate:  powershell -ExecutionPolicy Bypass -File generate_nineslice.ps1
#>

param(
    [string]$OutDir = "$PSScriptRoot\..\..\common\media\ui\KeyasLib",
    [int]$Radius = 20,
    [int]$Blur = 14
)

Add-Type -AssemblyName System.Drawing

$cell   = 64
$atlasW = 128
$atlasH = 64

$bmp = New-Object System.Drawing.Bitmap($atlasW, $atlasH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.Clear([System.Drawing.Color]::FromArgb(0, 255, 255, 255))

function New-RoundedPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2.0
    if ($d -gt $w) { $d = $w }
    if ($d -gt $h) { $d = $h }
    $p.AddArc($x,             $y,             $d, $d, 180, 90)
    $p.AddArc($x + $w - $d,   $y,             $d, $d, 270, 90)
    $p.AddArc($x + $w - $d,   $y + $h - $d,   $d, $d,   0, 90)
    $p.AddArc($x,             $y + $h - $d,   $d, $d,  90, 90)
    $p.CloseFigure()
    return $p
}

$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

# --- ROUND block: crisp opaque rounded square, inset 1px so the AA edge
#     isn't clipped by the atlas cell boundary. -----------------------------
$rp = New-RoundedPath 1 1 ($cell - 2) ($cell - 2) $Radius
$g.FillPath($white, $rp)
$rp.Dispose()

# --- SHADOW block: same square, then a Gaussian-ish blur by stacking a few
#     scaled-down / scaled-up passes (no System.Drawing native blur). ------
$shadow = New-Object System.Drawing.Bitmap($cell, $cell, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$sg = [System.Drawing.Graphics]::FromImage($shadow)
$sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$sg.Clear([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
$inset = [single]$Blur
$sp = New-RoundedPath $inset $inset ($cell - 2 * $inset) ($cell - 2 * $inset) ([single]([Math]::Max(2, $Radius - $Blur)))
$sg.FillPath($white, $sp)
$sp.Dispose()
$sg.Dispose()

# Cheap separable box blur, a few passes -> soft falloff.
function Invoke-BoxBlur([System.Drawing.Bitmap]$src, [int]$radius, [int]$passes) {
    $w = $src.Width; $h = $src.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    for ($pass = 0; $pass -lt $passes; $pass++) {
        $data = $src.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $bytes = New-Object byte[] ($data.Stride * $h)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
        $out = New-Object byte[] ($bytes.Length)
        for ($y = 0; $y -lt $h; $y++) {
            for ($x = 0; $x -lt $w; $x++) {
                $sum = 0; $n = 0
                for ($k = -$radius; $k -le $radius; $k++) {
                    $xx = $x + $k
                    if ($xx -lt 0 -or $xx -ge $w) { continue }
                    $sum += $bytes[($y * $data.Stride) + ($xx * 4) + 3]; $n++
                }
                $idx = ($y * $data.Stride) + ($x * 4)
                $a = [int]($sum / $n)
                $out[$idx] = 255; $out[$idx + 1] = 255; $out[$idx + 2] = 255; $out[$idx + 3] = $a
            }
        }
        # vertical pass
        $bytes = $out.Clone()
        $out = New-Object byte[] ($bytes.Length)
        for ($y = 0; $y -lt $h; $y++) {
            for ($x = 0; $x -lt $w; $x++) {
                $sum = 0; $n = 0
                for ($k = -$radius; $k -le $radius; $k++) {
                    $yy = $y + $k
                    if ($yy -lt 0 -or $yy -ge $h) { continue }
                    $sum += $bytes[($yy * $data.Stride) + ($x * 4) + 3]; $n++
                }
                $idx = ($y * $data.Stride) + ($x * 4)
                $a = [int]($sum / $n)
                $out[$idx] = 255; $out[$idx + 1] = 255; $out[$idx + 2] = 255; $out[$idx + 3] = $a
            }
        }
        [System.Runtime.InteropServices.Marshal]::Copy($out, 0, $data.Scan0, $out.Length)
        $src.UnlockBits($data)
    }
}

Invoke-BoxBlur $shadow ([Math]::Max(2, [int]($Blur / 3))) 3

$g.DrawImage($shadow, 64, 0, $cell, $cell)
$shadow.Dispose()

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$outPng = Join-Path $OutDir "keyas_ui_9slice.png"
$g.Dispose()
$bmp.Save($outPng, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$white.Dispose()

Write-Host "wrote $outPng  (${atlasW}x${atlasH}, radius=$Radius, blur=$Blur)"
Write-Host "KeyasCSS constants to match: NINESLICE_ROUND_SRC=64, NINESLICE_SHADOW_SRC=64, corner source inset for ROUND = $Radius"
