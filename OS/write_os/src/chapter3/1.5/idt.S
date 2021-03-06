/*
   ref: Orange'S：一个操作系统的实现
   do the 5M memory r/w
 */
/* chapter3/1/loader.S

   Author: Wenbo Yang <solrex@gmail.com> <http://solrex.cn>

   This file is part of the source code of book "Write Your Own OS with Free
   and Open Source Software". Homepage @ <http://share.solrex.cn/WriteOS/>.

   This file is licensed under the GNU General Public License; either
   version 3 of the License, or (at your option) any later version. */

#include "pm.h"

.code16
.text
    jmp LABEL_BEGIN     /* jump over the .data section. */

/* NOTE! Wenbo-20080512: Actually here we put the normal .data section into
   the .code section. For application SW, it is not allowed. However, we are
   writing an OS. That is OK. Because there is no OS to complain about
   that behavior. :) */

/* Global Descriptor Table */
LABEL_GDT:          Descriptor  0,                        0, 0
LABEL_DESC_NORMAL:  Descriptor  0,         0xffff, DA_DRW    # Normal descriptor is for back to real mode.
LABEL_DESC_CODE32:  Descriptor  0,       (SegCode32Len - 1), (DA_C + DA_32)
LABEL_DESC_CODE16:  Descriptor    0,         0xffff, DA_C      # 非一致程式碼段, 16
LABEL_DESC_DATA:   Descriptor    0,      DataLen-1, DA_DRW    # Data
LABEL_DESC_STACK:  Descriptor    0,     TopOfStack, DA_DRWA+DA_32 # Stack, 32 位
LABEL_DESC_TEST: Descriptor 0x500000, 0xffff, DA_DRW
LABEL_DESC_VIDEO:   Descriptor  0xB8000, 0xffff, DA_DRW

.set GdtLen, (. - LABEL_GDT)  /* GDT Length */

GdtPtr: .2byte  (GdtLen - 1)  /* GDT Limit */
        .4byte  0             /* GDT Base */

/* GDT Selector */
.set SelectorNormal, (LABEL_DESC_NORMAL - LABEL_GDT)    
.set    SelectorCode32, (LABEL_DESC_CODE32 - LABEL_GDT)
.set SelectorCode16, (LABEL_DESC_CODE16 - LABEL_GDT)
.set SelectorData, (LABEL_DESC_DATA         - LABEL_GDT)
.set SelectorStack, (LABEL_DESC_STACK        - LABEL_GDT)
.set SelectorTest, (LABEL_DESC_TEST         - LABEL_GDT)
.set    SelectorVideo,  (LABEL_DESC_VIDEO  - LABEL_GDT)


/* Program starts here. */
LABEL_BEGIN:
    mov     %cs, %ax    /* Move code segment address(CS) to data segment */
    mov     %ax, %ds    /* register(DS), ES and SS. Because we have      */
    mov     %ax, %es    /* embedded .data section into .code section in  */
    mov     %ax, %ss    /* the start(mentioned in the NOTE above).       */

    movw     $0x100, %sp
    nop
    movw %ax, (LABEL_GO_BACK_TO_REAL+3) # modify segment value, indexed memory mode, ref  professional aeesmbly language p 102.
    movw     %sp, (SPValueInRealMode)


    /* Initialize 16-bits code segment descriptor. */
    xor     %eax, %eax
    mov     %cs, %ax
    shl     $4, %eax
    addl    $(LABEL_SEG_CODE16), %eax
    movw    %ax, (LABEL_DESC_CODE16 + 2)
    shr     $16, %eax
    movb    %al, (LABEL_DESC_CODE16 + 4)
    movb    %ah, (LABEL_DESC_CODE16 + 7)

    /* Initialize 32-bits code segment descriptor. */
    xor     %eax, %eax
    mov     %cs, %ax
    shl     $4, %eax
    addl    $(LABEL_SEG_CODE32), %eax
    movw    %ax, (LABEL_DESC_CODE32 + 2)
    shr     $16, %eax
    movb    %al, (LABEL_DESC_CODE32 + 4)
    movb    %ah, (LABEL_DESC_CODE32 + 7)

	# initialize data segment descriptor
	xor	%eax, %eax
	mov	%ds, %ax
	shl	$4, %eax
	addl	$(LABEL_DATA), %eax
	movw	%ax, (LABEL_DESC_DATA + 2)
	shr	$16, %eax
	movb	%al, (LABEL_DESC_DATA + 4)
	movb	%ah, (LABEL_DESC_DATA + 7)

	# initialize stack segment descriptor
	xor	%eax, %eax
	mov	%ds, %ax
	shl	$4, %eax
	addl	$(LABEL_STACK), %eax
	movw	%ax, (LABEL_DESC_STACK + 2)
	shr	$16, %eax
	movb	%al, (LABEL_DESC_STACK + 4)
	movb	%ah, (LABEL_DESC_STACK + 7)

    /* Prepared for loading GDTR */
    xor     %eax, %eax
    mov     %ds, %ax
    shl     $4, %eax
    add     $(LABEL_GDT), %eax      /* eax <- gdt base*/
    movl    %eax, (GdtPtr + 2)

    /* Prepared for loading IDTR */
    xor     %eax, %eax
    mov     %ds, %ax
    shl     $4, %eax
    add     $(LABEL_IDT), %eax      /* eax <- idt base*/
    movl    %eax, (idt_ptr + 2)

