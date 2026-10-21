/*
 * vadshim: user-mode stand-in for the Voicemod kernel driver control device.
 *
 * Built as avrt.dll and placed next to Voicemod.exe. Wine loads it instead
 * of its builtin avrt (WINEDLLOVERRIDES=avrt=n,b), so it runs before the
 * application entry point and patches three imports of Voicemod.exe:
 *
 *   CreateFileA/W("\\.\voicemodvad")  -> returns a private event handle
 *   DeviceIoControl(that handle, ...)  -> answered here, logged
 *
 * The real driver receives raw handle values as METHOD_NEITHER "buffers"
 * (IOCTL 0x1d2007). Wine copies METHOD_NEITHER input into the server and
 * fails with ERROR_NOACCESS, so these requests must never reach Wine.
 *
 * It also hooks CoCreateInstance. The first time the app creates an
 * MMDeviceEnumerator, the shared vtable of Wine's IAudioSessionManager2 is
 * patched so that (Un)RegisterSessionNotification and the duck notification
 * calls return S_OK. Wine stubs them with E_NOTIMPL, and Voicemod aborts its
 * device setup when session notifications cannot be registered. No session
 * events are delivered, which only affects the "connected apps" indicator.
 *
 * The AvXxx exports keep the MMCSS API working for the rest of the process.
 */
#include <stdarg.h>
#include "windef.h"
#include "winbase.h"
#include "winnt.h"

#define VAD_DEVICE_TYPE 0x1d
#define IOCTL_METHOD_NEITHER 3
#define CLSCTX_ALL 0x17

