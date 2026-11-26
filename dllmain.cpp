// AToolSlotLimit: raises ATOOL's "slot <= 1000" guard at runtime (UE4SS C++ mod, nothing of ATOOL's is redistributed).
// ATOOL's ModActor blueprint functions DataGet1/2/3 each hold one Kismet `EX_IntConst 1000` (1D E8 03 00 00) in their Script.
// Once the class is loaded we find those bytes in UStruct::Script (TArray<uint8> at +0x60, per UE4SS MemberVariableLayout.ini)
// and write the configured limit. Polls every 2 s until it has patched, then every 5 s (ATOOL's class is re-created after load).
//
// Observability (project rule, see AGENTS.md): every line goes to UE4SS.log tagged [AToolSlotLimit] AND to AToolSlotLimit.log next to
// config.txt (rotated at 256 KB). Startup records the mod version, the config, and the host UE4SS.dll path + SHA-256 with a warning when
// it is not the tested build. While ATOOL is missing the mod says so and repeats every 30 s with a counter. Exceptions in the tick
// callback are caught and logged.
#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/Hooks.hpp>
#define NOMINMAX
#include <windows.h>
#include <bcrypt.h>
#include <chrono>
#include <climits>
#include <cstdint>
#include <ctime>
#include <exception>
#include <fstream>
#include <map>
#include <string>
#include <vector>
#pragma comment(lib, "bcrypt.lib")

using namespace RC;
using namespace RC::Unreal;

namespace
{
    // RevOG SB-UE4SS 1.3, the only UE4SS this mod was tested with
    constexpr const char* TESTED_UE4SS_SHA256 = "E0CC51CE5B47D5BE82194510B0B4B4054DD15CE0322A983655A022F92D27DABE";

    std::string sha256File(const std::wstring& path)
    {   // uppercase hex SHA-256 of a file, "" on any failure
        std::string hex;
        BCRYPT_ALG_HANDLE alg = nullptr; BCRYPT_HASH_HANDLE h = nullptr;
        if (!BCRYPT_SUCCESS(BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0))) return hex;
        DWORD objLen = 0, cb = 0;
        BCryptGetProperty(alg, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&objLen), sizeof(objLen), &cb, 0);
        std::vector<uint8_t> obj(objLen);
        if (BCRYPT_SUCCESS(BCryptCreateHash(alg, &h, obj.data(), objLen, nullptr, 0, 0)))
        {
            std::ifstream f(path, std::ios::binary); std::vector<char> buf(1 << 20); bool ok = f.is_open();
            while (ok && f)
            {
                f.read(buf.data(), static_cast<std::streamsize>(buf.size())); auto n = f.gcount();
                if (n > 0 && !BCRYPT_SUCCESS(BCryptHashData(h, reinterpret_cast<PUCHAR>(buf.data()), static_cast<ULONG>(n), 0))) ok = false;
            }
            uint8_t digest[32];
            if (ok && BCRYPT_SUCCESS(BCryptFinishHash(h, digest, 32, 0)))
            {
                static const char* d = "0123456789ABCDEF";
                for (auto b : digest) { hex += d[b >> 4]; hex += d[b & 15]; }
            }
            BCryptDestroyHash(h);
        }
        BCryptCloseAlgorithmProvider(alg, 0);
        return hex;
    }

    std::wstring widen(const std::string& s) { return std::wstring(s.begin(), s.end()); }   // ASCII is all we log from the narrow side
}

class AToolSlotLimit : public CppUserModBase
{
    static constexpr int OLD_LIMIT = 1000, SCRIPT_OFF = 0x60;   // ponytail: raw offset; UE4SS exposes no Script accessor
    static constexpr size_t LOG_CAP = 256 * 1024;
    int limit = 9999;
    bool done = false; int lastTotal = -1;
    std::map<std::wstring, uintptr_t> lastKey;
    std::map<std::wstring, bool> noConstLogged;                 // log "no 1000 constant" once per function, not every poll
    std::chrono::steady_clock::time_point last{};
    std::wstring logPath;
    bool waiting = false; std::chrono::steady_clock::time_point waitStart{}, nextWait{};
    bool ticked = false; int errCount = 0;

