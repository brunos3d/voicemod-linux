# voicemod-linux

Rode o build oficial do [Voicemod](https://www.voicemod.net/) para Windows no
Linux através do Proton. Um comando configura o Proton, baixa o Voicemod dos
próprios servidores da Voicemod e integra o app ao PipeWire, de modo que a sua
voz modificada aparece como um microfone comum que o Discord, o OBS, jogos e
navegadores conseguem usar.

[English](README.md) | Português

> ## ⚠️ Ferramenta de compatibilidade não oficial
>
> Este projeto **não tem vínculo com a Voicemod, nem é endossado ou
> patrocinado por ela**. É uma camada de compatibilidade que roda o aplicativo
> Windows sem modificá-lo.
>
> **Ele não faz crack, não pirateia e não burla pagamento, login ou qualquer
> proteção.** Você usa a sua própria conta Voicemod. Nenhum binário da Voicemod
> ou do Proton é distribuído aqui: o app da Voicemod é baixado dos servidores
> da Voicemod e o GE-Proton da sua release oficial no GitHub, ambos para o seu
> diretório pessoal, no momento da instalação.
>
> Rodar o Voicemod desta forma ainda pode conflitar com os
> [Termos de Uso](https://www.voicemod.net/terms-of-use/) da Voicemod e colocar
> uma conta em risco. Use por sua conta e risco. Veja
> [docs/LICENSES.md](docs/LICENSES.md).

## Instalação

Nada para clonar. Rode um destes:

```sh
# curl
curl -fsSL https://raw.githubusercontent.com/brunos3d/voicemod-linux/main/install.sh | bash

# wget
wget -qO- https://raw.githubusercontent.com/brunos3d/voicemod-linux/main/install.sh | bash

# npx (Node)
npx github:brunos3d/voicemod-linux
```

O instalador baixa um pacote pequeno para um diretório temporário, instala o
launcher e a bridge em `~/.local/share/voicemod-linux` e apaga a cópia
temporária. Ele guia você por cada passo no terminal. Depois é só abrir o
Voicemod pelo menu de aplicativos ou rodar `voicemod-linux`.

### Do que ele precisa

O instalador verifica estes itens e se oferece para instalar o que estiver
faltando com o seu gerenciador de pacotes (pacman, apt, dnf ou zypper):

- `curl` ou `wget`, `unzip`, `python3`
- `pactl` (dos pacotes `pipewire-pulse` / `pulseaudio-utils`)
- um servidor de som PipeWire (ou PulseAudio) funcionando

Ele também precisa do GE-Proton. Se você já tiver um pelo Steam, ele é
reaproveitado; senão o GE-Proton mais recente é baixado do GitHub e o checksum
é verificado. Opcional: `icoutils` (para um ícone melhor no menu).

## Primeira execução

- No onboarding, escolha o seu microfone e fone reais. Não escolha "PulseAudio
  Input" nem um dispositivo "Monitor of ..." como microfone.
- No Discord, OBS ou num jogo, selecione a entrada
  **Voicemod Virtual Audio Device (WDM)**.
- Se um diálogo oferecer instalar o driver do Voicemod, escolha **No**. O
  driver de kernel real não roda no Wine, e esse diálogo fecha o app.

Veja [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) se algo não funcionar.

## Comandos

```sh
voicemod-linux            # inicia, ou traz a instância aberta para frente
voicemod-linux update     # baixa a versão atual do Voicemod
voicemod-linux kill       # encerra o Voicemod e o wineserver
voicemod-linux doctor     # mostra a configuração detectada
voicemod-linux logs       # acompanha o log do Voicemod
voicemod-linux setup-audio / teardown-audio
voicemod-linux winecfg
```

## Desinstalação

```sh
curl -fsSL https://raw.githubusercontent.com/brunos3d/voicemod-linux/main/uninstall.sh | bash
```

Isso remove `~/.local/share/voicemod-linux`, o link do launcher, a entrada do
menu e o handler `voicemod:`. A sua conta Voicemod e qualquer GE-Proton do
Steam ficam intactos.

## Testado em

- Manjaro e Arch Linux, kernel 6.18
- GNOME no Wayland
- PipeWire 1.6 (com `pipewire-pulse`)
- GE-Proton11-1
- x86-64 com AVX, GPU NVIDIA (DXVK)

Deve funcionar em outras distribuições e desktops com PipeWire. Relatos e
correções para KDE Plasma, X11, setups só com PulseAudio, GPUs AMD/Intel e
outras configurações são bem-vindos. Veja [CONTRIBUTING.md](CONTRIBUTING.md).

## Como funciona

`Voicemod.exe` é um programa Qt 6: a interface é um bundle Vue renderizado pelo
QtWebEngine, e o áudio roda num motor nativo PortAudio/WASAPI que, no Windows,
conversa com um driver de kernel (`voicemodvad.sys`) que expõe um microfone e
um alto-falante virtuais, mais um dispositivo de controle em `\\.\voicemodvad`.

O Wine não roda esse driver de kernel, então cada peça exclusiva do Windows é
substituída:

| Windows | Equivalente no Linux |
| --- | --- |
| Endpoints de render/captura do `voicemodvad.sys` | Sink nulo `voicemod_vad` e source remapeada `voicemod_mic` no PipeWire, ambos chamados "Voicemod Virtual Audio Device (WDM)" |
| Dispositivo de controle `\\.\voicemodvad` | `bridge/vadshim`, compilado como `avrt.dll` e carregado da pasta do app |
| Entrada de driver vista pelo SetupAPI após o login | `bridge/registry/voicemodvad.reg` |
| Compartilhamento de texturas D3D11 do QtWebEngine | DXVK e o Wine do GE-Proton (o Wine padrão mostra tela preta) |
| Login no navegador e o callback `voicemod:` | `bin/voicemod-open-url` mais um handler `.desktop` |

O binário do aplicativo em disco nunca é modificado. O shim carrega como
`avrt.dll` via `WINEDLLOVERRIDES=avrt=n,b`, responde a `\\.\voicemodvad`
alterando os imports do processo em execução, e corrige o
`IAudioSessionManager2` (que o Wine deixa sem implementação) para que a
configuração de dispositivos funcione. Veja `bridge/vadshim/vadshim.c`.

## Compilar do fonte

O pacote de release já inclui o shim pré-compilado. Para compilar você mesmo,
precisa de `clang`, `lld` e os headers de desenvolvimento do Wine:

```sh
git clone https://github.com/brunos3d/voicemod-linux
cd voicemod-linux
make -C bridge/vadshim      # produz bridge/vadshim/avrt.dll
./install.sh --local        # instala a partir deste checkout
```

O build é reproduzível (`lld-link /Brepro`); o CI verifica isso a cada
alteração. Veja [CONTRIBUTING.md](CONTRIBUTING.md).

## Limitações conhecidas

- Alguns presets de voz falham ao carregar com `Error during string conversion
  ... to float` dentro do SDK de áudio fechado. A maioria das vozes funciona. A
  causa é desconhecida; não é problema de locale.
- O app não consegue definir o dispositivo virtual como padrão do sistema nem
  escondê-lo (`IPolicyConfig` não existe no Wine). Selecione o dispositivo em
  cada aplicativo.
- Medidores de pico por dispositivo e o indicador de "apps conectados" ficam
  vazios.
- A atualização automática está desligada; use `voicemod-linux update`.

## Licença

O código próprio deste projeto é MIT (veja [LICENSE](LICENSE)). Os componentes
de terceiros e a base legal estão descritos em [NOTICE](NOTICE) e
[docs/LICENSES.md](docs/LICENSES.md).
