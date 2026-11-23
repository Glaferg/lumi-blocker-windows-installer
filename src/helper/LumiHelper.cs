using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Web.Script.Serialization;

[assembly: AssemblyTitle("Lumi Helper")]
[assembly: AssemblyProduct("Lumi")]
[assembly: AssemblyFileVersion("1.0.0.0")]
[assembly: AssemblyVersion("1.0.0.0")]

class Program
{
    static int Main()
    {
        try
        {
            Run();
            return 0;
        }
        catch (Exception ex)
        {
            Log("fatal " + ex.GetType().Name);
            return 1;
        }
    }

    static void Run()
    {
        Stream stdin = Console.OpenStandardInput();
        Stream stdout = Console.OpenStandardOutput();
        while (true)
        {
            byte[] lenBuf = ReadExact(stdin, 4);
            if (lenBuf == null) return;
            int len = BitConverter.ToInt32(lenBuf, 0);
            if (len <= 0 || len > 1024 * 1024) return;
            byte[] body = ReadExact(stdin, len);
            if (body == null) return;
            string json = Encoding.UTF8.GetString(body);
            string response = Handle(json);
            byte[] payload = Encoding.UTF8.GetBytes(response);
            byte[] outLen = BitConverter.GetBytes(payload.Length);
            stdout.Write(outLen, 0, 4);
            stdout.Write(payload, 0, payload.Length);
            stdout.Flush();
        }
    }

    static string Handle(string json)
    {
        try
        {
            var ser = new JavaScriptSerializer();
            ser.MaxJsonLength = 1024 * 1024;
            var msg = ser.Deserialize<Dictionary<string, object>>(json);
            string action = "ping";
            if (msg != null && msg.ContainsKey("action") && msg["action"] != null)
            {
                action = msg["action"].ToString();
            }
            Log("action " + action);
            Dictionary<string, object> settings = LoadSettings();
            if (action == "ping" || action == "getSettings")
            {
                var ok = new Dictionary<string, object>();
                ok["ok"] = true;
                ok["name"] = "lumi_focus";
                ok["shortcut"] = ShortcutForWindows(settings);
                ok["mode"] = StringSetting(settings, "mode", "thorough");
                ok["fallbackMode"] = StringSetting(settings, "fallbackMode", "balanced");
                ok["settings"] = settings;
                return ser.Serialize(ok);
            }
            if (action == "classify")
            {
                return Classify(ser, settings, msg);
            }
            var unknown = new Dictionary<string, object>();
            unknown["ok"] = false;
            unknown["error"] = "unknown-action";
            return ser.Serialize(unknown);
        }
        catch (Exception ex)
        {
            Log("handle " + ex.GetType().Name);
            return "{\"ok\":false,\"error\":\"helper-error\"}";
        }
    }

    static string Classify(JavaScriptSerializer ser, Dictionary<string, object> settings, Dictionary<string, object> msg)
    {
        string mode = StringSetting(settings, "mode", "thorough");
        string fallback = StringSetting(settings, "fallbackMode", "balanced");
        if (mode != "thorough")
        {
            return Decision(ser, mode, false, "keep");
        }
        string baseUrl = StringSetting(settings, "ollamaBaseUrl", "http://127.0.0.1:11434");
        if (msg != null && msg.ContainsKey("ollamaBaseUrl") && msg["ollamaBaseUrl"] != null)
        {
            baseUrl = msg["ollamaBaseUrl"].ToString();
        }
        if (!IsLoopback(baseUrl))
        {
            Log("classify skipped non-local model");
            return Decision(ser, fallback, true, "keep");
        }
        string model = StringSetting(settings, "model", "gemma3:4b");
        string title = Clip(msg, "title", 300);
        string url = Clip(msg, "url", 300);
        string prompt = "You help a focus app. Reply with one word: close or keep. close means the page is a distraction. keep means it is fine.\nTitle: "
            + title + "\nURL: " + url;
        try
        {
            string content = AskModel(baseUrl, model, prompt, TimeoutSeconds(settings));
            string word = (content ?? "").Trim().ToLowerInvariant();
            string decision = word.StartsWith("close") ? "close" : "keep";
            return Decision(ser, "thorough", false, decision);
        }
        catch (Exception ex)
        {
            Log("classify fallback " + ex.GetType().Name);
            return Decision(ser, fallback, true, "keep");
        }
    }

    static string Decision(JavaScriptSerializer ser, string mode, bool fallback, string decision)
    {
        var obj = new Dictionary<string, object>();
        obj["ok"] = true;
        obj["mode"] = mode;
        obj["fallback"] = fallback;
        obj["decision"] = decision;
        return ser.Serialize(obj);
    }

