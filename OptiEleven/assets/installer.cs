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

    [STAThread]
    static void Main(string[] args) {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        bool quit = args.Length > 0 && args[0] == "-quit-when-done";
        Application.Run(new InstallerForm(quit));
    }
}

class InstallerForm : Form {
    static readonly Color Bg = Color.FromArgb(17, 15, 11), Card = Color.FromArgb(26, 24, 19), Ink = Color.FromArgb(238, 235, 229),
        Muted = Color.FromArgb(168, 164, 156), Accent = Color.FromArgb(255, 118, 67), Good = Color.FromArgb(134, 216, 151), Bad = Color.FromArgb(246, 154, 146);
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
        close = new Button { Text = Program.TClose, Enabled = false, FlatStyle = FlatStyle.Flat, BackColor = Accent, ForeColor = Bg,
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
