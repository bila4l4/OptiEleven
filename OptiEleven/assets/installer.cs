// OptiEleven - app installer (Ninite style). Template: OptiEleven fills in the app list and the texts
// (the double-underscore markers below), then compiles it with the C# compiler that ships with Windows.
using System;
using System.Diagnostics;
using System.Drawing;
using System.Threading;
using System.Windows.Forms;
[assembly: System.Reflection.AssemblyTitle("OptiEleven app installer")]
[assembly: System.Reflection.AssemblyProduct("OptiEleven")]
[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

static class Program {
    public static string[][] Apps = new string[][] {
__APPS__
    };
    public static string TTitle = "__TITLE__", TIntro = "__INTRO__", TCheck = "__CHECK__", TInstalling = "__INSTALLING__", TDone = "__DONE__",
        TAlready = "__ALREADY__", TFail = "__FAIL__", TWait = "__WAIT__", TSummary = "__SUMMARY__", TReady = "__READY__", TClose = "__CLOSE__", TNoWinget = "__NOWINGET__";

    // Prebuilt copy (native\OptiEleven-Apps.exe, made by build/Build.ps1): the panel appends the list and the texts
    // to the end of the exe instead of compiling it on the user's PC. Layout: UTF-8 text, Int32 length, Magic.
    // Text: one "T" line with the 12 texts in the order above, then one "A<tab>id<tab>name<tab>args" line per app.
    const string Magic = "OPTIELEVEN-APPS1";
    static void LoadAppended() {
        byte[] all;
        try { all = System.IO.File.ReadAllBytes(Application.ExecutablePath); } catch { return; }
        byte[] magic = System.Text.Encoding.ASCII.GetBytes(Magic);
        int n = all.Length - magic.Length;
        if (n < 4) return;
        for (int i = 0; i < magic.Length; i++) if (all[n + i] != magic[i]) return;
        int len = BitConverter.ToInt32(all, n - 4);
        if (len <= 0 || len > n - 4) return;
        string text = System.Text.Encoding.UTF8.GetString(all, n - 4 - len, len);
        var apps = new System.Collections.Generic.List<string[]>();
        foreach (string line in text.Split('\n')) {
            string[] f = line.Split('\t');
            if (f[0] == "A" && f.Length == 4) apps.Add(new string[] { f[1], f[2], f[3] });
            else if (f[0] == "T" && f.Length == 13) {
                TTitle = f[1]; TIntro = f[2]; TCheck = f[3]; TInstalling = f[4]; TDone = f[5]; TAlready = f[6];
                TFail = f[7]; TWait = f[8]; TSummary = f[9]; TReady = f[10]; TClose = f[11]; TNoWinget = f[12];
            }
        }
        Apps = apps.ToArray();
    }

    [STAThread]
    static void Main(string[] args) {
        LoadAppended();
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        bool quit = args.Length > 0 && args[0] == "-quit-when-done";
        Application.Run(new InstallerForm(quit));
    }
}

class InstallerForm : Form {
    static readonly Color Bg = Color.FromArgb(9, 9, 13), Card = Color.FromArgb(17, 17, 23), Ink = Color.FromArgb(237, 237, 242),
        Muted = Color.FromArgb(138, 138, 156), Accent = Color.FromArgb(124, 92, 255), Good = Color.FromArgb(74, 222, 128), Bad = Color.FromArgb(248, 113, 113);
    Label header, sub;
    ProgressBar bar;
    Button close;
    Label[] states;
    bool quitWhenDone;

    public InstallerForm(bool quitWhenDone) {
        this.quitWhenDone = quitWhenDone;
        Text = Program.TTitle; BackColor = Bg; ForeColor = Ink; Font = new Font("Segoe UI", 10f);
        FormBorderStyle = FormBorderStyle.FixedSingle; MaximizeBox = false; StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
        int w = 620;
        header = new Label { Text = Program.TTitle, Font = new Font("Segoe UI Semibold", 14f), AutoSize = false, AutoEllipsis = true, Bounds = new Rectangle(24, 16, w - 48, 34) };
        sub = new Label { Text = string.Format(Program.TIntro, Program.Apps.Length), ForeColor = Muted, AutoSize = false, AutoEllipsis = true, Bounds = new Rectangle(24, 54, w - 48, 26) };
        bar = new ProgressBar { Bounds = new Rectangle(24, 88, w - 48, 8), Maximum = Program.Apps.Length, Style = ProgressBarStyle.Continuous };
        Controls.Add(header); Controls.Add(sub); Controls.Add(bar);
        var list = new Panel { Bounds = new Rectangle(24, 110, w - 48, Math.Min(Program.Apps.Length, 12) * 34 + 8), AutoScroll = true, BackColor = Card };
        states = new Label[Program.Apps.Length];
        for (int i = 0; i < Program.Apps.Length; i++) {
            var name = new Label { Text = Program.Apps[i][1], AutoSize = false, Bounds = new Rectangle(14, 8 + i * 34, 250, 28), TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true };
            states[i] = new Label { Text = Program.TWait, ForeColor = Muted, AutoSize = false, Bounds = new Rectangle(270, 8 + i * 34, w - 48 - 290, 28), TextAlign = ContentAlignment.MiddleRight, AutoEllipsis = true };
            list.Controls.Add(name); list.Controls.Add(states[i]);
        }
        Controls.Add(list);
        close = new Button { Text = Program.TClose, Enabled = false, FlatStyle = FlatStyle.Flat, BackColor = Accent, ForeColor = Color.White,
            Font = new Font("Segoe UI Semibold", 10f), Bounds = new Rectangle(w - 24 - 140, list.Bottom + 16, 140, 38) };
        close.FlatAppearance.BorderSize = 0;
        close.Click += delegate { Close(); };
        Controls.Add(close);
        ClientSize = new Size(w, close.Bottom + 20);
        Shown += delegate { new Thread(Work) { IsBackground = true }.Start(); };
    }

    void Ui(Action a) { if (IsHandleCreated) BeginInvoke(a); }
    void SetState(int i, string text, Color c) { Ui(delegate { states[i].Text = text; states[i].ForeColor = c; }); }

    static int Winget(string args) {
        var psi = new ProcessStartInfo("winget", args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        using (var p = Process.Start(psi)) {
            p.OutputDataReceived += delegate { };
            p.ErrorDataReceived += delegate { };
            p.BeginOutputReadLine(); p.BeginErrorReadLine();
            p.WaitForExit();
            return p.ExitCode;
        }
    }

    void Work() {
        try { Winget("--version"); }
        catch { Ui(delegate { sub.Text = Program.TNoWinget; sub.ForeColor = Bad; close.Enabled = true; }); return; }
        int ok = 0, had = 0, bad = 0;
        for (int i = 0; i < Program.Apps.Length; i++) {
            string id = Program.Apps[i][0], extra = Program.Apps[i][2];
            SetState(i, Program.TCheck, Muted);
            int code = Winget("list --id \"" + id + "\" -e --accept-source-agreements --disable-interactivity");
            if (code == 0) { SetState(i, Program.TAlready, Muted); had++; }
            else {
                SetState(i, Program.TInstalling, Accent);
                code = Winget("install --id \"" + id + "\" -e --silent --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity " + extra);
                if (code == 0) { SetState(i, Program.TDone, Good); ok++; }
                else if (code == -1978335189 || code == -1978335135) { SetState(i, Program.TAlready, Muted); had++; }
                else { SetState(i, string.Format(Program.TFail, code), Bad); bad++; }
            }
            int done = i + 1;
            Ui(delegate { bar.Value = done; });
        }
        Ui(delegate {
            header.Text = Program.TReady;
            sub.Text = string.Format(Program.TSummary, ok, had, bad); sub.ForeColor = bad > 0 ? Bad : Good;
            close.Enabled = true; close.Focus();
            if (quitWhenDone) Close();
        });
    }
}
