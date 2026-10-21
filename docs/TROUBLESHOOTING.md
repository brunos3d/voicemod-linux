# Troubleshooting

Start with `voicemod-linux doctor`. It prints the install location, the
detected Proton build, the prefix, the audio server and whether Voicemod is
running. The application log is at
`~/.local/share/voicemod-linux/prefix/pfx/drive_c/users/steamuser/AppData/Local/VoicemodV3/logs/voicemod-desktop.log`
(or `voicemod-linux logs` to follow it live).

## The window is black

The UI is rendered by QtWebEngine, which shares D3D11 textures between
processes through NT handles. Stock Wine (10/11) does not implement that path,
so the window stays black. The fix is to use GE-Proton, whose Wine does.

- Confirm the launcher picked GE-Proton: `voicemod-linux doctor` should show a
  `GE-Proton...` path, not "Proton - Experimental" or system Wine.
- If only Valve's Proton is installed, install GE-Proton (ProtonUp-Qt, or let
  the installer download it) and run again.
- Force a specific build with `VOICEMOD_PROTON=/path/to/GE-Proton... voicemod-linux`.

## The login browser does not open

Clicking "Get Started" opens your default browser to the Voicemod login page.
A browser launched from inside Wine inherits Wine's blocked signal mask and a
partial environment and exits immediately, so `voicemod-open-url` starts the
browser outside Wine's process tree with `systemd-run --user`.

- Check that a default browser is set: `xdg-settings get default-web-browser`.
- Look at the wrapper log: `$XDG_RUNTIME_DIR/voicemod-open-url.log`.
- If you use a non-systemd session, the wrapper falls back to `xdg-open` with a
  rebuilt environment. Make sure `xdg-utils` is installed.

## After login the app does not come back

The login page ends with an "Open Voicemod" button that hands a `voicemod:`
link to the running app. That link is routed by a `.desktop` handler.

- Verify the handler: `xdg-mime query default x-scheme-handler/voicemod` should
  print `voicemod-linux.desktop`.
- Re-register it by running the installer again, or:
  `xdg-mime default voicemod-linux.desktop x-scheme-handler/voicemod`.
- Note the link has no `//` (it looks like `voicemod:login_token&code=...`);
  that is expected.

## Several Voicemod windows / tray icons appear

Each start with the launcher flag creates a new instance. `voicemod-linux`
avoids this: if an instance is already running it only focuses the window.
If you still have duplicates, run `voicemod-linux kill` and start once.

## It asks to install the driver, then fails

Voicemod checks for its kernel audio driver after login and may show
"Voicemod can't find its driver installed. Would you like to install it now?".
Choose **No**. The Windows kernel driver cannot run under Wine. The bridge
already provides the virtual devices and answers the driver's control channel,
so the app works without installing anything. Clicking Yes fails and closes
the app.

## No virtual microphone in Discord / OBS / games

The processed voice is exposed as a PipeWire source named "Voicemod Virtual
Audio Device (WDM)".

- List it: `pactl list short sources | grep voicemod_mic`.
- If it is missing, create the devices: `voicemod-linux setup-audio`.
- In the other app, pick "Voicemod Virtual Audio Device (WDM)" as the input,
  not your hardware mic.
- In the Voicemod onboarding, select your real hardware microphone and
  headphones, not "PulseAudio Input" or a "Monitor of ..." device.

## The virtual mic is silent

- Confirm Voicemod is capturing: the log shows `topology=kCaptureMode` and
  `Audio streaming has been successfully started`.
- Make sure a voice is active (the "Voice Changer" toggle is on) and that you
  selected your real microphone as the input inside Voicemod.
- Quick check: `parecord -d voicemod_mic out.wav` while speaking, then play
  `out.wav` back.

## A specific voice fails ("Voice couldn't be selected")

Some presets fail to load with `Error during string conversion ... to float`
in the closed-source audio SDK (seen with "Clean Mic" and "Banana", for
example). Most voices load fine. Pick a different voice. This is a known,
unresolved limitation, not a setup problem.

## Audio is choppy or has xruns

- Prefer a 48000 Hz setup; the virtual devices are created at 48 kHz.
- Raise your PipeWire quantum if needed (for example
  `PIPEWIRE_QUANTUM=1024/48000`), or set a larger default in
  `~/.config/pipewire/pipewire.conf.d/`.
- Close other heavy GPU/audio apps; QtWebEngine plus DXVK uses the GPU.

## "GE-Proton not found"

The installer downloads GE-Proton, or reuses one from Steam. If detection
fails, pass the path explicitly:
`VOICEMOD_PROTON=/home/you/.steam/steam/compatibilitytools.d/GE-Proton9-20 voicemod-linux`.

## Start fresh

Remove the prefix to recreate it on next start:
`rm -rf ~/.local/share/voicemod-linux/prefix` (your login and settings live in
the prefix, so you will log in again). To remove everything, run the uninstall
command in the README.

## Still stuck?

Open an issue with the output of `voicemod-linux doctor`, your distribution,
desktop and sound server, and the tail of the application log. See
[CONTRIBUTING.md](../CONTRIBUTING.md).
