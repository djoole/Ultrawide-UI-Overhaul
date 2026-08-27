#include <cstdint>
#include <cstring>
#include <atomic>
#include <intrin.h>
#include <windows.h>

#define RED4EXT_HEADER_ONLY
#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Utils.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector2.hpp>

namespace
{
RED4ext::v1::PluginHandle s_pluginHandle{};
const RED4ext::v1::Sdk* s_sdk = nullptr;

using FitReferenceRect_t = RED4ext::Vector2* (*)(RED4ext::Vector2*, const RED4ext::Vector2*);
FitReferenceRect_t s_originalFitReferenceRect = nullptr;
void* s_fitReferenceRectTarget = nullptr;
std::atomic_bool s_suppressed{false};

void LogInfo(const char* aMessage)
{
    if (s_sdk != nullptr && s_sdk->logger != nullptr)
        s_sdk->logger->Info(s_pluginHandle, aMessage);
}

RED4ext::Vector2* FitReferenceRectOverride(RED4ext::Vector2* aResult,
                                           const RED4ext::Vector2* aInput)
{
    auto* result = s_originalFitReferenceRect(aResult, aInput);

    const auto imageBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    const auto returnAddress = reinterpret_cast<uintptr_t>(_ReturnAddress());
    const auto callerRva = imageBase != 0 ? returnAddress - imageBase : 0;

    // This caller converts analog-controller pointer coordinates into the
    // stock UI reference space. Returning the physical ultrawide rectangle
    // here makes the virtual pointer appear but prevents stick movement.
    // Keep the stock fitted rectangle for this input path while allowing the
    // fullscreen compositor callers below to use the physical rectangle.
    constexpr uintptr_t kControllerPointerCallerReturnRva = 0x103BE12;
    const bool isControllerPointerPath =
        callerRva == kControllerPointerCallerReturnRva;

    // REDengine normally fits fullscreen menus into a fixed 3840x2160
    // reference rectangle. Preserve the physical rectangle on ultrawide
    // displays so the compositor does not generate side pillars.
    if (result != nullptr && aInput != nullptr &&
        s_suppressed.load(std::memory_order_relaxed) &&
        !isControllerPointerPath &&
        // 3200x900 is also accepted as a practical 32:9 development mode on
        // a 3440x1440 panel. The wide minimum and aspect check still prevent
        // ordinary UI rectangles from entering this fullscreen-only path.
        aInput->X >= 2500.0f && aInput->Y >= 700.0f &&
        aInput->X / aInput->Y > (16.0f / 9.0f + 0.01f))
    {
        *result = *aInput;
    }

    return result;
}

void SetBlackBarsSuppressed(RED4ext::IScriptable* aContext,
                            RED4ext::CStackFrame* aFrame,
                            void* aOut, int64_t a4)
{
    RED4EXT_UNUSED_PARAMETER(aContext);
    RED4EXT_UNUSED_PARAMETER(aOut);
    RED4EXT_UNUSED_PARAMETER(a4);

    bool suppressed = false;
    RED4ext::GetParameter(aFrame, &suppressed);
    aFrame->code++;
    s_suppressed.store(suppressed, std::memory_order_relaxed);
    LogInfo(suppressed ? "[BlackPillarsRemover] pillars disabled"
                       : "[BlackPillarsRemover] pillars enabled");
}

bool InstallHook()
{
    if (s_sdk == nullptr || s_sdk->hooking == nullptr)
        return false;

    // Cyberpunk 2077 2.31. Refuse to attach if a game update changes the
    // function, instead of hooking an unknown address.
    constexpr uintptr_t kFitReferenceRectRva = 0x2980F4;
    constexpr uint8_t kExpected[] = {
        0xF3, 0x0F, 0x10, 0x42, 0x04, 0xF3, 0x0F, 0x10, 0x0A,
        0x0F, 0x28, 0xD0
    };

    auto* imageBase = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto* target = imageBase != nullptr ? imageBase + kFitReferenceRectRva : nullptr;
    if (target == nullptr || std::memcmp(target, kExpected, sizeof(kExpected)) != 0)
    {
        LogInfo("[BlackPillarsRemover] unsupported game executable; hook not installed");
        return false;
    }

    if (!s_sdk->hooking->Attach(s_pluginHandle, target,
                                reinterpret_cast<void*>(&FitReferenceRectOverride),
                                reinterpret_cast<void**>(&s_originalFitReferenceRect)))
    {
        LogInfo("[BlackPillarsRemover] hook installation failed");
        return false;
    }

    s_fitReferenceRectTarget = target;
    LogInfo("[BlackPillarsRemover] ultrawide fullscreen composition enabled");
    return true;
}
} // namespace

RED4EXT_C_EXPORT void RED4EXT_CALL RegisterTypes()
{
}

RED4EXT_C_EXPORT void RED4EXT_CALL PostRegisterTypes()
{
    auto* rtti = RED4ext::CRTTISystem::Get();
    RED4ext::CBaseFunction::Flags flags{};
    flags.isNative = true;
    flags.isStatic = true;

    auto* function = RED4ext::CGlobalFunction::Create(
        "UWMapSetBlackBarsSuppressed", "UWMapSetBlackBarsSuppressed", &SetBlackBarsSuppressed);
    function->flags = flags;
    function->AddParam("Bool", "suppressed");
    rtti->RegisterFunction(function);
}

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle,
                                        RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    if (aReason == RED4ext::v1::EMainReason::Load)
    {
        s_pluginHandle = aHandle;
        s_sdk = aSdk;
        s_suppressed.store(false, std::memory_order_relaxed);
        auto* rtti = RED4ext::CRTTISystem::Get();
        rtti->AddRegisterCallback(RegisterTypes);
        rtti->AddPostRegisterCallback(PostRegisterTypes);
        InstallHook();
    }
    else if (aReason == RED4ext::v1::EMainReason::Unload &&
             s_sdk != nullptr && s_sdk->hooking != nullptr &&
             s_fitReferenceRectTarget != nullptr)
    {
        s_sdk->hooking->Detach(s_pluginHandle, s_fitReferenceRectTarget);
        s_fitReferenceRectTarget = nullptr;
        s_originalFitReferenceRect = nullptr;
    }

    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"Black Pillars Remover";
    aInfo->author = L"djoole";
    aInfo->version = RED4EXT_V1_SEMVER(1, 2, 1);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_LATEST;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}
