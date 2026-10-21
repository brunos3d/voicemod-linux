# Licenses and legal basis

This document explains what this project distributes, what it does not, and
why running it is compatible with the licenses involved. It is not legal
advice.

## What this repository distributes

Only original code written for this project, under the MIT License
([LICENSE](../LICENSE)):

- the installer and uninstaller scripts;
- the `voicemod-linux` launcher and the `voicemod-open-url` helper;
- `bridge/vadshim` (C source for a user-mode shim);
- `bridge/registry/voicemodvad.reg`;
- the desktop-integration template and packaging scripts.

Release bundles additionally contain the compiled shim (`avrt.dll`), which is
built from `bridge/vadshim/vadshim.c` in this repository. It is our own binary,
also under MIT. The build is reproducible and verified in CI.

## What this repository does NOT distribute

No Voicemod code, assets, trademarks or logos. No Proton, Wine or DXVK
binaries. These are obtained at install time from their official sources into
the user's home directory.

## Third-party software obtained at install time

### Voicemod (proprietary)

Voicemod is downloaded from Voicemod's own servers (`api.voicemod.net` and its
CDN) using the same update endpoint the official launcher uses. The user must
have a Voicemod account. This tool does not bypass payment, authentication,
licensing, or copy protection, and it never modifies the Voicemod binary on
disk.

Voicemod's [Terms of Use](https://www.voicemod.net/terms-of-use/), section 8,
prohibits reverse engineering "unless you have our written consent or
applicable law permits it". The interoperability work in this project relies on
that "applicable law permits it" carve-out:

- Voicemod S.L. is established in the European Union. Under
  **Directive 2009/24/EC on the legal protection of computer programs**,
  Article 6 permits reproducing and translating code where that is
  indispensable to achieve the interoperability of an independently created
  program with other programs, when done by a lawful user. Article 8 makes any
  contractual term contrary to Article 6 null and void.
- The bridge is an independently created program. It exists only to let the
  unmodified Voicemod application interoperate with the Linux audio stack
  (PipeWire) and the Wine/Proton environment, replacing the Windows kernel
  driver and system calls that Wine does not provide.
- Only the information necessary for that interoperability is used, and no
  Voicemod code is copied or redistributed.

Laws differ by country. In some jurisdictions the reverse-engineering carve-out
is narrower, and even where the acts are lawful, Voicemod may still treat use
outside Windows as a Terms violation and act on the account under section 14.
Each user decides whether to accept that.

### GE-Proton

Downloaded from the official release of
[GloriousEggroll/proton-ge-custom](https://github.com/GloriousEggroll/proton-ge-custom).
Proton's top-level code is under the **BSD 3-Clause License** (Valve
Corporation), which permits use and redistribution in source and binary form,
including outside Steam, with attribution. Proton bundles other components under
their own licenses, including Wine (**LGPL-2.1-or-later**), DXVK (**zlib**) and
vkd3d-proton (**LGPL-2.1 / zlib**). This project does not redistribute Proton;
it downloads the official release and runs it. The GE-Proton checksum is
verified after download.

## Build tools (not bundled)

Building the shim uses `clang`/`lld` (**Apache-2.0 with LLVM exceptions**) and
the Wine development headers and `winedump` (**LGPL-2.1-or-later**). These are
build-time only and are not part of releases.

## Trademarks

"Voicemod" is a trademark of Voicemod S.L. It is used here only to identify the
software this tool runs. This project is not affiliated with, endorsed by, or
sponsored by Voicemod S.L.
