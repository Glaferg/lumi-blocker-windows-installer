# Lumi for Windows

Lumi Focus can close distracting tabs. This setup prepares Thorough mode on Windows: a small helper Firefox can talk to, plus Ollama and a Gemma model that stay on this computer.

It is meant for someone who does not have developer tools installed. It does not need administrator rights. It only changes the Windows user who runs it.

## For testers

1. Unzip the folder.
2. Double-click **Install Lumi**.
3. Read the short note and choose **Continue**.
4. Wait. The window names each step. Longer program output is saved in the Lumi folder, not shown on screen.
5. When you see a blue Lumi and **Close this tab and let's get started!**, close the window and open Firefox.

The download is large. Thorough mode keeps a model on this computer and needs a few gigabytes of free space.

If Firefox is missing or too old, setup still finishes and tells you what to do next. Install Firefox 115 or newer, add the Lumi Focus add-on, then run setup again so they can connect.

To bring back the last tab Lumi closed, press **Ctrl+Alt+S**. Firefox can also bring it back with **Ctrl+Shift+T**. If Ctrl+Alt+S does nothing, the note in the Lumi folder explains how to set it in Firefox. On some versions that shortcut belongs to the Debugger while developer tools are open.

To remove Lumi, open the Start menu and choose **Remove Lumi**. That removes Lumi's files and its Firefox registration. Ollama stays, because you might use it for something else. Setup can remove that too if you run it with `-Uninstall -RemoveOllama`.

Running setup again is safe. It keeps choices you already made and does not download the model a second time.

## What setup changes

- Files for this user, under `%LOCALAPPDATA%\Lumi`
- A Firefox helper registration for this user only (`lumi_focus`)
- The user setting `OLLAMA_ORIGINS`, with `moz-extension://*` added so the Firefox add-on can reach Ollama. Without that, Thorough mode quietly uses Balanced instead
- Ollama for this user, if it is not already installed, and the Gemma model `gemma3:4b`

Nothing is sent to Lumi. Page titles are not written to the helper log.

## Shared consent

The wording in `share/consent.txt` is what the Windows window shows before it downloads anything. A Mac installer should show that same file. This repository does not contain the Mac installer, so there was nothing there to patch.

## Helper defaults

`share/default-settings.json` is what a new install stores:

- Mode starts at Thorough, and falls back to Balanced if the model cannot be reached
- The model is `gemma3:4b` on `http://127.0.0.1:11434`
- Light mode keeps a page open at or below 0.17
- **Ctrl+Alt+S** on Windows reopens the last tab Lumi closed
- No personal data is collected, and page text is not sent off the computer

The extension project is not in this repository. Those values are the contract this helper serves. If the add-on has a newer cutoff, the add-on should keep its own copy.

`share/firefox-command.json` is the Firefox command the add-on should ship, with `Ctrl+Alt+S` suggested on Windows.

## Build

On Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File build\Build-Installer.ps1
```

That compiles `LumiHelper.exe` with the .NET Framework compiler that ships with Windows, copies the scripts, and writes `dist\LumiSetup-win.zip`.

GitHub Actions runs that build on `windows-latest`, then installs into a temporary folder, checks the helper registration and file layout, runs setup again, removes Lumi, and checks that the registration is gone. The workflow does not download the real Ollama app or the real Gemma model. It serves a tiny stand-in and still walks through the download, model, and startup steps.