    // one line to UE4SS.log and to our own log file (timestamped, best effort)
    void note(const std::wstring& m)
    {
        Output::send<LogLevel::Verbose>(STR("[AToolSlotLimit] {}\n"), m);
        if (logPath.empty()) return;
        std::ofstream f(logPath, std::ios::app | std::ios::binary);
        if (!f) return;
        std::time_t t = std::time(nullptr); std::tm lt{}; localtime_s(&lt, &t); char ts[32]; std::strftime(ts, sizeof ts, "%Y-%m-%d %H:%M:%S", &lt);
        int n = WideCharToMultiByte(CP_UTF8, 0, m.c_str(), static_cast<int>(m.size()), nullptr, 0, nullptr, nullptr);
        std::string u(static_cast<size_t>(n), '\0');
        WideCharToMultiByte(CP_UTF8, 0, m.c_str(), static_cast<int>(m.size()), u.data(), n, nullptr, nullptr);
        f << ts << " " << u << "\r\n";
    }

    void loadCfg(const std::wstring& path)
    {   // config.txt: "limit=NNNN" (1000 = leave ATOOL as is; below 1000 is not supported and is raised to 1000)
        std::ifstream f(path); bool found = false;
        for (std::string l; std::getline(f, l);)
            if (l.rfind("limit=", 0) == 0)
            {
                found = true; int v = std::atoi(l.c_str() + 6);
                if (v >= OLD_LIMIT && v <= INT_MAX) limit = v;
                else { limit = OLD_LIMIT; note(fmt::format(STR("config: limit={} is below 1000 or invalid and is not supported; using 1000 (ATOOL unchanged)"), widen(l.substr(6)))); }
            }
        note(fmt::format(STR("config: {} {} (limit {})"), path, f.is_open() ? (found ? STR("read") : STR("read, no limit= line, default used")) : STR("not found, default used"), limit));
    }

    static void put(uint8_t* p, int v) { p[0] = 0x1D; for (int i = 0; i < 4; ++i) p[1 + i] = uint8_t((uint32_t(v) >> (8 * i)) & 0xff); }

    // returns patched-or-already count, -1 when the function is not loaded yet, -2 on an unexpected layout
    int patchFn(const wchar_t* name)
    {
        auto* fn = UObjectGlobals::StaticFindObject<UObject*>(nullptr, nullptr, name);
        if (!fn) return -1;
        auto* base = reinterpret_cast<uint8_t*>(fn);
        uint8_t* data = *reinterpret_cast<uint8_t**>(base + SCRIPT_OFF);
        int32_t num = *reinterpret_cast<int32_t*>(base + SCRIPT_OFF + 8), max = *reinterpret_cast<int32_t*>(base + SCRIPT_OFF + 12);
        if (!data || num < 16 || num > (1 << 20) || max < num)
        {
            if (!noConstLogged[std::wstring(name) + L"#odd"]) { noConstLogged[std::wstring(name) + L"#odd"] = true; note(fmt::format(STR("{}: odd Script array (data {} num {} max {}) - ATOOL's layout differs from what this mod was made for"), name, static_cast<void*>(data), num, max)); }
            return -2;
        }
        uint8_t oldB[5], newB[5]; put(oldB, OLD_LIMIT); put(newB, limit);
        int hit = 0;
        for (int32_t i = 0; i + 5 <= num; ++i)
        {
            if (memcmp(data + i, oldB, 5) == 0 && limit != OLD_LIMIT) { memcpy(data + i, newB, 5); ++hit; note(fmt::format(STR("{}: {} -> {} at +{}"), name, OLD_LIMIT, limit, i)); }
            else if (memcmp(data + i, newB, 5) == 0) ++hit;
        }
        auto& flagged = noConstLogged[name];
        if (!hit) { if (!flagged) { flagged = true; note(fmt::format(STR("{}: no 1000 constant in {} bytes (ATOOL's data differs from what this mod was made for)"), name, num)); } }
        else flagged = false;
        auto key = reinterpret_cast<uintptr_t>(fn) ^ reinterpret_cast<uintptr_t>(data);
        auto& seen = lastKey[name];
        if (seen != key) { note(fmt::format(STR("{}: UFunction {} Script data {} ({} bytes)"), name, static_cast<void*>(fn), static_cast<void*>(data), num)); seen = key; }
        return hit;
    }

    void waitNote(int missing)
    {   // never silent while ATOOL's class is missing: say it once, then every 30 s with the elapsed time
        auto now = std::chrono::steady_clock::now();
        if (!waiting)
        {
            waiting = true; waitStart = now; nextWait = now + std::chrono::seconds(30);
            note(fmt::format(STR("waiting for ATOOL: {} of 3 DataGet functions not found yet (ATOOL not installed, or not loaded yet)"), missing));
        }
        else if (now >= nextWait)
        {
            nextWait = now + std::chrono::seconds(30);
            note(fmt::format(STR("still waiting for ATOOL after {} s: {} of 3 DataGet functions not found"), std::chrono::duration_cast<std::chrono::seconds>(now - waitStart).count(), missing));
        }
    }

