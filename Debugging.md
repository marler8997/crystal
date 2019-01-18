# Notes on Debugging Crystal

* make sure you assemble your bootloader with a list file (`nasm -l <listfile>`)
* start the emulator in bochs
* you'll get a prompt, set the breakpoint to the line of code you want to break at.
```
> lb <address>
```
The bootloader will be loaded at address `0x7c00` so to get to any line of the bootloader you will add its offset to this address.  For example, if you want to break at the bootloader at offset 0x99, you would invoke:
```
> lb 0x7c99
```
* continue to the breakpoint
```
> c
```
* you can now debug, here's some common debug commands
```
> n # go to the next instruction (do not follow calls)
> s # step to the next instruction (do follow calls)
> r # print registers
> sreg # print segment registers
> x <addr> # print memory at <addr>
> x /<count><format><size> <addr> # print non-default memory at addr
      # i.e. print 10 hex bytes at address 0x7c10: "x /10xb 0x7c10"
```

