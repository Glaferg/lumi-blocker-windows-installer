using System;
using System.Diagnostics;
using System.IO;

class Program
{
    static int Main(string[] args)
    {
        string name = Path.GetFileName(Process.GetCurrentProcess().MainModule.FileName).ToLowerInvariant();
        if (name.IndexOf("setup") >= 0) return Setup(args);
        return Ollama(args);
    }

    static int Setup(string[] args)
    {
        bool silent = false;
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i].IndexOf("VERYSILENT", StringComparison.OrdinalIgnoreCase) >= 0) silent = true;
        }
        if (!silent) return 2;
        string dir = Environment.GetEnvironmentVariable("LUMI_OLLAMA_DIR");
        if (string.IsNullOrEmpty(dir))
        {
            dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Ollama");
        }
        Directory.CreateDirectory(dir);
        string dest = Path.Combine(dir, "ollama.exe");
        File.Copy(Process.GetCurrentProcess().MainModule.FileName, dest, true);
        File.WriteAllText(Path.Combine(dir, "setup-ok.txt"), "ok");
        string countPath = Path.Combine(dir, "setup-count.txt");
        int count = 0;
        if (File.Exists(countPath)) int.TryParse(File.ReadAllText(countPath).Trim(), out count);
        count += 1;
        File.WriteAllText(countPath, count.ToString());
        Console.WriteLine("fake setup installed");
        return 0;
    }

    static int Ollama(string[] args)
    {
        string dir = Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName);
        string models = Path.Combine(dir, "models");
        Directory.CreateDirectory(models);
        if (args.Length == 0) return 0;
        string cmd = args[0].ToLowerInvariant();
        if (cmd == "--version" || cmd == "-v")
        {
            Console.WriteLine("ollama version fake-ci");
            return 0;
        }
        if (cmd == "list")
        {
            string[] files = Directory.GetFiles(models, "*.ok");
            for (int i = 0; i < files.Length; i++)
            {
                Console.WriteLine(Path.GetFileNameWithoutExtension(files[i]));
            }
            return 0;
        }
        if (cmd == "pull")
        {
            if (args.Length < 2) return 3;
            string exitVar = Environment.GetEnvironmentVariable("LUMI_FAKE_PULL_EXIT");
            int exitCode;
            if (!string.IsNullOrEmpty(exitVar) && int.TryParse(exitVar, out exitCode) && exitCode != 0)
            {
                Console.Error.WriteLine("fake pull failed");
                return exitCode;
            }
            File.WriteAllText(Path.Combine(models, args[1] + ".ok"), "tiny");
            string countPath = Path.Combine(dir, "pull-count.txt");
            int count = 0;
            if (File.Exists(countPath)) int.TryParse(File.ReadAllText(countPath).Trim(), out count);
            count += 1;
            File.WriteAllText(countPath, count.ToString());
            Console.WriteLine("pull " + args[1]);
            return 0;
        }
        if (cmd == "app" || cmd == "serve")
        {
            string origin = Environment.GetEnvironmentVariable("OLLAMA_ORIGINS") ?? "";
            File.WriteAllText(Path.Combine(dir, "backend-started.txt"), origin);
            while (true) System.Threading.Thread.Sleep(1000);
        }
        Console.Error.WriteLine("unknown");
        return 4;
    }
}
