OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x0;
  .text.init : { *(.text.init) }
  .text : { *(.text) }
  . = ALIGN(0x800);
  .data : { *(.data) }
  .bss : { *(.bss) }
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }
  _end = .;
}
