;
; NOTE: linux boot protocol can be found here:
;
;  https://github.com/torvalds/linux/blob/master/Documentation/x86/boot.txt
;
; Crystal Memory Map
; ------------------------------------------------------------------------------
; offset  | limit  | size              | Description
; ------------------------------------------------------------------------------
;         | 0x7c00 |                   | The stack (grows down from 0x7c00)
; 0x7c00  | 0x7e00 | 0x0200 (512)      | Bootsector load address
; 0x7e00  | 0x9c00 | 0x1e00 (512 * 15) | Crystal stage 2 load address
; 0x9c00  | 0x9e00 | 0x0200 (512)      | Kernel command line load address
; 0x9e00  | 0xa000 | 0x0200 (512)      | Initrd info load address
; ...
; 0x10000 |        |                   | The location where kernel setup code is loaded (not sure why)
; 0x20000 |        |                   | Temporary location to load kernel before copying to highmove_addr
; 0x100000|        |                   | Location where kernel is loaded (variable highmove_addr)
;                                        Note that it is not loaded here directly, it is loaded
;                                        to address 0x20000 and then moved here as it is read from disk.
;
        bits 16
        org 0x7c00

bootloader_reserve_sector_count equ 16
bootloader_size equ bootloader_end - $$

; These values are based on the offset the register will be stored
; after running pushad
ax_fmt equ 28
cx_fmt equ 24
dx_fmt equ 20
bx_fmt equ 16

start:
        ; initialize segments and stack
        xor ax, ax
        mov ds, ax
        mov ss, ax
        mov esp, 0x7c00          ; the stack grows down so we put it just below the bootloader
                                 ; so it won't overwrite it

        mov [boot_disk_num], dl  ; save the boot disk number (used in the read_disk function)

        ; print start message
        and dx, 0xFF
        mov ax, bootloader_size
        mov si, .msg_started_dx_ax
        call printfln

        ; calculate extra sector count to read
        ; todo: can I calculate this at compile time?
        mov ax, bootloader_size - 512
        mov bx, ax
        shr ax, 9      ; divide by 512
        and bx, 0x01ff ; get remainder
        cmp bx, 0
        jz .skip_add_sector
        inc ax
    .skip_add_sector:
        ; ax already contains the sector count
        mov si, .msg_loading_stage2_ax
        call printfln

        ; read in the rest of the bootloader
        ; ax already contains the sector count
        mov ebx, 0x0000_7e00 ; dest 0xssss_oooo s=segment, o=offset
        call read_disk

        mov dword [read_disk.next_sector], bootloader_reserve_sector_count

        jmp second_stage
    .msg_started_dx_ax:     db "crystal bootloader v0.0 (drive=%",dx_fmt,", size=%",ax_fmt,")", 0
    .msg_loading_stage2_ax: db "loading stage 2 (%",ax_fmt," sectors)", 0
read_disk:
        push eax
        push edx
        mov [.sector_count], ax                   ; populate extra arguments
        mov [.dest_segment_and_offset], ebx       ;
        mov edx, [.next_sector]                   ;
        mov dword [.src_lba], edx                 ;
        and eax, 0xffff                           ; increment .next_sector
        add edx, eax                              ;
        mov [.next_sector], edx                   ;
        ; call bios "extended read"
        mov ah, 0x42                              ; method 0x42
        mov si, .disk_address_packet              ;
        mov dl, [boot_disk_num]                   ; read from the boot disk
        int 0x13
        mov si, .error_msg_ax                     ; set error message in case we failed
        shr ax, 8                                 ; set the error code in ah to ax so it can
                                                  ; be included in the error message
        jc fatal_error
        pop edx
        pop eax
        ret
    .next_sector: ; static counter variable that tracks the next sector to read
        ; TODO: make the initial value configurable?
        dd 1 ; start at sector 1
    .disk_address_packet:
        db 0x10 ; size of the packet
        db 0    ; reserved
    .sector_count:
        dw 0
    .dest_segment_and_offset:
        dd 0
    .src_lba:
        dq 0; lba
    .error_msg_ax     db "read_disk failed (e=%",ax_fmt,")", 0