#  movb $'Z', _SavedIDTR

#  mov $0xb800,%ax
#  mov %ax,%gs
#  mov $0xa,%ah
#  mov _SavedIDTR,%al
#  mov %ax,%gs:((80*0)*2)

  sidt _SavedIDTR
  in $0x21, %al
  mov %al, (_SavedIMREG)
  #lidt _SavedIDTR
    /* Load GDTR(Global Descriptor Table Register) */
    lgdtw   GdtPtr

    /* Clear Interrupt Flags */
    cli
    lidt idt_ptr

    /* Open A20 line. */
    inb     $0x92, %al
    orb     $0b00000010, %al
    outb    %al, $0x92

    /* Enable protect mode, PE bit of CR0. */
    movl    %cr0, %eax
    orl     $1, %eax
    movl    %eax, %cr0

    /* Mixed-Size Jump. */
    ljmp $SelectorCode32, $0       /* Thanks to earthengine@gmail, I got */
                                    /* this mixed-size jump insn of gas.  */
                                    /* this calls far jump (ptr 16:32) in intel manual) */

LABEL_REAL_ENTRY:               # 從保護模式跳回到實模式就到了這裡
        mov     %cs, %ax
        mov     %ax, %ds
        mov     %ax, %es
        mov     %ax, %ss

#        mov     sp, [SPValueInRealMode]
        movw     (SPValueInRealMode), %sp

#  movb $0xc, %ah
#  movb _SavedIDTR, %al

#  mov $0xb800,%ax
#  mov %ax,%gs
#  mov $0xc,%ah
#  mov _SavedIDTR,%al
#  #mov $'U',%al
#  mov %ax,%gs:((80*0+39)*2)

  
  lidt _SavedIDTR
  mov (_SavedIMREG), %al
  out %al, $0x21

        in      $0x92, %al
        and     $0b11111101, %al   #  close A20 line
        out     %al, $0x92

        sti                     # 開中斷

        mov     $0x4c00, %ax
        int     $0x21             #  回到 DOS
# END of .code16

LABEL_SEG_CODE32: 
.code32

	mov	$(SelectorData), %ax
	mov	%ax, %ds			# 資料段選擇子
	mov	$(SelectorTest), %ax
	mov	%ax, %es			# 測試段選擇子




    mov     $(SelectorVideo), %ax
    mov     %ax, %gs                /* Video segment selector(dest) */

	mov	$(SelectorStack), %ax
	mov	%ax, %ss			# 堆疊段選擇子

	mov	$(TopOfStack), %esp

/*
    movl    $((80 * 10 + 0) * 2), %edi
    movb    $0xC, %ah               # 0000: Black Back 1100: Red Front 
    movb    $'P', %al

    mov     %ax, %gs:(%edi)
*/

#if 0
	# print string "In Protect Mode now. ^-^"
	movb	$0x0c, %ah # 0000: 黑底    1100: 紅字
	xor	%esi, %esi
	xor	%edi, %edi
	mov	$(OffsetPMMessage), %esi	# data string offset
	movl	$((80 * 10 + 0) * 2), %edi	# 目的資料偏移。螢幕第 10 行, 第 0 列。
	cld # Clear Direction Flag, ref: http://www.fermi.mn.it/linux/quarta/x86/cld.htm
            # After CLD is executed, string operations will increment the index 
            # (SI and/or DI) that they use. 
