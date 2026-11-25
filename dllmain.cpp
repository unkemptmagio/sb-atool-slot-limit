// AToolSlotLimit: raises ATOOL's "slot <= 1000" guard at runtime (UE4SS C++ mod, nothing of ATOOL's is redistributed).
// ATOOL's ModActor blueprint functions DataGet1/2/3 each hold one Kismet `EX_IntConst 1000` (1D E8 03 00 00) in their Script.
// Once the class is loaded we find those bytes in UStruct::Script (TArray<uint8> at +0x60, per UE4SS MemberVariableLayout.ini)
// and write the configured limit. Polls every 2 s until it has patched, then does nothing (no per-frame cost).
#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/Hooks.hpp>
#define NOMINMAX
#include <windows.h>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <string>

using namespace RC;
using namespace RC::Unreal;

class AToolSlotLimit : public CppUserModBase
{
    static constexpr int OLD_LIMIT = 1000, SCRIPT_OFF = 0x60;   // ponytail: raw offset; UE4SS exposes no Script accessor
    int limit = 9999;
    bool done = false;
    std::chrono::steady_clock::time_point last{};

    void loadCfg(const std::wstring& path)
    {   // config.txt: "limit=NNNN" (1000 = leave ATOOL as is)
        std::ifstream f(path);
        for (std::string l; std::getline(f, l);)
            if (l.rfind("limit=", 0) == 0) { int v = std::atoi(l.c_str() + 6); if (v >= 1 && v <= 0x7fffffff) limit = v; }
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
        if (!data || num < 16 || num > (1 << 20) || max < num) { Output::send<LogLevel::Verbose>(STR("[AToolSlotLimit] {}: odd Script array (data {} num {} max {})\n"), name, (void*)data, num, max); return -2; }
        uint8_t oldB[5], newB[5]; put(oldB, OLD_LIMIT); put(newB, limit);
        int hit = 0;
        for (int32_t i = 0; i + 5 <= num; ++i)
        {
            if (memcmp(data + i, oldB, 5) == 0 && limit != OLD_LIMIT) { memcpy(data + i, newB, 5); ++hit; Output::send<LogLevel::Verbose>(STR("[AToolSlotLimit] {}: {} -> {} at +{}\n"), name, OLD_LIMIT, limit, i); }
            else if (memcmp(data + i, newB, 5) == 0) ++hit;
        }
        if (!hit) Output::send<LogLevel::Verbose>(STR("[AToolSlotLimit] {}: no 1000 constant in {} bytes\n"), name, num);
        return hit;
    }

    void tryPatch()
    {
        int total = 0, missing = 0;
        for (auto* n : {STR("/Game/Mods/HD-ATOOL_P/ModActor.ModActor_C:DataGet1"), STR("/Game/Mods/HD-ATOOL_P/ModActor.ModActor_C:DataGet2"), STR("/Game/Mods/HD-ATOOL_P/ModActor.ModActor_C:DataGet3")})
        {
            int r = patchFn(n);
            if (r == -1) ++missing; else if (r > 0) total += r;
        }
        if (missing) return;                      // class not loaded yet: try again later
        done = true;
        Output::send<LogLevel::Verbose>(STR("[AToolSlotLimit] done: {} constant(s) now {} (3 expected)\n"), total, limit);
    }

public:
    AToolSlotLimit() { ModName = STR("AToolSlotLimit"); ModVersion = STR("0.1"); ModDescription = STR("Raises ATOOL's 1000 slot guard"); ModAuthors = STR("sb-atool-slot-limit"); }

    auto on_unreal_init() -> void override
    {
        wchar_t path[MAX_PATH]{}; HMODULE self = nullptr;
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, reinterpret_cast<LPCWSTR>(&anchor), &self);
        GetModuleFileNameW(self, path, MAX_PATH);
        std::wstring p = path; p = p.substr(0, p.find_last_of(L"\\/")); p = p.substr(0, p.find_last_of(L"\\/"));   // .../AToolSlotLimit/dlls/main.dll
        loadCfg(p + L"\\config.txt");
        Hook::RegisterEngineTickPostCallback([this](UEngine*, float) {
            if (done) return;
            auto now = std::chrono::steady_clock::now();
            if (now - last < std::chrono::seconds(2)) return;
            last = now; tryPatch();
        });
        Output::send<LogLevel::Verbose>(STR("[AToolSlotLimit] v0.1 loaded, limit {}\n"), limit);
    }
    static void anchor() {}
};

extern "C"
{
    __declspec(dllexport) CppUserModBase* start_mod() { return new AToolSlotLimit(); }
    __declspec(dllexport) void uninstall_mod(CppUserModBase* mod) { delete mod; }
}