    void tryPatch()
    {
        int total = 0, missing = 0;
        for (auto* n : {STR("/Game/Mods/HD-ATOOL_P/ModActor.ModActor_C:DataGet1"), STR("/Game/Mods/HD-ATOOL_P/ModActor.ModActor_C:DataGet2"), STR("/Game/Mods/HD-ATOOL_P/ModActor.ModActor_C:DataGet3")})
        {
            int r = patchFn(n);
            if (r == -1) ++missing; else if (r > 0) total += r;
        }
        if (missing) { waitNote(missing); return; }          // class not loaded yet: try again later
        if (waiting)
        {
            waiting = false;
            note(fmt::format(STR("ATOOL found after {} s"), std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() - waitStart).count()));
        }
        if (!done || total != lastTotal) note(fmt::format(STR("{}: {} constant(s) now {} (3 expected)"), done ? STR("changed") : STR("done"), total, limit));
        done = true; lastTotal = total;
    }

public:
    AToolSlotLimit() { ModName = STR("AToolSlotLimit"); ModVersion = STR("0.2"); ModDescription = STR("Raises ATOOL's 1000 slot guard"); ModAuthors = STR("sb-atool-slot-limit"); }

    auto on_unreal_init() -> void override
    {
        wchar_t path[MAX_PATH]{}; HMODULE self = nullptr;
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, reinterpret_cast<LPCWSTR>(&anchor), &self);
        GetModuleFileNameW(self, path, MAX_PATH);
        std::wstring p = path; p = p.substr(0, p.find_last_of(L"\\/")); p = p.substr(0, p.find_last_of(L"\\/"));   // .../AToolSlotLimit/dlls/main.dll
        logPath = p + L"\\AToolSlotLimit.log";
        {   // rotate our own log: one .1 copy above the cap
            std::ifstream probe(logPath, std::ios::binary | std::ios::ate);
            if (probe && static_cast<size_t>(probe.tellg()) > LOG_CAP) { probe.close(); std::wstring old = logPath + L".1"; DeleteFileW(old.c_str()); MoveFileW(logPath.c_str(), old.c_str()); }
        }
        loadCfg(p + L"\\config.txt");
        note(fmt::format(STR("v0.2 loaded, limit {} (own log: {})"), limit, logPath));
        {   // identity of the host: which UE4SS.dll is this running in, and is it the tested one?
            wchar_t hostPath[MAX_PATH]{}; HMODULE host = GetModuleHandleW(L"UE4SS.dll");
            if (host && GetModuleFileNameW(host, hostPath, MAX_PATH))
            {
                std::string sha = sha256File(hostPath); bool tested = (sha == TESTED_UE4SS_SHA256);
                note(fmt::format(STR("host UE4SS: {} sha256 {} - {}"), hostPath, sha.empty() ? STR("(could not be read)") : widen(sha), tested ? STR("the tested build (RevOG SB-UE4SS 1.3)") : STR("NOT the tested build (RevOG SB-UE4SS 1.3): unsupported, may misbehave")));
            }
            else note(STR("host UE4SS: UE4SS.dll module not found - cannot tell which build this runs in"));
        }
        note(STR("waiting for ATOOL's class; the patch is applied once it is loaded"));
        Hook::RegisterEngineTickPostCallback([this](UEngine*, float) {
            try
            {
                if (!ticked) { ticked = true; note(STR("engine tick callback is running")); }
                auto now = std::chrono::steady_clock::now();
                if (now - last < std::chrono::seconds(done ? 5 : 2)) return;   // after the first patch: re-check (re-apply if ATOOL's class was replaced)
                last = now; tryPatch();
            }
            catch (const std::exception& e) { if (errCount++ < 5) note(fmt::format(STR("exception in the tick callback: {}"), widen(e.what()))); }
            catch (...) { if (errCount++ < 5) note(STR("unknown exception in the tick callback")); }
        });
    }
    static void anchor() {}
};

extern "C"
{
    __declspec(dllexport) CppUserModBase* start_mod() { return new AToolSlotLimit(); }
    __declspec(dllexport) void uninstall_mod(CppUserModBase* mod) { delete mod; }
}
