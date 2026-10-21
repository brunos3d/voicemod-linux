# Contributing

Thanks for helping make Voicemod usable on more Linux setups. This tool was
built and tested on one configuration (Manjaro/Arch, GNOME on Wayland, PipeWire
1.6, GE-Proton11-1, NVIDIA). The most useful contributions right now are
reports and fixes for environments it has not been tried on.

## Especially wanted

- **KDE Plasma and other desktops.** The login flow opens a browser through
  `systemd-run --user` and a `voicemod:` URL handler. Confirm whether that
  works on your desktop, or what needs adjusting (`bin/voicemod-open-url`,
  `share/voicemod-linux.desktop.in`).
- **X11 sessions.** `voicemod-open-url` rebuilds the session environment for
  Wayland; check the X11 path.
- **PulseAudio-only (no PipeWire).** The virtual devices are created with
  `pactl load-module module-null-sink` / `module-remap-source`, which also work
  on PulseAudio. Verify and report.
- **AMD and Intel GPUs.** The black-window fix relies on DXVK in GE-Proton.
  Confirm it renders on non-NVIDIA GPUs.
- **Other distributions.** The installer maps package names for pacman, apt,
  dnf and zypper (`pkg_for` in `install.sh`). Add mappings for others.
- **The voice-load bug.** Some presets fail with
  `Error during string conversion ... to float`. If you can pin down the cause,
  that would help everyone.

## Development setup

```sh
git clone https://github.com/brunos3d/voicemod-linux
cd voicemod-linux
# build the shim (needs clang, lld, and the Wine headers in /usr/include/wine)
make -C bridge/vadshim
# install from this checkout instead of downloading a release bundle
./install.sh --local --prefix /tmp/vml-dev
```

Use `--prefix` to install to a throwaway location so you do not disturb a real
install. `VML_HOME=/tmp/vml-dev /tmp/vml-dev/bin/voicemod-linux doctor` inspects
it.

## Layout

```
install.sh / uninstall.sh   one-command install/uninstall (curl|bash capable)
bin/voicemod-linux          the launcher (run, update, kill, doctor, logs, ...)
bin/voicemod-open-url       opens the login browser outside Wine
bridge/vadshim/             the avrt.dll shim (C, no CRT) + reproducible Makefile
bridge/registry/            registry fragment for the post-login driver check
share/                      .desktop template
scripts/make-release.sh     builds the shim and packages the release bundle
docs/                       troubleshooting and license notes
.github/workflows/          CI: build+verify the shim, publish releases
```

## The shim

`bridge/vadshim/vadshim.c` builds into `avrt.dll` and is loaded by Wine in
place of its builtin avrt (`WINEDLLOVERRIDES=avrt=n,b`). It patches the running
process's `CreateFile`/`DeviceIoControl` imports to answer the `\\.\voicemodvad`
control device, and patches Wine's `IAudioSessionManager2` stubs. It links
without a C runtime and imports only the kernel32 functions listed in
`kernel32.def`. The build is reproducible; please keep it that way (`make -C
bridge/vadshim` twice must produce identical output). CI enforces this.

No Voicemod or Proton code or binaries belong in the repository or in commits.
The release bundle contains only our files plus the shim we compile.

## Reporting an issue

Include:

- `voicemod-linux doctor` output;
- distribution and version, desktop environment, session type (Wayland/X11);
- sound server (`pactl info | grep 'Server Name'`);
- GPU and driver;
- the relevant tail of the application log (see `docs/TROUBLESHOOTING.md`).

## Style

Shell is bash with `set -euo pipefail`. Keep scripts readable and dependency
light. Documentation avoids marketing language; prefer short, concrete
sentences with real commands and paths.
