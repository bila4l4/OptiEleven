// OptiEleven.exe - opens OptiEleven.ps1 (next to this exe) inside this process, with Windows PowerShell 5.1.
// No hidden powershell.exe, no -EncodedCommand and nothing embedded: the scripts stay in plain text beside the exe,
// so anyone (and any antivirus) can read exactly what runs. The manifest asks for administrator, like OptiEleven.cmd.
// Built by build/Build.ps1 with the C# compiler that ships with .NET Framework 4.8.
using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;
[assembly: System.Reflection.AssemblyTitle("OptiEleven")]
[assembly: System.Reflection.AssemblyProduct("OptiEleven")]
[assembly: System.Reflection.AssemblyDescription("Opens the OptiEleven panel (OptiEleven.ps1 in this folder)")]

static class Launcher {
    [STAThread]   // the panel is WPF, which needs a single-threaded apartment
    static int Main(string[] args) {
        string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "OptiEleven.ps1");
        try {
            if (!File.Exists(script)) throw new FileNotFoundException("OptiEleven.ps1 is missing from the folder of OptiEleven.exe: " + script);
            var iss = InitialSessionState.CreateDefault();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;   // this process only, like -ExecutionPolicy Bypass
            iss.ApartmentState = ApartmentState.STA;
            iss.ThreadOptions = PSThreadOptions.UseCurrentThread;
            using (var rs = RunspaceFactory.CreateRunspace(iss)) {
                rs.Open();
                using (var ps = PowerShell.Create()) {
                    ps.Runspace = rs;
                    ps.AddCommand(script);
                    // "-Page cleanup -NoGui" -> named parameters and switches, anything else positional
                    for (int i = 0; i < args.Length; i++) {
                        string a = args[i];
                        if (a.Length > 1 && a[0] == '-') {
                            string name = a.Substring(1).TrimEnd(':');
                            if (i + 1 < args.Length && !(args[i + 1].Length > 1 && args[i + 1][0] == '-')) ps.AddParameter(name, args[++i]);
                            else ps.AddParameter(name);
                        }
                        else ps.AddArgument(a);
                    }
                    ps.Invoke();
                }
            }
            return 0;
        }
        catch (Exception e) {
            var err = e as RuntimeException;
            string where = (err != null && err.ErrorRecord != null && err.ErrorRecord.InvocationInfo != null) ? "\n\n" + err.ErrorRecord.InvocationInfo.PositionMessage : "";
            MessageBox.Show("OptiEleven could not start.\n\n" + e.Message + where, "OptiEleven", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
