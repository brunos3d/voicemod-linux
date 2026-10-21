# Builds avrt.dll (vadshim) for the Windows build of Voicemod running under
# Wine. Needs only clang, lld-link and the Wine development headers
# (package names: Arch "wine", Debian/Ubuntu "wine" or "libwine-dev",
# Fedora "wine-devel"). No Wine runtime, winedump or kernel32.dll required:
# the kernel32 and avrt import definitions are committed as .def files.
WINE_INC ?= /usr/include/wine
BUILD    ?= build

CFLAGS = --target=x86_64-w64-windows-gnu -O2 -ffreestanding -fno-stack-protector -fno-builtin \
         -fshort-wchar -nostdinc -isystem $(shell clang -print-resource-dir)/include \
         -I$(WINE_INC)/msvcrt -I$(WINE_INC)/windows -DWINE_UNICODE_NATIVE -Wall

all: avrt.dll

$(BUILD)/kernel32.lib: kernel32.def | $(BUILD)
	lld-link /lib /def:kernel32.def /machine:x64 /out:$@ >/dev/null

$(BUILD)/vadshim.o: vadshim.c | $(BUILD)
	clang $(CFLAGS) -c $< -o $@

# /Brepro makes the PE timestamp a hash of the content, so the output is
# byte-for-byte reproducible.
avrt.dll: $(BUILD)/vadshim.o avrt.def $(BUILD)/kernel32.lib
	lld-link /nologo /dll /Brepro /entry:DllMain /nodefaultlib /machine:x64 /def:avrt.def \
	         /implib:$(BUILD)/avrt.lib /out:$@ $(BUILD)/vadshim.o $(BUILD)/kernel32.lib

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD) avrt.dll avrt.lib avrt.exp

.PHONY: all clean