typedef HANDLE (WINAPI *CreateFileA_t)(LPCSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
typedef HANDLE (WINAPI *CreateFileW_t)(LPCWSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
typedef HRESULT (WINAPI *CoCreateInstance_t)(const GUID *, void *, DWORD, const GUID *, void **);
typedef BOOL (WINAPI *DeviceIoControl_t)(HANDLE, DWORD, LPVOID, DWORD, LPVOID, DWORD, LPDWORD, LPOVERLAPPED);

static CreateFileA_t real_CreateFileA;
static CreateFileW_t real_CreateFileW;
static DeviceIoControl_t real_DeviceIoControl;
static CoCreateInstance_t real_CoCreateInstance;
static LONG sessions_patched;

static const GUID CLSID_MMDeviceEnumerator_ = {0xbcde0395, 0xe52f, 0x467c, {0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e}};
static const GUID IID_IMMDeviceEnumerator_ = {0xa95664d2, 0x9614, 0x4f35, {0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6}};
static const GUID IID_IAudioSessionManager2_ = {0x77aa99a0, 0x1bd6, 0x484f, {0x8b, 0xc7, 0x2c, 0x65, 0x4c, 0x9a, 0x9b, 0x6f}};

static HANDLE vad_handles[16];
static HANDLE log_file = INVALID_HANDLE_VALUE;
static CRITICAL_SECTION lock;

/* ---- tiny helpers, the DLL links without a C runtime ---- */

static void *mem_set(void *dst, int c, SIZE_T n)
{
    unsigned char *p = dst;
    while (n--) *p++ = (unsigned char)c;
    return dst;
}

static int ascii_lower(int c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }

static BOOL ends_with_vad_a(const char *s)
{
    static const char want[] = "voicemodvad";
    SIZE_T n = 0, w = sizeof(want) - 1, i;
    if (!s) return FALSE;
    while (s[n]) n++;
    if (n < w) return FALSE;
    for (i = 0; i < w; i++)
        if (ascii_lower(s[n - w + i]) != want[i]) return FALSE;
    return n == w || s[n - w - 1] == '\\';
}

static BOOL ends_with_vad_w(const WCHAR *s)
{
    char buf[260];
    int i;
    if (!s) return FALSE;
    for (i = 0; s[i] && i < 259; i++) buf[i] = s[i] < 128 ? (char)s[i] : '?';
    buf[i] = 0;
    return ends_with_vad_a(buf);
}

static char *put_str(char *p, const char *s) { while (*s) *p++ = *s++; return p; }

static char *put_hex(char *p, ULONG_PTR v)
{
    static const char hex[] = "0123456789abcdef";
    char tmp[17];
    int n = 0;
    *p++ = '0'; *p++ = 'x';
    do { tmp[n++] = hex[v & 15]; v >>= 4; } while (v);
    while (n) *p++ = tmp[--n];
    return p;
}

static void log_line(const char *text, SIZE_T len)
{
    DWORD written;
    if (log_file == INVALID_HANDLE_VALUE)
    {
        char path[MAX_PATH];
        DWORD n = GetTempPathA(MAX_PATH - 32, path);
        if (!n) return;
        put_str(path + n, "voicemod-vadshim.log")[0] = 0;
        log_file = real_CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                    NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (log_file == INVALID_HANDLE_VALUE) return;
    }
    WriteFile(log_file, text, (DWORD)len, &written, NULL);
}

static BOOL is_vad_handle(HANDLE h)
{
    int i;
    if (!h || h == INVALID_HANDLE_VALUE) return FALSE;
    for (i = 0; i < 16; i++) if (vad_handles[i] == h) return TRUE;
    return FALSE;
}

static HANDLE open_vad(void)
{
    HANDLE h = CreateEventW(NULL, TRUE, FALSE, NULL);
    int i;
    EnterCriticalSection(&lock);
    for (i = 0; i < 16; i++)
    {
        if (!vad_handles[i] || WaitForSingleObject(vad_handles[i], 0) == WAIT_FAILED)
        {
            vad_handles[i] = h;
            break;
        }
    }
    LeaveCriticalSection(&lock);
    log_line("open \\\\.\\voicemodvad\n", 22);
    return h;
}

/* ---- hooks ---- */

static HANDLE WINAPI hook_CreateFileA(LPCSTR name, DWORD access, DWORD share, LPSECURITY_ATTRIBUTES sa,
                                      DWORD disp, DWORD flags, HANDLE tmpl)
{
    if (ends_with_vad_a(name)) return open_vad();
    return real_CreateFileA(name, access, share, sa, disp, flags, tmpl);
}

static HANDLE WINAPI hook_CreateFileW(LPCWSTR name, DWORD access, DWORD share, LPSECURITY_ATTRIBUTES sa,
                                      DWORD disp, DWORD flags, HANDLE tmpl)
{
    if (ends_with_vad_w(name)) return open_vad();
    return real_CreateFileW(name, access, share, sa, disp, flags, tmpl);
}

static BOOL WINAPI hook_DeviceIoControl(HANDLE h, DWORD code, LPVOID in, DWORD in_len, LPVOID out,
                                        DWORD out_len, LPDWORD returned, LPOVERLAPPED ov)
{
    char line[160], *p;

    if (!is_vad_handle(h))
        return real_DeviceIoControl(h, code, in, in_len, out, out_len, returned, ov);

    p = put_str(line, "ioctl code=");
    p = put_hex(p, code);
    p = put_str(p, " in=");
    p = put_hex(p, (ULONG_PTR)in);
    p = put_str(p, " in_len=");
    p = put_hex(p, in_len);
    p = put_str(p, " out_len=");
    p = put_hex(p, out_len);
    *p++ = '\n';
    log_line(line, p - line);

    /* Zeroed replies read as "no xruns, no dropouts, nothing pending".
     * Event handles passed by 0x1d2007 are accepted and never signalled. */
    if (out && out_len) mem_set(out, 0, out_len);
    if (returned) *returned = (code >> 16) == VAD_DEVICE_TYPE && (code & 3) == IOCTL_METHOD_NEITHER ? 0 : out_len;
    if (ov)
    {
        ov->Internal = 0;
        ov->InternalHigh = out_len;
        if (ov->hEvent) SetEvent(ov->hEvent);
    }
    return TRUE;
}

/* ---- IAudioSessionManager2 notification stubs ---- */

static BOOL guid_eq(const GUID *a, const GUID *b)
{
    const unsigned char *x = (const unsigned char *)a, *y = (const unsigned char *)b;
    int i;
    for (i = 0; i < 16; i++) if (x[i] != y[i]) return FALSE;
    return TRUE;
}

static HRESULT WINAPI session_notify_ok(void *iface, void *arg) { return S_OK; }
static HRESULT WINAPI duck_notify_ok(void *iface, const WCHAR *id, void *arg) { return S_OK; }

/* Raw COM calls through vtable slots, so no SDK interface headers are needed.
 * IMMDeviceEnumerator: 4 = GetDefaultAudioEndpoint
 * IMMDevice:           3 = Activate
 * IAudioSessionManager2: 6/7 = (Un)RegisterSessionNotification,
 *                        8/9 = (Un)RegisterDuckNotification */
typedef ULONG (WINAPI *Release_t)(void *);
typedef HRESULT (WINAPI *GetDefaultEndpoint_t)(void *, int, int, void **);
typedef HRESULT (WINAPI *Activate_t)(void *, const GUID *, DWORD, void *, void **);
#define VTBL(obj) (*(void ***)(obj))

static void patch_session_manager(void)
{
    void *enumerator = NULL, *device = NULL, *manager = NULL;
    HRESULT hr;
    int flow;

    if (InterlockedExchange(&sessions_patched, 1)) return;

    hr = real_CoCreateInstance(&CLSID_MMDeviceEnumerator_, NULL, CLSCTX_ALL, &IID_IMMDeviceEnumerator_, &enumerator);
    if (FAILED(hr)) goto done;
    for (flow = 0; flow < 2 && !device; flow++)  /* eRender, then eCapture */
        ((GetDefaultEndpoint_t)VTBL(enumerator)[4])(enumerator, flow, 0, &device);
    if (!device) goto done;
    hr = ((Activate_t)VTBL(device)[3])(device, &IID_IAudioSessionManager2_, CLSCTX_ALL, NULL, &manager);
    if (FAILED(hr) || !manager) goto done;

    {
        void **vtbl = VTBL(manager);
        DWORD old;
        if (VirtualProtect(&vtbl[6], 4 * sizeof(void *), PAGE_READWRITE, &old))
        {
            vtbl[6] = session_notify_ok;
            vtbl[7] = session_notify_ok;
            vtbl[8] = duck_notify_ok;
            vtbl[9] = session_notify_ok;
            VirtualProtect(&vtbl[6], 4 * sizeof(void *), old, &old);
            log_line("patched IAudioSessionManager2 notifications\n", 45);
        }
    }

done:
    if (manager) ((Release_t)VTBL(manager)[2])(manager);
    if (device) ((Release_t)VTBL(device)[2])(device);
    if (enumerator) ((Release_t)VTBL(enumerator)[2])(enumerator);
}

static HRESULT WINAPI hook_CoCreateInstance(const GUID *clsid, void *outer, DWORD ctx, const GUID *iid, void **out)
{
    HRESULT hr = real_CoCreateInstance(clsid, outer, ctx, iid, out);
    if (SUCCEEDED(hr) && !sessions_patched && clsid && guid_eq(clsid, &CLSID_MMDeviceEnumerator_))
        patch_session_manager();
    return hr;
}

/* ---- import table patching ---- */

static void patch_imports(HMODULE module)
{
    BYTE *base = (BYTE *)module;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY *dir = &nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    IMAGE_IMPORT_DESCRIPTOR *desc;

    if (!dir->VirtualAddress) return;
    for (desc = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir->VirtualAddress); desc->Name; desc++)
    {
        IMAGE_THUNK_DATA *names = (IMAGE_THUNK_DATA *)(base + (desc->OriginalFirstThunk ? desc->OriginalFirstThunk : desc->FirstThunk));
        IMAGE_THUNK_DATA *slots = (IMAGE_THUNK_DATA *)(base + desc->FirstThunk);

        for (; names->u1.AddressOfData; names++, slots++)
        {
            const char *fn;
            void *hook = NULL;
            DWORD old;

            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
            fn = (const char *)((IMAGE_IMPORT_BY_NAME *)(base + names->u1.AddressOfData))->Name;
            if (!lstrcmpA(fn, "CreateFileA")) hook = hook_CreateFileA;
            else if (!lstrcmpA(fn, "CreateFileW")) hook = hook_CreateFileW;
            else if (!lstrcmpA(fn, "DeviceIoControl")) hook = hook_DeviceIoControl;
            else if (!lstrcmpA(fn, "CoCreateInstance"))
            {
                real_CoCreateInstance = (CoCreateInstance_t)slots->u1.Function;
                hook = hook_CoCreateInstance;
            }
            if (!hook) continue;

            VirtualProtect(&slots->u1.Function, sizeof(void *), PAGE_READWRITE, &old);
            slots->u1.Function = (ULONG_PTR)hook;
            VirtualProtect(&slots->u1.Function, sizeof(void *), old, &old);
        }
    }
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, void *reserved)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        HMODULE k32 = GetModuleHandleA("kernel32.dll");
        DisableThreadLibraryCalls(inst);
        InitializeCriticalSection(&lock);
        real_CreateFileA = (CreateFileA_t)GetProcAddress(k32, "CreateFileA");
        real_CreateFileW = (CreateFileW_t)GetProcAddress(k32, "CreateFileW");
        real_DeviceIoControl = (DeviceIoControl_t)GetProcAddress(k32, "DeviceIoControl");
        patch_imports(GetModuleHandleA(NULL));
    }
    return TRUE;
}