.1:
	lodsb # For legacy mode, Load byte at address DS:(E)SI into AL. 
              # For 64-bit mode load byte at address (R)SI into AL. 
              # ref: http://siyobik.info/main/reference/instruction/LODS%2FLODSB%2FLODSW%2FLODSD%2FLODSQ
	test	%al, %al # result is 0, zf sets to 1.
	jz	.2 # zf = 1 jump
#	mov	[gs:edi], ax
        mov     %ax, %gs:(%edi)
	add	$2, %edi
	jmp	.1
.2:	# 顯示完畢
#push  %eax                       # Multiboot magic number
#   push  %ebx                       # Multiboot data structure

#	call	kmain
	call	DispReturn
        #movb $0xa9, %al
	#call	DispAL

	call	TestRead
	call	TestWrite
	call	TestRead

#endif
  call init_8259a
    movl    $(2), %edi
    movb    $0xC, %ah               # 0000: Black Back 1100: Red Front 
    movb    $'8', %al
    mov     %ax, %gs:(%edi)

    int $0x80
    sti
    jmp .
  call set_real_mode_8259a

    ljmpl     $SelectorCode16,$0
    # jmpl     $SelectorCode16,$0 # it works

clock_handler:
.set clock_handler_offset, (. - LABEL_SEG_CODE32)
  incb %gs:((80 * 0 + 70) * 2) # (0, 70)
  mov $0x20, %al
  out %al, $0x20
  iretl

user_int_handler:
.set user_int_handler_offset, (. - LABEL_SEG_CODE32)
  mov $0xc, %ah
  mov $'I', %al
  mov %ax, %gs:((80 * 2 + 60) * 2) # (2, 60)
  iretl


spurious_handler:
.set spurious_handler_offset, (. - LABEL_SEG_CODE32)
  mov $0x0c, %ah
  mov $'*', %al
  mov %ax, %gs:((80 * 1 + 75) * 2) # (1, 75)
  jmp .
  iretl

io_delay:
  nop
  nop
  nop
  nop
  ret

init_8259a:
  mov $0x11, %al
  outb %al, $0x20
  call io_delay

  outb %al, $0xa0
  call io_delay

  mov $0x20, %al
  outb %al, $0x21
  call io_delay

  mov $0x28, %al
  outb %al, $0xa1
  call io_delay

  mov $0x04, %al
  outb %al, $0x21
  call io_delay

  mov $0x02, %al
  outb %al, $0xa1
  call io_delay

  mov $0x01, %al
  outb %al, $0x21
  call io_delay

  out %al, $0xa1
  call io_delay

  mov $0b11111110, %al
  out %al, $0x21
  call io_delay

  mov $0b11111111, %al
  out %al, $0xa1
  call io_delay

  ret

set_real_mode_8259a:
  mov $SelectorData, %ax
  mov %ax, %fs

  mov $0x17, %al
  out %al, $0x20
  call io_delay

  mov $0x8, %al
  out %al, $0x21
  call io_delay

  mov $0x1, %al
  out %al, $0x21
  call io_delay

  mov $saved_imreg_offset, %edi
  mov %fs:(%edi), %al
  out %al, $0x21
  call io_delay

  ret


# ------------------------------------------------------------------------
TestRead:
	xor	%esi, %esi
	mov	$8, %ecx
.loop:
	mov	%es:(%esi), %al
	call	DispAL
	inc	%esi
	loop	.loop
	call	DispReturn

	ret
# TestRead 結束-----------------------------------------------------------


# ------------------------------------------------------------------------
TestWrite:
	pushl	%esi
	pushl	%edi
	xor	%esi, %esi
	xor	%edi, %edi
	mov	$(OffsetStrTest), %esi	# data offset
	cld # Clear Direction Flag, ref: http://www.fermi.mn.it/linux/quarta/x86/cld.htm
            # After CLD is executed, string operations will increment the index 
            # (SI and/or DI) that they use. 
.6:
	lodsb # For legacy mode, Load byte at address DS:(E)SI into AL. 
              # For 64-bit mode load byte at address (R)SI into AL. 
              # ref: http://siyobik.info/main/reference/instruction/LODS%2FLODSB%2FLODSW%2FLODSD%2FLODSQ

	test	%al, %al
	jz	.5 # zf = 1 jump
#	mov	[es:edi], al
	mov	%al, %es:(%edi)
	inc	%edi
	jmp	.6
.5:

	popl	%edi
	popl	%esi
	ret
# TestWrite 結束----------------------------------------------------------


