OPTION CASEMAP:NONE
PUBLIC UWUI_TestStockFit
PUBLIC UWUI_TestProbe
PUBLIC UWUI_TestProbeReturn
IFDEF UWUI_BOUNDARY_CONTRACT_TEST
EXTERN UWUI_TestAdjustedResult:QWORD
EXTERN UWUI_TestAdjustedInput:QWORD
EXTERN UWUI_TestCaller:QWORD
EXTERN UWUI_TestStackAlignment:QWORD
PUBLIC UWUI_AdjustFitReferenceRect
ENDIF

.const
ALIGN 16
pattern BYTE 16 DUP (05Ah), 16 DUP (0A5h), 16 DUP (033h)
        BYTE 16 DUP (0CCh), 16 DUP (066h), 16 DUP (099h)
aspect REAL4 1.7777777778
inverseAspect REAL4 0.5625

.code
; Stock fitter substitute with distinctive volatile outputs. No C++ ABI
; assumptions: the probe records those outputs before calling anything else.
UWUI_TestStockFit PROC
    movss xmm0, DWORD PTR [rdx]
    movss xmm1, DWORD PTR [rdx+4]
    movaps xmm2, xmm1
    mulss xmm2, DWORD PTR [aspect]
    comiss xmm0, xmm2
    jbe fitHeight
    movaps xmm0, xmm2
    jmp fitted
fitHeight:
    movaps xmm1, xmm0
    mulss xmm1, DWORD PTR [inverseAspect]
fitted:
    movss DWORD PTR [rcx], xmm0
    movss DWORD PTR [rcx+4], xmm1
    mov rax, rcx
    mov rcx, 1111111111111111h
    mov rdx, 2222222222222222h
    mov r8, 8888888888888888h
    mov r9, 9999999999999999h
    mov r10, 0AAAAAAAAAAAAAAAAh
    mov r11, 0BBBBBBBBBBBBBBBBh
    movdqu xmm0, XMMWORD PTR [pattern]
    movdqu xmm1, XMMWORD PTR [pattern+10h]
    movdqu xmm2, XMMWORD PTR [pattern+20h]
    movdqu xmm3, XMMWORD PTR [pattern+30h]
    movdqu xmm4, XMMWORD PTR [pattern+40h]
    movdqu xmm5, XMMWORD PTR [pattern+50h]
    cmp rax, rax
    stc
    ret
UWUI_TestStockFit ENDP

; RCX=function, RDX=result, R8=input, R9=snapshot. Snapshot offsets match
; BoundaryHarness.cpp. Record immediately so no compiler can hide corruption.
UWUI_TestProbe PROC FRAME
    push rbx
    .pushreg rbx
    sub rsp, 20h
    .allocstack 20h
    .endprolog
    mov rax, rcx
    mov rbx, r9
    mov rcx, rdx
    mov rdx, r8
    call rax
UWUI_TestProbeReturn LABEL BYTE
    mov [rbx], rax
    mov [rbx+08h], rcx
    mov [rbx+10h], rdx
    mov [rbx+18h], r8
    mov [rbx+20h], r9
    mov [rbx+28h], r10
    mov [rbx+30h], r11
    pushfq
    pop QWORD PTR [rbx+38h]
    movdqu [rbx+40h], xmm0
    movdqu [rbx+50h], xmm1
    movdqu [rbx+60h], xmm2
    movdqu [rbx+70h], xmm3
    movdqu [rbx+80h], xmm4
    movdqu [rbx+90h], xmm5
    add rsp, 20h
    pop rbx
    ret
UWUI_TestProbe ENDP

IFDEF UWUI_BOUNDARY_CONTRACT_TEST
; Deliberately hostile but ABI-compliant adjustment. It destroys EVERY
; volatile register, while recording the actual arguments and stack alignment.
UWUI_AdjustFitReferenceRect PROC
    mov [UWUI_TestAdjustedResult], rcx
    mov [UWUI_TestAdjustedInput], rdx
    mov [UWUI_TestCaller], r8
    mov rax, rsp
    and rax, 0Fh
    mov [UWUI_TestStackAlignment], rax
    mov DWORD PTR [rcx], 045A00000h ; 5120.0: output adjustment must survive
    xor eax, eax
    xor ecx, ecx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    xor r10d, r10d
    xor r11d, r11d
    pxor xmm0, xmm0
    pxor xmm1, xmm1
    pxor xmm2, xmm2
    pxor xmm3, xmm3
    pxor xmm4, xmm4
    pxor xmm5, xmm5
    clc
    ret
UWUI_AdjustFitReferenceRect ENDP
ENDIF
END