print_ecx_hex_with_prefix:
        push si
        mov si, print_ecx_hex.hex_prefix
        call printf
        pop si
print_ecx_hex:
        ; input: ecx = value to print
        push ecx
        pusha
        mov ax, sp          ; save stack pointer to restore it at the end
        dec sp              ; push terminating null onto stack
        mov [esp], byte 0   ;
    .loop:
        mov bl, cl
        and bl, 0xF
        cmp bl, 0xa
        jl .is_decimal
        add bl, 7           ; add offset to print 'a-f' instead of '0-9'
    .is_decimal:
        add bl, '0'         ; convert hex value to hex digit
        dec sp              ; push char
        mov [esp], bl
        shr ecx, 4
        cmp ecx, 0
        jnz .loop
        mov si, sp
        call printf
        mov sp, ax
        popa
        pop ecx
        ret
    .hex_prefix: db "0x", 0
printfln:
        call printf
print_newline:
        push si
        mov si, .newline
        call printf
        pop si
        ret
    .newline: db 13, 10, 0 ; 13='\r' 10='\n'
printf:
        ; input: si points to address of null-terminated string
        ; TODO: what do I set bh = page number to? 0?
        pushad
        mov ah, 0x0e                 ; Argument for interrupt 10 which says to
                                     ; print the character in al to the screen
    .next_char:
        lodsb                        ; load next byte from memory pointed to by si
                                     ; into al and increment si
        cmp al, '%'
        jne .not_format_spec
        lodsb
        cmp al, 'e'
        jne .not_32_bit
        lodsb                        ; it is a 32-bit value
        mov ebx, 0xFFFFFFFF
        jmp .print_reg
    .not_32_bit:
        mov ebx, 0xFFFF
    .print_reg:
        ; the value in al should represent one of the <reg>_fmt value
        ; which represent the register's offset in the stack after
        ; executing pushad
        xor edx, edx                         ; zero edx
        mov dl, al                           ; set edx to the register's stack offset
        add dx, sp                           ; add stack to edx
        mov ecx, [edx]                       ; read the register value from the stack
        and ecx, ebx                         ; mask the value (if we're not printing 32-bit)
        call print_ecx_hex_with_prefix
        jmp .next_char
    .not_format_spec:
        cmp al, 0
        je .done          ; If char is zero, end of string
    .print_al:
        int 10h                        ; Otherwise, print it
        jmp .next_char
    .done:
        ;pop ecx
        ;pop ebx
        ;pop eax
        popad
        ret
fatal_error:
        ; input: si points to address of null-terminated error message
        push si
        mov si, .prefix
        call printf
        pop si
        call printfln
        cli
        hlt
    .prefix: db "fatal error: ", 0
dev_break:
        mov si, .msg
        call printfln
        cli
        hlt
    .msg: db "dev break", 0

boot_disk_num: db 0
        ; this line ensures the boot sector code doesn't spill into
        ; the partition table of the MBR
        times 446 - ($-$$) db 0x00
        times 510 - ($-$$) db 0xcc; special value so you can see where the partition table is
        dw 0xAA55

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 2nd stage bootloader
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
second_stage:

        mov si, msg_at_stage2
        call printfln

        ; read the kernel command line sector
        mov ax, 1            ; sector_count
        mov ebx, 0x0000_9c00 ; dest 0xssss_oooo s=segment o=offset
        call read_disk

        ;
        ; read kernel command line
        ;
        xor bx, bx   ; zero out the counter
      .next_cmd_line_char:
        cmp [0x9c00+bx], byte 0
        jz .found_cmd_line_null
        inc bx
        mov si, error_msg.kernel_cmd_line_has_no_null_terminator
        cmp bx, 512
        je fatal_error
        jmp .next_cmd_line_char
      .found_cmd_line_null:
        mov [kernel_cmd_line_size], bx
        ; print the kernel command line
        mov si, msg_kernel_cmd_line_prefix_bx
        call printf
        mov si, 0x9c00
        call printf
        mov si, msg_kernel_cmd_line_suffix
        call printfln

        ;
        ;  get into protected mode so we can setup "unreal" mode
        ;  to access 32-addresses and load the kernel
        ;
        mov ax, 0x2401         ; enable A20 line
        int 0x15
        mov si, error_msg.enable_a20
        jc fatal_error

        lgdt [gdt_register_value]    ; load the global descriptor table
        mov eax, cr0                 ; enable protected mode bit in control register
        ; NOTE: do not modify eax until after 'back_to_real_mode'
        or eax, 1
        mov cr0, eax
        ; jmp $+2                ; WHAT DOES THIS DO???
        mov bx, 0x8 ; first descriptor in GDT
        mov ds, bx
        mov es, bx
        mov gs, bx
        and al, 0xfe ; 'back_to_real_mode'
        mov cr0, eax ; disable protected mode bit in control register

        ; restore segments registers
        xor ax, ax
        mov ds, ax
        mov gs, ax
        mov ax, 0x1000 ; set es to segment for kernel (starts being used below at "read kernel setup sectors")
        mov es, ax     ;
        sti

        ;
        ; now in "unreal" mode
        ;

        ; read the first sector of the kernel which tells us how many
        ; sectors to read for the rest of the kernel setup memory
        mov ax, 1            ; sector_count
        mov ebx, 0x1000_0000 ; dest 0xssss_oooo s=segment o=offset
        call read_disk

        ;
        ; read kernel setup sectors
        ;
        xor ah,ah                      ; zero ah so when we print ax it only shows al
        mov al, [es:0x1f1]             ; kernel setup size
        mov si, msg_kernel_setup_sector_count_ax ; print the size
        call printfln

        ; default to 4 sectors if we got a value of 0
        cmp ax, 0
        jne .skip_set_to_4
        mov ax, 4
    .skip_set_to_4:
        mov ebx, 0x1000_0200    ; dest 0xssss_oooo s=segment, o=offset
        call read_disk

        ;
        ; verify kernel boot version is >= 2.04
        ;
        mov dx, [es:0x206]
        mov si, msg_kernel_boot_version_dx
        call printfln
        mov si, error_msg.kernel_boot_version_too_old
        cmp dx, 0x204
        jb fatal_error

        ;
        ; TODO: check that the cmd_line_size is <= the maximum
        ;       command line size defined in the kernel which
        ;       would be found at es:0x238 (cmdline_size)
        ;       something like
        ;       mv si, error_msg.kernel_cmd_line_too_big_az
        ;       mov ax, [es:0x238]
        ;       cmp [kernel_cmd_line_size], ax
        ;       jg fatal_error

        ;
        ; check kernel loadflags to make sure LOADED_HIGH is true
        ;
        mov si, error_msg.kernel_not_loaded_high
        test byte [es:0x211],1
        jz fatal_error
        ; pass information to kernel
        mov byte  [es:0x210], 0xe1    ; 0xTV T=loader_type V=version
        mov byte  [es:0x211], 0x80    ; heap use? !! set bit5 to make kernel quiet
        mov word  [es:0x224], 0xde00  ; head_end_ptr
        mov byte  [es:0x227], 0x01    ; ext_loader_type / bootloader id
        mov dword [es:0x228], 0x1e000 ; cmd line ptr

        ; copy cmd line
        mov si, 0x9c00  ; kernel command line address
        mov di, 0xe000
        mov cx, [kernel_cmd_line_size]
        rep movsb                       ; copy from DS:si to ES:di

        ; load_kernel
        mov edx, [es:0x1f4]             ; syssize (size of protected-mode code in 16-byte paragraphs)
        shl edx, 4                      ; convert to bytes
        mov si, msg_loading_kernel_edx
        call printfln
        call loader_length_in_edx

        ; read initrd size
        mov ax, 1            ; sector count
        mov ebx, 0x0000_a000 ; dest 0xssss_oooo s=segment o=offset
        call read_disk

        mov edx, [0xa000]              ; get initrd size
        mov si, msg_loading_initrd_edx
        call printfln
        mov [es:0x21c], edx            ; tell kernel how big initrd is

        ; method 1 (load initrd right after the kernel)
        ;mov eax, [highmove_addr]      ; get the next load address, where initrd will be loaded
        ; method 2 (load initrd at this predefined address, qemu loads it here)
        mov eax, 0x7fab000
        mov [highmove_addr],eax        ; tell loader to load initrd here
        ; end of methods
        mov [es:0x218], eax            ; tell the kernel where the initrd lives
        call loader_length_in_edx

; start the kernel
        mov si, msg_jumping_to_kernel
        call printfln
        cli
        mov ax, 0x1000
        mov ds, ax
        mov es, ax
        mov fs, ax
        mov gs, ax
        mov ss, ax
        mov sp, 0xe000
        jmp 0x1020:0
        jmp $

loader_length_in_edx:
    .loop:
        ;mov si, .msg_size_left    ; print progress
        ;call printfln
        cmp edx, 512 * 127
        jl .read_last_part
    .read_127_sectors:
        mov ax, 127
        mov ebx, 0x2000_0000 ; 0xssss_oooo s=segment o=offset
        call read_disk
        call highmove
        sub edx, 512 * 127
        jmp .loop
    .read_last_part:
        jz .done
        shr edx, 9 ; divide by 512
        inc edx    ; increase by one in case it wasn't divisible by 512, loading more junk sectors is OK
        mov ax, dx
        mov ebx, 0x2000_0000 ; 0xssss_oooo s=segment o=offset
        call read_disk
        call highmove
    .done:
        ret
    .msg_size_left: db "%e",dx_fmt," bytes left to read...", 0

;; Move 127 sectors at address 0x20000 to the next address at highmove_addr
; source = 0x20000
; count = 512 * 127 fixed (note, copying junk at the end doesn't matter)
; don't think we can use rep movsb here as it won't use edi/esi in unreal mode
highmove_addr dd 0x100000
highmove:
        pushad
        mov esi, 0x20000
        mov edi, [highmove_addr]
        mov edx, 512 * 127
        mov ecx, 0                  ; pointer
    .loop:
        mov eax, [ds:esi]
        mov [ds:edi], eax
        add esi, 4
        add edi, 4
        sub edx, 4
        jnz highmove.loop
        mov [highmove_addr], edi
        popad
        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
gdt_register_value:
        dw gdt_end - gdt - 1
        dd gdt
gdt:
        dq 0          ; first entry 0
        ; flat data segment
        dw 0xffff     ; limit[0:15] (4gb)
        dw 0          ; base[0:15]
        db 0          ; base[16:23]
        db 0b10010010 ; access byte
        db 0b11001111 ; [7..4]=flage [3..0] = limit[16:19]
        db 0          ; base[24:31]
gdt_end:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

kernel_cmd_line_size: dw 0

msg_at_stage2:                    db "at stage 2", 0
msg_kernel_cmd_line_prefix_bx:    db "kernel cmd line (%", bx_fmt, " bytes) '",0
msg_kernel_cmd_line_suffix:       db "'", 0
msg_kernel_setup_sector_count_ax: db "kernel setup sector count: %",ax_fmt, 0
msg_kernel_boot_version_dx:       db "kernel boot version: %",dx_fmt, 0
msg_loading_kernel_edx:           db "loading kernel (%e",dx_fmt," bytes)...",0
msg_loading_initrd_edx:           db "loading initrd (%e",dx_fmt," bytes)...",0
msg_jumping_to_kernel:            db "jumping to kernel",0

error_msg:
.enable_a20                    db "failed to enable a20 line", 0
.kernel_boot_version_too_old   db "kernel version too old", 0
.kernel_not_loaded_high        db "kernel LOADED_HIGH is 0", 0
.kernel_cmd_line_has_no_null_terminator db "kernel cmd line sector has no NULL terminator", 0

bootloader_end:
