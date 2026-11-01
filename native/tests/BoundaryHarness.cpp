#include <cstdint>
#include <cstdio>
#include <cstring>
#include <initializer_list>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

struct Vector2 { float X; float Y; };
using Fit = Vector2* (*)(Vector2*, const Vector2*);
struct Snapshot
{
    uint64_t gp[7];
    uint64_t flags;
    uint8_t xmm[6][16];
};
static_assert(sizeof(Snapshot) == 0xA0);
extern "C"
{
Vector2* UWUI_TestStockFit(Vector2*, const Vector2*);
Vector2* UWUI_FitReferenceRectBoundary(Vector2*, const Vector2*);
void UWUI_TestProbe(Fit, Vector2*, const Vector2*, Snapshot*);
extern const uint8_t UWUI_TestProbeReturn;
Fit UWUI_OriginalFitReferenceRect = &UWUI_TestStockFit;
uintptr_t UWUI_TestAdjustedResult = 0;
uintptr_t UWUI_TestAdjustedInput = 0;
uintptr_t UWUI_TestCaller = 0;
uintptr_t UWUI_TestStackAlignment = 0;
}

int main()
{
    const Vector2 input{5120, 2160};
    Vector2 result{};
    Snapshot stock{}, hooked{};
    UWUI_TestProbe(&UWUI_TestStockFit, &result, &input, &stock);
    UWUI_TestProbe(&UWUI_FitReferenceRectBoundary, &result, &input, &hooked);
    if (std::memcmp(&stock, &hooked, sizeof(stock)) != 0 ||
        result.X != 5120 || result.Y != 2160 ||
        UWUI_TestAdjustedResult != reinterpret_cast<uintptr_t>(&result) ||
        UWUI_TestAdjustedInput != reinterpret_cast<uintptr_t>(&input) ||
        UWUI_TestCaller != reinterpret_cast<uintptr_t>(&UWUI_TestProbeReturn) ||
        UWUI_TestStackAlignment != 8)
    {
        std::puts("FAIL native boundary: register, flags, output, argument or alignment mismatch");
        return 1;
    }
    std::puts("PASS production ASM boundary: all volatile GP/XMM outputs and flags survive hostile adjustment");
    std::puts("PASS result mutation, original input, original return address and Windows stack alignment");

    // Verify Windows can also unwind the frame from its body and epilogue.
    DWORD64 imageBase = 0;
    auto* entry = RtlLookupFunctionEntry(
        reinterpret_cast<DWORD64>(&UWUI_FitReferenceRectBoundary), &imageBase, nullptr);
    if (!entry) return 2;
    const auto* code = reinterpret_cast<const uint8_t*>(imageBase + entry->BeginAddress);
    const auto size = entry->EndAddress - entry->BeginAddress;
    unsigned epilogue = size;
    for (unsigned i = 0; i + 4 < size; ++i)
        if (code[i] == 0x48 && code[i+1] == 0x8D && code[i+2] == 0x65 &&
            code[i+3] == 0 && code[i+4] == 0x5D)
            epilogue = i;
    if (epilogue == size) return 3;
    for (unsigned pc : {16u, epilogue, epilogue + 4, epilogue + 5})
    {
        alignas(16) uint64_t stack[64]{};
        const auto allocated = reinterpret_cast<DWORD64>(&stack[0]);
        stack[0xD0 / 8] = 0x12345678; // caller's RBP
        stack[0xD8 / 8] = 0x87654321; // caller's return address
        CONTEXT context{};
        context.Rip = imageBase + entry->BeginAddress + pc;
        context.Rsp = allocated + (pc == epilogue + 4 ? 0xD0 : pc == epilogue + 5 ? 0xD8 : 0);
        context.Rbp = pc == epilogue + 5 ? 0x12345678 : allocated + 0xD0;
        PVOID handlerData = nullptr;
        DWORD64 establisher = 0;
        RtlVirtualUnwind(UNW_FLAG_NHANDLER, imageBase, context.Rip, entry,
            &context, &handlerData, &establisher, nullptr);
        if (context.Rip != 0x87654321 || context.Rsp != allocated + 0xE0 ||
            context.Rbp != 0x12345678)
        {
            std::printf("FAIL Windows frame unwind at offset %u\n", pc);
            return 4;
        }
    }
    std::puts("PASS Windows frame unwind from hook body and every epilogue instruction");
}