/* ---- avrt.dll API ---- */

static HANDLE mmcss_handle(DWORD *index)
{
    if (!index) { SetLastError(ERROR_INVALID_PARAMETER); return NULL; }
    if (!*index) *index = 1;
    return (HANDLE)(ULONG_PTR)0xcafe;
}

HANDLE WINAPI AvSetMmThreadCharacteristicsA(LPCSTR task, DWORD *index) { return mmcss_handle(index); }
HANDLE WINAPI AvSetMmThreadCharacteristicsW(LPCWSTR task, DWORD *index) { return mmcss_handle(index); }
HANDLE WINAPI AvSetMmMaxThreadCharacteristicsA(LPCSTR a, LPCSTR b, DWORD *index) { return mmcss_handle(index); }
HANDLE WINAPI AvSetMmMaxThreadCharacteristicsW(LPCWSTR a, LPCWSTR b, DWORD *index) { return mmcss_handle(index); }
BOOL WINAPI AvRevertMmThreadCharacteristics(HANDLE h) { return TRUE; }

BOOL WINAPI AvSetMmThreadPriority(HANDLE h, int prio)
{
    /* AVRT_PRIORITY_* runs from -2 (very low) to 2 (high), 3 is critical. */
    int win = prio >= 3 ? THREAD_PRIORITY_TIME_CRITICAL : prio >= 1 ? THREAD_PRIORITY_HIGHEST : THREAD_PRIORITY_NORMAL;
    SetThreadPriority(GetCurrentThread(), win);
    return TRUE;
}

