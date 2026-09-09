# generate_skin.ps1 - bake a KeyasUI skin (chrome.png + zones.lua) from a spec.
#
# Offline tool. Nothing here ships inside the KeyasLib mod: run it on your
# machine, drop the two outputs into YOUR mod, and load them with
# KeyasUI.registerSkin (see tools/skin_gen/README.md).
#
# Why: ISUI can't draw rounded corners, gradients or shadows - but it can
# stretch a texture. So the whole fixed "chrome" of a retro-OS style window
# (bezel, gradient title bar, bevels, drop shadow, rail, decorative art,
# vignette + scanlines) is rendered ONCE here with System.Drawing (real
# LinearGradientBrush / PathGradientBrush / GraphicsPath arcs) into a single
# PNG. At runtime KeyasUI just blits that PNG; the consumer paints dynamic
# content into the named content zones this tool also emits.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File generate_skin.ps1 `
#       -Spec .\spec.xcyos.ps1 -OutDir ..\..\examples\xcyos
#
# Requires: Windows + .NET (System.Drawing). Every PZ modder on Windows has it.

param(
    [Parameter(Mandatory = $true)][string]$Spec,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [string]$Name = "chrome"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# The spec is a .ps1 that returns a hashtable. See spec.xcyos.ps1 for the
# full set of keys and their defaults.
$S = & (Resolve-Path $Spec)
if ($S -isnot [hashtable]) { throw "Spec must return a hashtable" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$cs = @'
using System;
using System.Collections;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;

public static class SkinBaker
{
    static Color Col(string hex) {
        hex = hex.TrimStart('#');
        return Color.FromArgb(255,
            Convert.ToInt32(hex.Substring(0,2),16),
            Convert.ToInt32(hex.Substring(2,2),16),
            Convert.ToInt32(hex.Substring(4,2),16));
    }
    static Color ColA(string hex, int a) { var c = Col(hex); return Color.FromArgb(a, c); }

    static GraphicsPath Round(RectangleF r, float rad) {
        var p = new GraphicsPath(); float d = rad * 2;
        if (rad <= 0) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure(); return p;
    }
    static void Bevel(Graphics g, RectangleF r, Color hi, Color lo) {
        using (var ph = new Pen(hi, 1f)) {
            g.DrawLine(ph, r.X, r.Y, r.Right - 1, r.Y);
            g.DrawLine(ph, r.X, r.Y, r.X, r.Bottom - 1);
        }
        using (var pl = new Pen(lo, 1f)) {
            g.DrawLine(pl, r.X, r.Bottom - 1, r.Right - 1, r.Bottom - 1);
            g.DrawLine(pl, r.Right - 1, r.Y, r.Right - 1, r.Bottom - 1);
        }
    }
    static void Pane(Graphics g, RectangleF r, Color face) {
        using (var b = new SolidBrush(face)) g.FillRectangle(b, r);
        Bevel(g, r, Col("6d6a61"), Col("eeece4"));
        using (var pb = new Pen(Color.FromArgb(200,0,0,0), 1f)) g.DrawRectangle(pb, r.X, r.Y, r.Width, r.Height);
    }
    static void DrawGlyph(Graphics g, Pen p, string kind, RectangleF r) {
        if (kind == "monitor") {
            g.DrawRectangle(p, r.X, r.Y, r.Width, r.Height * 0.72f);
            g.DrawLine(p, r.X + r.Width * 0.35f, r.Bottom, r.X + r.Width * 0.65f, r.Bottom);
        } else if (kind == "page") {
            g.DrawRectangle(p, r.X + 6, r.Y, r.Width - 12, r.Height);
            for (int i = 1; i <= 3; i++) g.DrawLine(p, r.X + 10, r.Y + i * 7, r.Right - 10, r.Y + i * 7);
        } else if (kind == "folder") {
            g.DrawLine(p, r.X, r.Y + 6, r.X, r.Bottom);
            g.DrawLine(p, r.X, r.Bottom, r.Right, r.Bottom);
            g.DrawLine(p, r.Right, r.Bottom, r.Right, r.Y + 10);
            g.DrawLine(p, r.X, r.Y + 6, r.X + r.Width * 0.4f, r.Y + 6);
            g.DrawLine(p, r.X + r.Width * 0.4f, r.Y + 6, r.X + r.Width * 0.5f, r.Y + 10);
            g.DrawLine(p, r.X + r.Width * 0.5f, r.Y + 10, r.Right, r.Y + 10);
        } else { // gear
            float cx = r.X + r.Width/2, cy = r.Y + r.Height/2, rr = r.Height*0.42f;
            g.DrawEllipse(p, cx-rr, cy-rr, rr*2, rr*2);
            g.DrawEllipse(p, cx-4, cy-4, 8, 8);
            for (int a=0;a<360;a+=60){ double rad=a*Math.PI/180;
                g.DrawLine(p, cx+(float)Math.Cos(rad)*rr, cy+(float)Math.Sin(rad)*rr,
                              cx+(float)Math.Cos(rad)*(rr+5), cy+(float)Math.Sin(rad)*(rr+5)); }
        }
    }

    static float F(Hashtable h, string k, float d) { return h.ContainsKey(k) ? Convert.ToSingle(h[k]) : d; }
    static string Str(Hashtable h, string k, string d) { return h.ContainsKey(k) ? (string)h[k] : d; }

    // returns "name x y w h" lines for zones.lua
    public static string Build(Hashtable s, string outPng)
    {
        int W = (int)F(s, "bakeW", 1920), H = (int)F(s, "bakeH", 1080);
        var sb = new System.Text.StringBuilder();

        using (var bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;

            // desktop radial gradient
            using (var path = new GraphicsPath()) {
                path.AddEllipse(-W*0.3f, -H*0.5f, W*1.9f, H*2.2f);
                using (var pgb = new PathGradientBrush(path)) {
                    pgb.CenterPoint = new PointF(W*0.62f, H*0.40f);
                    pgb.CenterColor = Col(Str(s, "desktopInner", "232a27"));
                    pgb.SurroundColors = new[] { Col(Str(s, "desktopOuter", "12140f")) };
                    g.FillRectangle(pgb, 0, 0, W, H);
                }
            }

            // CRT bezel
            float bez = F(s, "bezelRadius", 26);
            using (var pth = Round(new RectangleF(4,4,W-8,H-8), bez))
            using (var pen = new Pen(Col(Str(s, "bezel", "17181a")), 9f)) g.DrawPath(pen, pth);
            using (var pth = Round(new RectangleF(9,9,W-18,H-18), bez-4))
            using (var pen = new Pen(ColA("3a3b3e", 90), 1.5f)) g.DrawPath(pen, pth);

            // left rail
            var apps = (object[])s["railApps"];
            if (apps != null && apps.Length > 0) {
                float railX = F(s,"railX",22), railW = F(s,"railW",128);
                var stripe = (object[])s["stripe"];
                if (stripe != null)
                    for (int i=0;i<stripe.Length;i++)
                        using (var brs = new SolidBrush(ColA(stripe[i].ToString(), 235)))
                            g.FillRectangle(brs, railX-8, F(s,"stripeY",300)+i*8, railW+6, 8);
                using (var lf = new Font("Consolas", 8.5f, FontStyle.Bold))
                using (var lbr = new SolidBrush(Col("b6bfb8"))) {
                    for (int i=0;i<apps.Length;i++) {
                        var ap = (object[])apps[i];
                        float iy = F(s,"railTop",30) + i * F(s,"railStep",118);
                        var gr = new RectangleF(railX+railW/2-20, iy, 40, 30);
                        using (var pen = new Pen(Col("cfd8cf"), 2f)) DrawGlyph(g, pen, (string)ap[1], gr);
                        var sz = g.MeasureString((string)ap[0], lf);
                        g.DrawString((string)ap[0], lf, lbr, railX+(railW-sz.Width)/2, iy+40);
                        sb.AppendLine(string.Format("rail{0} {1} {2} {3} {4}", i+1, (int)railX, (int)iy-8, (int)railW, 88));
                    }
                }
            }

            // logo watermark
            string logo = Str(s, "logo", null);
            if (logo != null && System.IO.File.Exists(logo)) {
                try { using (var lg = new Bitmap(logo)) {
                    int lw = (int)F(s,"logoW",420); int lh = (int)((float)lw*lg.Height/lg.Width);
                    var ia = new ImageAttributes(); var cm = new ColorMatrix(); cm.Matrix33 = F(s,"logoAlpha",0.5f);
                    ia.SetColorMatrix(cm);
                    g.DrawImage(lg, new Rectangle(W-lw-(int)F(s,"logoMargin",40), H/2-lh/2, lw, lh),
                        0,0,lg.Width,lg.Height, GraphicsUnit.Pixel, ia);
                } } catch { }
            }

            // window
            var win = new RectangleF(F(s,"winX",172), F(s,"winY",60), F(s,"winW",1372), F(s,"winH",918));
            for (int sh=10; sh>=2; sh-=2)
                using (var b = new SolidBrush(Color.FromArgb(22,0,0,0)))
                using (var sp = Round(new RectangleF(win.X+sh,win.Y+sh,win.Width,win.Height), 4)) g.FillPath(b, sp);
            using (var b = new SolidBrush(Col(Str(s,"winFace","b9b6ad")))) g.FillRectangle(b, win);
            using (var pen = new Pen(Color.FromArgb(255,10,10,8), 1f)) g.DrawRectangle(pen, win.X, win.Y, win.Width, win.Height);
            Bevel(g, win, Col("eeece4"), Col("6d6a61"));
            sb.AppendLine(string.Format("win {0} {1} {2} {3}", (int)win.X, (int)win.Y, (int)win.Width, (int)win.Height));

            // title bar
            float tbH = F(s,"titleH",32);
            var tb = new RectangleF(win.X+2, win.Y+2, win.Width-4, tbH);
            using (var lgb = new LinearGradientBrush(tb, Col(Str(s,"titleTop","3f5049")), Col(Str(s,"titleBot","26302d")), 90f))
                g.FillRectangle(lgb, tb);
            using (var pen = new Pen(Color.FromArgb(255,0,0,0), 1f)) g.DrawLine(pen, tb.X, tb.Bottom, tb.Right, tb.Bottom);
            using (var tf = new Font("Consolas", 11f, FontStyle.Bold))
            using (var tbr = new SolidBrush(Col(Str(s,"titleInk","eafffb")))) {
                using (var fb = new SolidBrush(Col("f0c964"))) g.FillRectangle(fb, tb.X+12, tb.Y+9, 16, 12);
                g.DrawString(Str(s,"titleText","APLICACION"), tf, tbr, tb.X+38, tb.Y+7);
                using (var wf = new Font("Consolas", 12f, FontStyle.Bold))
                    g.DrawString("_  []  X", wf, tbr, tb.Right-90, tb.Y+6);
            }
            sb.AppendLine(string.Format("titleClose {0} {1} {2} {3}", (int)(tb.Right-30), (int)tb.Y, 26, (int)tbH-4));

            // panes
            var paneDefs = (object[])s["panes"];
            if (paneDefs != null) {
                foreach (object pd0 in paneDefs) {
                    var pd = (object[])pd0; // {name, x, y, w, h}
                    var pr = new RectangleF(
                        win.X + Convert.ToSingle(pd[1]), win.Y + Convert.ToSingle(pd[2]),
                        Convert.ToSingle(pd[3]), Convert.ToSingle(pd[4]));
                    Pane(g, pr, Col(Str(s,"paneFace","d0cdc4")));
                    // zone = pane interior, inset 14px
                    sb.AppendLine(string.Format("{0} {1} {2} {3} {4}", (string)pd[0],
                        (int)pr.X+14, (int)pr.Y+14, (int)pr.Width-28, (int)pr.Height-28));
                }
            }

            // status bar
            var sbar = new RectangleF(12, H-46, W-24, 30);
            using (var b = new SolidBrush(Col("05221c"))) g.FillRectangle(b, sbar);
            using (var pen = new Pen(Col("0b3b30"), 1f)) g.DrawLine(pen, sbar.X, sbar.Y, sbar.Right, sbar.Y);
            using (var sf = new Font("Consolas", 10.5f, FontStyle.Bold)) {
                using (var d = new SolidBrush(Col("1c8f7c")))
                    g.DrawString(Str(s,"statusLeft","TERMINAL"), sf, d, sbar.X+12, sbar.Y+6);
                using (var p = new SolidBrush(Col("2fe7c4"))) {
                    var t = Str(s,"statusRight","12:47  .  14/07/1993");
                    var sz = g.MeasureString(t, sf);
                    g.DrawString(t, sf, p, sbar.Right-sz.Width-14, sbar.Y+6);
                }
            }

            // scanlines + vignette, baked last
            using (var sl = new SolidBrush(Color.FromArgb((int)F(s,"scanAlpha",20), 0,0,0)))
                for (int y=0;y<H;y+=3) g.FillRectangle(sl, 0, y, W, 1);
            using (var vp = new GraphicsPath()) {
                vp.AddEllipse(-W*0.15f, -H*0.15f, W*1.3f, H*1.3f);
                using (var vg = new PathGradientBrush(vp)) {
                    vg.CenterPoint = new PointF(W/2f, H/2f);
                    vg.CenterColor = Color.FromArgb(0,0,0,0);
                    vg.SurroundColors = new[] { Color.FromArgb((int)F(s,"vignetteAlpha",70), 0,0,0) };
                    g.FillRectangle(vg, 0, 0, W, H);
                }
            }

            bmp.Save(outPng, ImageFormat.Png);
        }
        return sb.ToString();
    }
}
'@
Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Drawing

$png = Join-Path $OutDir "$Name.png"
$rawZones = [SkinBaker]::Build($S, $png)

# emit zones.lua
$W = if ($S.ContainsKey("bakeW")) { [int]$S["bakeW"] } else { 1920 }
$H = if ($S.ContainsKey("bakeH")) { [int]$S["bakeH"] } else { 1080 }
$lua = New-Object System.Text.StringBuilder
[void]$lua.AppendLine("-- Generado por tools/skin_gen/generate_skin.ps1. NO editar a mano.")
[void]$lua.AppendLine("-- Pasar a KeyasUI.registerSkin(id, { chromePath = ..., spec = require(este) }).")
[void]$lua.AppendLine("return {")
[void]$lua.AppendLine("  bakeW = $W, bakeH = $H,")
[void]$lua.AppendLine("  zones = {")
foreach ($line in ($rawZones -split "`r?`n" | Where-Object { $_.Trim() -ne "" })) {
    $p = $line.Trim() -split "\s+"
    [void]$lua.AppendLine("    $($p[0]) = { $($p[1]), $($p[2]), $($p[3]), $($p[4]) },")
}
[void]$lua.AppendLine("  },")
[void]$lua.AppendLine("}")
$zpath = Join-Path $OutDir "zones.lua"
[System.IO.File]::WriteAllText($zpath, $lua.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "skin  -> $png"
Write-Host "zones -> $zpath"
