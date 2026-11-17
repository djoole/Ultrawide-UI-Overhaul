# Controller cursor investigation — 2.5.9

Report: 5120x2160, Steam Controller through Steam Input; cursor does not move
with UI Overhaul alone, jumps towards corners when Scanner HUD is also enabled.
Local user cannot reproduce with 3440x1440 / DualSense through DSX.

## Verified against local 2.5 executable and release object

- Repository is clean at main / v2.5.9, commit 7f2cc41.
- Native override excludes return RVA 0x609D6E from geometry replacement.
- However, exclusion is evaluated AFTER calling the original function AND
  GetModuleHandleW(nullptr). It only preserves returned dimensions, not the
  original function's register-preservation behavior.
- Game helper at RVA 0x609D44 stores its destination pointer in R8, calls
  FitReferenceRect at 0x609D69, then writes through R8 at 0x609D8D / 0x609D93.
  It expects R8 to survive the call.
- Analog routine at RVA 0x60B5B4 keeps state pointers in R10 and R11, calls
  that helper at 0x60B65C, then uses R11 at 0x60B661 and R10 at 0x60B69A etc.
  It expects those registers to survive the nested helper too.
- Clamp caller keeps width in XMM5 across FitReferenceRect at 0x60B4C6,
  then uses XMM5 at 0x60B4DA and 0x60B503. It must also retain UW bounds.
- Release object native/build-2.5.9/BlackPillarsRemover.obj was disassembled
  with Capstone. FitReferenceRectOverride calls its original trampoline and
  GetModuleHandleW unconditionally, including the excluded controller path.
  It does not save R8/R10/R11/XMM5 around those calls. These are volatile
  under the standard Windows x64 calling convention.

This is an actual mismatch with the engine callers' observed expectations.
It is a plausible cause of controller failures; the reporter's particular
failure is NOT yet reproduced or confirmed as fixed. Resolution and Steam
Input have not been isolated as causes.

## Scanner HUD and aspect checks

- Local installed Scanner HUD 1.1.0 only observes scanner/quickhack controller
  initialization and changes HUD widget widths/margins. No controller input
  override, cursor scale hook, or DLL in that examined version.
- Reporter may have a different version; do not generalize this audit to
  their installation without checking.
- 5120/2160 = 2.370370..., 3440/1440 = 2.388888.... Both pass the same
  native ultrawide thresholds. No resolution-specific switch found here.

## Next implementation/validation

Preserve the engine's required register state at the native hook boundary,
including calls that return stock dimensions. Do not merely change the
excluded return RVA or alter Lua layouts. Verify generated machine code
and register preservation with an adversarial native harness, then test
mouse, stick, D-pad, menus and access-point hacking. User validation and
reporter confirmation are required before calling this the confirmed fix.

No tracked source, installation, settings, branch or release was changed
during this investigation.