# ------------------------------------------------------------------------
# 顯示 AL 中的數字
# 默認地:
#	數字已經存在 AL 中
#	edi 始終指向要顯示的下一個字元的位置
# 被改變的暫存器:
#	ax, edi
# ------------------------------------------------------------------------
DispAL:
	pushl	%ecx
	pushl	%edx

	movb	$0x0c, %ah # 0000: 黑底    1100: 紅字
	movb	%al, %dl
	shr	$4, %al
	movl	$2, %ecx
.begin:
	andb	$0x0f, %al
	cmp	$9, %al
	ja	.3          # cf=0, zf=0, above 9 (>9)
	#addb	$'0', %al
	addb	$0x30, %al
	jmp	.4
.3:
	sub	$0x0A, %al
	#add	$'A', %al
	add	$0x41, %al
.4:
	#mov	[gs:edi], ax
	mov	%ax, %gs:(%edi)
	add	$2, %edi

	mov	%dl, %al
	loop	.begin
	add	$2, %edi

	popl	%edx
	popl	%ecx

	ret
# DispAL 結束-------------------------------------------------------------


# ------------------------------------------------------------------------
DispReturn:
	pushl	%eax
	pushl	%ebx
	mov	%edi, %eax
	movb	$160, %bl
	divb	%bl          # %eax/160, 商 al, 餘數 ah.
	and	$0x0FF, %eax
	inc	%eax         # ++ %eax
	mov	$160, %bl
	mul	%bl
	mov	%eax, %edi
	popl	%ebx
	popl	%eax
	ret
# DispReturn 結束---------------------------------------------------------

/*
kmain:
        pushl   %ebp
        movl    %esp, %ebp
        popl    %ebp
        ret
        .size   kmain, .-kmain
        .ident  "GCC: (Ubuntu/Linaro 4.5.2-8ubuntu4) 4.5.2"
*/
#        .section        .note.GNU-stack,"",@progbits


/* Get the length of 32-bit segment code. */
.set    SegCode32Len, . - LABEL_SEG_CODE32

#[SECTION .data1]         ; 資料段
#ALIGN   32
#[BITS   32]
LABEL_DATA:
SPValueInRealMode: .2byte 0x0
_SavedIDTR: .4byte 0x12345678
_SavedIDTR__: .4byte 0xabcdef35
.set saved_idtr_offset, (. - LABEL_DATA)
_SavedIMREG: .byte 0x0
.set saved_imreg_offset, (. - LABEL_DATA)
# string
PMMessage:              .ascii      "In Protect Mode now. ^-^\0"   # 在保護模式中顯示
.set    OffsetPMMessage, (PMMessage - LABEL_DATA)
#StrTest:                .ascii "B\0"
StrTest:                .ascii "ABCDEFGHIJKLMNOPQRSTUVWXYZ\0"
#OffsetStrTest           equ     StrTest - $$
.set OffsetStrTest , (StrTest - LABEL_DATA)
#DataLen                 equ     $ - LABEL_DATA
.set DataLen, .  - LABEL_DATA
/* 32-bit global stack segment. */
LABEL_STACK:
.space  512, 0
.set    TopOfStack, (. - LABEL_STACK - 1)

LABEL_IDT:
.rept 32
Gate SelectorCode32, spurious_handler_offset, 0, DA_386IGate
.endr

Gate SelectorCode32, clock_handler_offset, 0, DA_386IGate # 0x20
#Gate SelectorCode32, spurious_handler_offset, 0, DA_386IGate

.rept 95
Gate SelectorCode32, spurious_handler_offset, 0, DA_386IGate
.endr

Gate SelectorCode32, user_int_handler_offset, 0, DA_386IGate # 0x80

.set idt_len, (. - LABEL_IDT)  /* IDT Length */

idt_ptr: .2byte  (idt_len - 1)  /* IDT Limit */
         .4byte  0             /* IDT Base */


# END of [SECTION .data1]


LABEL_SEG_CODE16:
.code16
    #jmp     .
        # back to real mode
        mov     $SelectorNormal, %ax
        mov     %ax, %ds
        mov     %ax, %es
        mov     %ax, %fs
        mov     %ax, %gs
        mov     %ax, %ss

        mov     %cr0, %eax
        and     $0b11111110, %al
        mov     %eax, %cr0


LABEL_GO_BACK_TO_REAL:
#.2byte 0xea66
#.4byte 0x00000000
#.2byte LABEL_REAL_ENTRY
    jmp     $0, $LABEL_REAL_ENTRY      # 段位址會在程序開始處被設置成正確的值


.set Code16Len, . - LABEL_SEG_CODE16


