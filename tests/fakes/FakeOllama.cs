using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

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
            Thread worker = new Thread(Serve);
            worker.IsBackground = true;
            worker.Start();
            while (true) Thread.Sleep(1000);
        }
        Console.Error.WriteLine("unknown");
        return 4;
    }

    static void Serve()
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, 11434);
        listener.Server.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        bool started = false;
        for (int i = 0; i < 20; i++)
        {
            try
            {
                listener.Start();
                started = true;
                break;
            }
            catch
            {
                Thread.Sleep(250);
            }
        }
        if (!started) return;
        while (true)
        {
            TcpClient client = null;
            try
            {
                client = listener.AcceptTcpClient();
                NetworkStream stream = client.GetStream();
                stream.ReadTimeout = 3000;
                MemoryStream raw = new MemoryStream();
                byte[] buf = new byte[2048];
                string header = "";
                while (header.IndexOf("\r\n\r\n") < 0)
                {
                    int n = stream.Read(buf, 0, buf.Length);
                    if (n <= 0) break;
                    raw.Write(buf, 0, n);
                    header = Encoding.ASCII.GetString(raw.ToArray());
                    if (header.Length > 65536) break;
                }
                string requestOrigin = "";
                string[] lines = header.Split(new string[] { "\r\n" }, StringSplitOptions.None);
                for (int i = 0; i < lines.Length; i++)
                {
                    if (lines[i].StartsWith("Origin:", StringComparison.OrdinalIgnoreCase))
                    {
                        requestOrigin = lines[i].Substring(7).Trim();
                    }
                }
                string allowed = Environment.GetEnvironmentVariable("OLLAMA_ORIGINS") ?? "";
                bool ok = OriginAllowed(requestOrigin, allowed);
                string body = ok ? "{\"version\":\"fake\"}" : "{\"error\":\"origin\"}";
                byte[] payload = Encoding.UTF8.GetBytes(body);
                StringBuilder response = new StringBuilder();
                response.Append(ok ? "HTTP/1.1 200 OK\r\n" : "HTTP/1.1 403 Forbidden\r\n");
                if (ok) response.Append("Access-Control-Allow-Origin: ").Append(requestOrigin).Append("\r\n");
                response.Append("Content-Length: ").Append(payload.Length).Append("\r\n");
                response.Append("Connection: close\r\n\r\n");
                byte[] prefix = Encoding.ASCII.GetBytes(response.ToString());
                stream.Write(prefix, 0, prefix.Length);
                stream.Write(payload, 0, payload.Length);
                stream.Flush();
            }
            catch
            {
            }
            finally
            {
                if (client != null) client.Close();
            }
        }
    }

    static bool OriginAllowed(string origin, string allowed)
    {
        if (string.IsNullOrEmpty(origin) || string.IsNullOrEmpty(allowed)) return false;
        string[] parts = allowed.Split(',');
        for (int i = 0; i < parts.Length; i++)
        {
            string pattern = parts[i].Trim();
            if (pattern.Length == 0) continue;
            if (pattern == "*") return true;
            if (pattern.EndsWith("*"))
            {
                string prefix = pattern.Substring(0, pattern.Length - 1);
                if (origin.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return true;
            }
            else if (string.Equals(pattern, origin, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }
}
