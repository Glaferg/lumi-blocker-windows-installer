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
                int headerEnd = header.IndexOf("\r\n\r\n");
                string head = headerEnd >= 0 ? header.Substring(0, headerEnd) : header;
                string requestBody = headerEnd >= 0 ? header.Substring(headerEnd + 4) : "";
                string[] lines = head.Split(new string[] { "\r\n" }, StringSplitOptions.None);
                string requestOrigin = "";
                string path = "";
                int contentLength = 0;
                if (lines.Length > 0)
                {
                    string[] requestParts = lines[0].Split(' ');
                    if (requestParts.Length > 1) path = requestParts[1];
                }
                for (int i = 0; i < lines.Length; i++)
                {
                    if (lines[i].StartsWith("Origin:", StringComparison.OrdinalIgnoreCase))
                    {
                        requestOrigin = lines[i].Substring(7).Trim();
                    }
                    if (lines[i].StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
                    {
                        int.TryParse(lines[i].Substring(15).Trim(), out contentLength);
                    }
                }
                while (requestBody.Length < contentLength)
                {
                    int n = stream.Read(buf, 0, buf.Length);
                    if (n <= 0) break;
                    requestBody += Encoding.ASCII.GetString(buf, 0, n);
                }
                string allowed = Environment.GetEnvironmentVariable("OLLAMA_ORIGINS") ?? "";
                bool show = path.IndexOf("/api/show", StringComparison.OrdinalIgnoreCase) >= 0;
                int status = 200;
                string body;
                string allowOrigin = "";
                if (show)
                {
                    string model = ExtractJsonString(requestBody, "model");
                    if (string.IsNullOrEmpty(model)) model = ExtractJsonString(requestBody, "name");
                    string folder = Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName);
                    string marker = Path.Combine(folder, "models", model + ".ok");
                    bool found = !string.IsNullOrEmpty(model) && File.Exists(marker);
                    status = found ? 200 : 404;
                    body = found
                        ? "{\"model\":\"" + model.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\",\"details\":{\"family\":\"gemma\"}}"
                        : "{\"error\":\"not ready\"}";
                }
                else
                {
                    bool ok = OriginAllowed(requestOrigin, allowed);
                    status = ok ? 200 : 403;
                    body = ok ? "{\"version\":\"fake\"}" : "{\"error\":\"origin\"}";
                    if (ok) allowOrigin = requestOrigin;
                }
                byte[] payload = Encoding.UTF8.GetBytes(body);
                StringBuilder response = new StringBuilder();
                response.Append("HTTP/1.1 ").Append(status).Append(status == 200 ? " OK\r\n" : " Result\r\n");
                if (allowOrigin.Length > 0) response.Append("Access-Control-Allow-Origin: ").Append(allowOrigin).Append("\r\n");
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

    static string ExtractJsonString(string body, string key)
    {
        if (string.IsNullOrEmpty(body) || string.IsNullOrEmpty(key)) return "";
        string token = "\"" + key + "\"";
        int at = body.IndexOf(token, StringComparison.OrdinalIgnoreCase);
        if (at < 0) return "";
        int colon = body.IndexOf(':', at + token.Length);
        if (colon < 0) return "";
        int open = body.IndexOf('"', colon + 1);
        if (open < 0) return "";
        int close = body.IndexOf('"', open + 1);
        if (close < 0) return "";
        return body.Substring(open + 1, close - open - 1);
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
