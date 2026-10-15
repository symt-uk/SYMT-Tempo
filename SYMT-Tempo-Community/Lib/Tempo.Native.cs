// SYMT Tempo v0.5 - small native helpers compiled at start-up by Add-Type.
// Optional: if compilation is blocked, Tempo runs without idle detection, the global hotkey,
// dark menus and Windows 11 rounded corners.
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace SymtTempo
{
    public static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

        [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr hwnd, string app, string idList);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);

        /// Seconds since the last keyboard/mouse input anywhere in the session.
        public static double IdleSeconds()
        {
            LASTINPUTINFO info = new LASTINPUTINFO();
            info.cbSize = (uint)Marshal.SizeOf(info);
            if (!GetLastInputInfo(ref info)) return 0;
            uint now = unchecked((uint)Environment.TickCount);
            return unchecked(now - info.dwTime) / 1000.0;
        }

        /// Windows 11 rounded window corners (DWMWA_WINDOW_CORNER_PREFERENCE = 33, ROUND = 2).
        public static bool RoundCorners(IntPtr hwnd)
        {
            try { int v = 2; return DwmSetWindowAttribute(hwnd, 33, ref v, 4) == 0; } catch { return false; }
        }

        /// Dark scrollbars for list boxes (Windows 10 1809+).
        public static void DarkScrollbars(IntPtr hwnd)
        {
            try { SetWindowTheme(hwnd, "DarkMode_Explorer", null); } catch { }
        }

        public static void Foreground(IntPtr hwnd) { try { SetForegroundWindow(hwnd); } catch { } }
    }

    /// Message-only window that raises Pressed when the registered global hotkey fires.
    public class HotKey : NativeWindow, IDisposable
    {
        [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
        const int Id = 0x5154;
        bool registered;
        public event EventHandler Pressed;

        public HotKey() { CreateHandle(new CreateParams()); }

        /// modifiers: 1 Alt, 2 Ctrl, 4 Shift, 8 Win. MOD_NOREPEAT is added automatically.
        public bool Register(uint modifiers, Keys key)
        {
            Unregister();
            registered = RegisterHotKey(Handle, Id, modifiers | 0x4000, (uint)key);
            return registered;
        }
        public void Unregister() { if (registered) { UnregisterHotKey(Handle, Id); registered = false; } }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0312 && Pressed != null) Pressed(this, EventArgs.Empty);
            base.WndProc(ref m);
        }
        public void Dispose() { Unregister(); DestroyHandle(); }
    }

    public class DarkColors : ProfessionalColorTable
    {
        public static Color Bg = Color.FromArgb(22, 29, 43);
        public static Color Sel = Color.FromArgb(36, 48, 68);
        public static Color Line = Color.FromArgb(44, 56, 77);
        public override Color MenuItemSelected { get { return Sel; } }
        public override Color MenuItemSelectedGradientBegin { get { return Sel; } }
        public override Color MenuItemSelectedGradientEnd { get { return Sel; } }
        public override Color MenuItemPressedGradientBegin { get { return Sel; } }
        public override Color MenuItemPressedGradientEnd { get { return Sel; } }
        public override Color MenuItemBorder { get { return Sel; } }
        public override Color MenuBorder { get { return Line; } }
        public override Color ToolStripDropDownBackground { get { return Bg; } }
        public override Color ImageMarginGradientBegin { get { return Bg; } }
        public override Color ImageMarginGradientMiddle { get { return Bg; } }
        public override Color ImageMarginGradientEnd { get { return Bg; } }
        public override Color SeparatorDark { get { return Line; } }
        public override Color SeparatorLight { get { return Bg; } }
        public override Color CheckBackground { get { return Sel; } }
        public override Color CheckSelectedBackground { get { return Sel; } }
        public override Color CheckPressedBackground { get { return Sel; } }
    }

    public class DarkRenderer : ToolStripProfessionalRenderer
    {
        public DarkRenderer() : base(new DarkColors()) { RoundedEdges = false; }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            // honour per-item colours (e.g. red "Delete"), fall back to light text
            Color fore = e.Item.ForeColor;
            if (fore.ToArgb() == SystemColors.ControlText.ToArgb() || fore.GetBrightness() < 0.35f) fore = Color.FromArgb(232, 238, 246);
            e.TextColor = e.Item.Enabled ? fore : Color.FromArgb(120, 134, 156);
            base.OnRenderItemText(e);
        }
        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
        {
            e.ArrowColor = Color.FromArgb(138, 155, 180);
            base.OnRenderArrow(e);
        }
        protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
        {
            Rectangle r = e.ImageRectangle;
            using (Font f = new Font("Segoe UI Symbol", 9f))
                TextRenderer.DrawText(e.Graphics, "\u2713", f, r, Color.FromArgb(79, 177, 251), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }
    }
}
