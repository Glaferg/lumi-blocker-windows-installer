function Initialize-LumiJson {
    if ('LumiJson' -as [type]) { return }
    Add-Type -ReferencedAssemblies System.Web.Extensions -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using System.Web.Script.Serialization;
public static class LumiJson {
    public static string Serialize(object value) {
        var ser = new JavaScriptSerializer();
        ser.MaxJsonLength = 1024 * 1024;
        return ser.Serialize(Unwrap(value));
    }
    public static Dictionary<string, object> Deserialize(string text) {
        var ser = new JavaScriptSerializer();
        ser.MaxJsonLength = 1024 * 1024;
        return ser.Deserialize<Dictionary<string, object>>(text);
    }
    static object Unwrap(object value) {
        if (value == null) return null;
        var type = value.GetType();
        if (type.FullName == "System.Management.Automation.PSObject") {
            PropertyInfo prop = type.GetProperty("BaseObject");
            object inner = prop == null ? null : prop.GetValue(value, null);
            if (inner == null || object.ReferenceEquals(inner, value)) return null;
            return Unwrap(inner);
        }
        if (value is string || value is ValueType) return value;
        IDictionary dict = value as IDictionary;
        if (dict != null) {
            var copy = new Dictionary<string, object>();
            foreach (DictionaryEntry entry in dict) {
                copy[Convert.ToString(entry.Key)] = Unwrap(entry.Value);
            }
            return copy;
        }
        IEnumerable enumerable = value as IEnumerable;
        if (enumerable != null) {
            var list = new ArrayList();
            foreach (object item in enumerable) list.Add(Unwrap(item));
            return list;
        }
        return Convert.ToString(value);
    }
}
'@
}

function Read-LumiJsonFile {
    param([string]$Path)
    Initialize-LumiJson
    $text = [System.IO.File]::ReadAllText($Path)
    return ,([LumiJson]::Deserialize($text))
}

function Write-LumiJsonFile {
    param(
        $Object,
        [string]$Path
    )
    Initialize-LumiJson
    $json = [LumiJson]::Serialize($Object)
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $json, $utf8)
}

function Initialize-LumiSettings {
    param(
        [string]$InstallRoot,
        [string]$Model
    )
    $defaultsPath = Join-Path $InstallRoot 'default-settings.json'
    $settingsPath = Join-Path $InstallRoot 'settings.json'
    $fresh = -not (Test-Path -LiteralPath $settingsPath)
    if ($fresh) {
        Copy-Item -LiteralPath $defaultsPath -Destination $settingsPath -Force
    }
    $settings = Read-LumiJsonFile -Path $settingsPath
    $defaults = Read-LumiJsonFile -Path $defaultsPath
    foreach ($key in @($defaults.Keys)) {
        if (-not $settings.ContainsKey($key) -or $null -eq $settings[$key]) {
            $settings[$key] = $defaults[$key]
        }
    }
    if ($fresh -and $Model) { $settings['model'] = $Model }
    Write-LumiJsonFile -Object $settings -Path $settingsPath
    return $settings
}

function Set-LumiSetting {
    param(
        [string]$InstallRoot,
        [string]$Name,
        $Value
    )
    $settingsPath = Join-Path $InstallRoot 'settings.json'
    $settings = Read-LumiJsonFile -Path $settingsPath
    $settings[$Name] = $Value
    Write-LumiJsonFile -Object $settings -Path $settingsPath
}
