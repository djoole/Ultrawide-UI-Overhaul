; Cyberpunk 2077's internal FitReferenceRect is a leaf with a stronger
; preservation contract than the Windows x64 ABI. In particular:
; - the pointer-scale helper keeps its destination in R8;
; - its caller keeps cursor state in R10/R11;
; - the cursor-clamp caller keeps the screen width in XMM5.
;
; Run the original trampoline without touching those registers, then preserve
; ALL of its volatile outputs (including flags) around the C++ adjustment.
; Thus stock dimensions and register side effects survive the controller
; exception, while the separate cursor clamp can still use ultrawide bounds.

OPTION CASEMAP:NONE
EXTERN UWUI_OriginalFitReferenceRect:QWORD
EXTERN UWUI_AdjustFitReferenceRect:PROC
PUBLIC UWUI_FitReferenceRectBoundary

.code
UWUI_FitReferenceRectBoundary PROC FRAME
    push rbp
    .pushreg rbp
    sub rsp, 0D0h
    .allocstack 0D0h
    lea rbp, [rsp+0D0h]
    .setframe rbp, 0D0h
    .endprolog

    ; 00..1F: Windows shadow space; 20: original input pointer.
    ; RSP is 16-byte aligned before both calls.
    mov [rsp+20h], rdx
    call QWORD PTR [UWUI_OriginalFitReferenceRect]

    mov [rsp+28h], rax
    mov [rsp+30h], rcx
    mov [rsp+38h], rdx
    mov [rsp+40h], r8
    mov [rsp+48h], r9
    mov [rsp+50h], r10
    mov [rsp+58h], r11
    movdqu [rsp+60h], xmm0
    movdqu [rsp+70h], xmm1
    movdqu [rsp+80h], xmm2
    movdqu [rsp+90h], xmm3
    movdqu [rsp+0A0h], xmm4
    movdqu [rsp+0B0h], xmm5
    pushfq
    pop QWORD PTR [rsp+0C0h]

    mov rcx, rax
    mov rdx, [rsp+20h]
    mov r8, [rsp+0D8h]       ; original game caller's return address
    call UWUI_AdjustFitReferenceRect

    movdqu xmm0, [rsp+60h]
    movdqu xmm1, [rsp+70h]
    movdqu xmm2, [rsp+80h]
    movdqu xmm3, [rsp+90h]
    movdqu xmm4, [rsp+0A0h]
    movdqu xmm5, [rsp+0B0h]
    mov rax, [rsp+28h]
    mov rcx, [rsp+30h]
    mov rdx, [rsp+38h]
    mov r8, [rsp+40h]
    mov r9, [rsp+48h]
    mov r10, [rsp+50h]
    mov r11, [rsp+58h]
    push QWORD PTR [rsp+0C0h]
    popfq
    ; A frame-pointer epilogue preserves flags AND is recognizable by the
    ; Windows unwinder (LEA RSP,[RSP+...] without a frame pointer is not).
    lea rsp, [rbp]
    pop rbp
    ret
UWUI_FitReferenceRectBoundary ENDP
END
