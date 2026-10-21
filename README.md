# voicemod-linux

Run the official Windows build of [Voicemod](https://www.voicemod.net/) on
Linux through Proton. One command sets up Proton, downloads Voicemod from
Voicemod's own servers, and wires the app into PipeWire so your changed voice
shows up as a normal microphone that Discord, OBS, games and browsers can use.

English | [Português](README.pt-BR.md)

> ## ⚠️ Unofficial compatibility tool
>
> This project is **not affiliated with, endorsed by, or sponsored by
> Voicemod**. It is a compatibility layer that runs the unmodified Windows
> application on Linux.
>
> **It does not crack, pirate, or bypass payment, login, or any copy
> protection.** You use your own Voicemod account. No Voicemod or Proton
> binaries are distributed here: the Voicemod app is downloaded from
> Voicemod's servers and GE-Proton from its official GitHub release, both into
> your home directory at install time.
>
> Running Voicemod this way may still conflict with Voicemod's
> [Terms of Use](https://www.voicemod.net/terms-of-use/) and could put an
> account at risk. Use it at your own discretion. See [docs/LICENSES.md](docs/LICENSES.md).

## Install

Nothing to clone. Run one of these:

```sh
# curl
curl -fsSL https://raw.githubusercontent.com/BrunoS3D/voicemod-linux/main/install.sh | bash

# wget
wget -qO- https://raw.githubusercontent.com/BrunoS3D/voicemod-linux/main/install.sh | bash

# npx (Node)
npx github:BrunoS3D/voicemod-linux
```

The installer downloads a small bundle into a temporary directory, installs the
launcher and bridge into `~/.local/share/voicemod-linux`, and removes the
temporary copy. It walks you through each step in the terminal. Then start
Voicemod from your application menu or run `voicemod-linux`.

### What it needs

The installer checks for these and offers to install anything missing with
your package manager (pacman, apt, dnf or zypper):

- `curl` or `wget`, `unzip`, `python3`
- `pactl` (from `pipewire-pulse` / `pulseaudio-utils`)
- a working PipeWire (or PulseAudio) sound server

It also needs GE-Proton. If you already have one from Steam it is reused;
otherwise the latest GE-Proton is downloaded from GitHub and its checksum is
verified. Optional: `icoutils` (for a nicer menu icon).

## First run

- During onboarding, pick your real microphone and headphones. Do not choose
  "PulseAudio Input" or a "Monitor of ..." device as the microphone.
- In Discord, OBS or a game, select the input named
  **Voicemod Virtual Audio Device (WDM)**.
- If a dialog offers to install the Voicemod driver, choose **No**. The real
  kernel driver cannot run under Wine, and that dialog closes the app.

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) if something does not work.

## Commands

```sh
voicemod-linux            # start, or focus the running instance
voicemod-linux update     # download the current Voicemod release
voicemod-linux kill       # stop Voicemod and its wineserver
voicemod-linux doctor     # print the detected setup
voicemod-linux logs       # follow the Voicemod log
voicemod-linux setup-audio / teardown-audio
voicemod-linux winecfg
```

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/BrunoS3D/voicemod-linux/main/uninstall.sh | bash
```

This removes `~/.local/share/voicemod-linux`, the launcher symlink, the menu
entry and the `voicemod:` handler. Your Voicemod account and any Steam
GE-Proton are left untouched.

## Tested on

- Manjaro and Arch Linux, kernel 6.18
- GNOME on Wayland
- PipeWire 1.6 (with `pipewire-pulse`)
- GE-Proton11-1
- x86-64 with AVX, NVIDIA GPU (DXVK)

It should work on other distributions and desktops with PipeWire. Reports and
fixes for KDE Plasma, X11, PulseAudio-only setups, AMD/Intel GPUs and other
configurations are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## How it works

`Voicemod.exe` is a Qt 6 program: the UI is a Vue bundle rendered by
QtWebEngine, and audio runs in a native PortAudio/WASAPI engine that, on
Windows, talks to a kernel driver (`voicemodvad.sys`) exposing a virtual
microphone and speaker plus a control device at `\\.\voicemodvad`.

Wine cannot run that kernel driver, so each Windows-only piece is replaced:

| Windows | Linux replacement |
| --- | --- |
| `voicemodvad.sys` render/capture endpoints | PipeWire null sink `voicemod_vad` and remap source `voicemod_mic`, both named "Voicemod Virtual Audio Device (WDM)" |
| `\\.\voicemodvad` control device | `bridge/vadshim`, built as `avrt.dll` and loaded from the app folder |
| Driver entry seen by SetupAPI after login | `bridge/registry/voicemodvad.reg` |
| D3D11 texture sharing for QtWebEngine | DXVK and the Wine in GE-Proton (stock Wine shows a black window) |
| Browser login and the `voicemod:` callback | `bin/voicemod-open-url` plus a `.desktop` handler |

The application binary on disk is never modified. The shim loads as `avrt.dll`
through `WINEDLLOVERRIDES=avrt=n,b`, answers `\\.\voicemodvad` by patching the
running process's imports, and patches `IAudioSessionManager2` (which Wine
stubs out) so device setup succeeds. See `bridge/vadshim/vadshim.c` for details.

## Build from source

The release bundle ships a prebuilt shim. To build it yourself you need
`clang`, `lld` and the Wine development headers:

```sh
git clone https://github.com/BrunoS3D/voicemod-linux
cd voicemod-linux
make -C bridge/vadshim      # produces bridge/vadshim/avrt.dll
./install.sh --local        # install from this checkout
```

The build is reproducible (`lld-link /Brepro`); CI verifies this on every
change. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Known limitations

- A few voice presets fail to load with `Error during string conversion ... to
  float` inside the closed-source audio SDK. Most voices work. Cause unknown;
  it is not a locale issue.
- The app cannot set the virtual device as the system default or hide it
  (`IPolicyConfig` is not in Wine). Select the device in each application.
- Per-device peak meters and the "connected apps" indicator stay empty.
- Auto-update is off; use `voicemod-linux update`.

## License

This project's own code is MIT (see [LICENSE](LICENSE)). Third-party components
and the legal basis are described in [NOTICE](NOTICE) and
[docs/LICENSES.md](docs/LICENSES.md).
