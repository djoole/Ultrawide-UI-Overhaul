// Exercise the actual production adjustment and boundary, with only the
// game's original fitter replaced by the deterministic assembly test stub.
#include "../src/BlackPillarsRemover.cpp"

extern "C"
{
RED4ext::Vector2* UWUI_TestStockFit(RED4ext::Vector2*, const RED4ext::Vector2*);
extern const uint8_t UWUI_TestProbeReturn;
void UWUI_TestProbe(FitReferenceRect_t, RED4ext::Vector2*, const RED4ext::Vector2*, void*);
}

int main()
{
    UWUI_OriginalFitReferenceRect = &UWUI_TestStockFit;
    unsigned passed = 0;
    for (const auto input : {RED4ext::Vector2{3440, 1440}, {5120, 2160},
                             {7680, 2160}, {2880, 1440}, {1920, 816},
                             {3840, 2160}, {1920, 1080}})
    {
        s_configuredWidth = static_cast<uint32_t>(input.X);
        s_configuredHeight = static_cast<uint32_t>(input.Y);
        for (bool suppressed : {false, true})
        for (bool controller : {false, true})
        {
            s_suppressed.store(suppressed);
            s_imageBase = reinterpret_cast<uintptr_t>(&UWUI_TestProbeReturn) -
                (controller ? 0x609D6E : 0x60B4CB);
            RED4ext::Vector2 stock{}, result{};
            uint8_t snapshot[0xA0]{};
            UWUI_TestStockFit(&stock, &input);
            UWUI_TestProbe(&UWUI_FitReferenceRectBoundary, &result, &input, snapshot);
            const bool expand = suppressed && !controller &&
                input.X / input.Y > 16.0f / 9.0f + 0.01f;
            const auto expected = expand ? input : stock;
            if (result.X != expected.X || result.Y != expected.Y)
            {
                std::printf("FAIL geometry %.0fx%.0f suppressed=%d controller=%d\n",
                    input.X, input.Y, suppressed, controller);
                return 1;
            }
            ++passed;
        }
    }
    // Null outputs must remain harmless to the adjustment itself.
    UWUI_AdjustFitReferenceRect(nullptr, nullptr, 0);
    std::printf("PASS %u production geometry cases: stock pillars, UW bounds, stock stick scale, 16:9\n", passed);
}