    static string AskModel(string baseUrl, string model, string prompt, int timeoutSeconds)
    {
        string root = baseUrl.TrimEnd('/');
        string endpoint = root + "/api/chat";
        var ser = new JavaScriptSerializer();
        var message = new Dictionary<string, object>();
        message["role"] = "user";
        message["content"] = prompt;
        var messages = new object[] { message };
        var body = new Dictionary<string, object>();
        body["model"] = model;
        body["messages"] = messages;
        body["stream"] = false;
        string payload = ser.Serialize(body);
        System.Net.ServicePointManager.Expect100Continue = false;
        using (var client = new HttpClient())
        {
            client.Timeout = TimeSpan.FromSeconds(timeoutSeconds);
            var http = new StringContent(payload, Encoding.UTF8, "application/json");
            var response = client.PostAsync(endpoint, http).Result;
            string text = response.Content.ReadAsStringAsync().Result;
            if (!response.IsSuccessStatusCode)
            {
                throw new IOException("model-http");
            }
            var parsed = ser.Deserialize<Dictionary<string, object>>(text);
            if (parsed == null || !parsed.ContainsKey("message") || parsed["message"] == null)
            {
                throw new IOException("model-shape");
            }
            var inner = parsed["message"] as Dictionary<string, object>;
            if (inner == null || !inner.ContainsKey("content") || inner["content"] == null)
            {
                throw new IOException("model-shape");
            }
            return inner["content"].ToString();
        }
    }

    static bool IsLoopback(string url)
    {
        Uri u;
        if (!Uri.TryCreate(url, UriKind.Absolute, out u)) return false;
        if (u.Scheme != "http" && u.Scheme != "https") return false;
        if (u.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase)) return true;
        if (u.Host == "127.0.0.1") return true;
        if (u.Host == "::1") return true;
        return false;
    }

    static int TimeoutSeconds(Dictionary<string, object> settings)
    {
        int value = 25;
        if (settings != null && settings.ContainsKey("requestTimeoutSeconds") && settings["requestTimeoutSeconds"] != null)
        {
            try { value = Convert.ToInt32(settings["requestTimeoutSeconds"]); } catch { value = 25; }
        }
        if (value < 1) value = 1;
        if (value > 30) value = 30;
        return value;
    }

    static string Clip(Dictionary<string, object> msg, string key, int max)
    {
        if (msg == null || !msg.ContainsKey(key) || msg[key] == null) return "";
        string text = msg[key].ToString();
        if (text.Length > max) return text.Substring(0, max);
        return text;
    }

    static Dictionary<string, object> LoadSettings()
    {
        string dir = AppDir();
        var defaults = ReadObject(Path.Combine(dir, "default-settings.json"));
        var settings = ReadObject(Path.Combine(dir, "settings.json"));
        if (defaults == null && settings == null)
        {
            throw new IOException("settings-missing");
        }
        if (defaults == null) defaults = new Dictionary<string, object>();
        if (settings == null) settings = new Dictionary<string, object>();
        foreach (var kv in defaults)
        {
            if (!settings.ContainsKey(kv.Key) || settings[kv.Key] == null)
            {
                settings[kv.Key] = kv.Value;
            }
        }
        return settings;
    }

    static Dictionary<string, object> ReadObject(string path)
    {
        if (!File.Exists(path)) return null;
        string text = File.ReadAllText(path);
        var ser = new JavaScriptSerializer();
        ser.MaxJsonLength = 1024 * 1024;
        return ser.Deserialize<Dictionary<string, object>>(text);
    }

    static string ShortcutForWindows(Dictionary<string, object> settings)
    {
        if (settings == null || !settings.ContainsKey("reopenLastClosedShortcut") || settings["reopenLastClosedShortcut"] == null)
        {
            return "Ctrl+Alt+S";
        }
        var map = settings["reopenLastClosedShortcut"] as Dictionary<string, object>;
        if (map != null && map.ContainsKey("windows") && map["windows"] != null)
        {
            return map["windows"].ToString();
        }
        return settings["reopenLastClosedShortcut"].ToString();
    }

    static string StringSetting(Dictionary<string, object> settings, string key, string fallback)
    {
        if (settings == null || !settings.ContainsKey(key) || settings[key] == null) return fallback;
        return settings[key].ToString();
    }

    static string AppDir()
    {
        return Path.GetDirectoryName(typeof(Program).Assembly.Location);
    }

    static void Log(string line)
    {
        try
        {
            string path = Path.Combine(AppDir(), "logs", "helper.log");
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.AppendAllText(path, DateTime.UtcNow.ToString("o") + " " + line + "\r\n");
        }
        catch
        {
        }
    }

    static byte[] ReadExact(Stream stream, int count)
    {
        byte[] buf = new byte[count];
        int got = 0;
        while (got < count)
        {
            int n = stream.Read(buf, got, count - got);
            if (n <= 0)
            {
                if (got == 0) return null;
                return null;
            }
            got += n;
        }
        return buf;
    }
}