BOOL WINAPI AvQuerySystemResponsiveness(HANDLE h, ULONG *value)
{
    if (value) *value = 20;
    return TRUE;
}

BOOL WINAPI AvRtCreateThreadOrderingGroup(HANDLE *ctx, LARGE_INTEGER *period, GUID *guid, LARGE_INTEGER *timeout)
{
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    return FALSE;
}
BOOL WINAPI AvRtCreateThreadOrderingGroupExA(HANDLE *ctx, LARGE_INTEGER *period, GUID *guid, LARGE_INTEGER *timeout, LPCSTR task)
{
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    return FALSE;
}
BOOL WINAPI AvRtCreateThreadOrderingGroupExW(HANDLE *ctx, LARGE_INTEGER *period, GUID *guid, LARGE_INTEGER *timeout, LPCWSTR task)
{
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    return FALSE;
}
BOOL WINAPI AvRtDeleteThreadOrderingGroup(HANDLE ctx) { return FALSE; }
BOOL WINAPI AvRtJoinThreadOrderingGroup(HANDLE *ctx, GUID *guid, BOOL before) { return FALSE; }
BOOL WINAPI AvRtLeaveThreadOrderingGroup(HANDLE ctx) { return FALSE; }
BOOL WINAPI AvRtWaitOnThreadOrderingGroup(HANDLE ctx) { return FALSE; }
