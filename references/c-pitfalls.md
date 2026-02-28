# C/C++ Pitfalls Checklist (Embedded)

## Undefined Behavior (UB)

### The Dangerous Ones
```c
// 1. Signed integer overflow (UB in C, defined wrapping in unsigned)
int32_t a = INT32_MAX;
a += 1;  // UB! Compiler may assume this never happens and optimize based on that

// 2. Null pointer dereference
int *p = NULL;
int x = *p;  // UB — may crash, may silently read address 0 (which is valid on some MCUs!)

// 3. Uninitialized local variables
int x;
if (x > 0) { ... }  // UB — x could be anything

// 4. Accessing array out of bounds
int arr[10];
arr[10] = 42;  // UB — may corrupt adjacent stack variables silently

// 5. Sequence point violations
i = i++ + ++i;  // UB — modification + read without sequence point

// 6. Strict aliasing violation
float f = 3.14;
uint32_t bits = *(uint32_t*)&f;  // UB (strict aliasing)
// SAFE: use memcpy or __attribute__((may_alias))
uint32_t bits;
memcpy(&bits, &f, sizeof(bits));
```

### Embedded-Specific UB Traps
- Dereferencing address 0 on Cortex-M: Address 0 is the vector table — reading it returns the initial stack pointer, not a crash
- Writing to const-qualified flash memory location: May trigger HardFault or silently fail
- Modifying a `const` object through pointer cast: UB even if the cast compiles

## Integer Issues

### Implicit Conversions
```c
// 1. Unsigned to signed narrowing
uint32_t big = 0xFFFFFFFF;
int16_t small = big;  // Implementation-defined, likely -1 or truncated

// 2. Sign extension surprise
int8_t signed_byte = 0xFF;  // = -1
uint32_t extended = signed_byte;  // = 0xFFFFFFFF, not 0xFF!
// Fix: cast through unsigned first
uint32_t correct = (uint8_t)signed_byte;  // = 0xFF

// 3. Integer promotion in expressions
uint8_t a = 200, b = 100;
uint8_t c = a + b;  // Promoted to int, result 300, truncated to 44
// No warning from most compilers!

// 4. Comparison of signed and unsigned
int x = -1;
unsigned int y = 0;
if (x < y) { ... }  // FALSE! -1 is converted to UINT_MAX
```

### Shift Operations
```c
// Shifting by >= type width is UB
uint32_t x = 1;
uint32_t y = x << 32;  // UB

// Shifting negative values is UB (left shift) or implementation-defined (right shift)
int x = -1;
int y = x << 1;   // UB
int z = x >> 1;   // Implementation-defined (arithmetic vs logical shift)

// Shift amount should always be checked
void set_bit(uint32_t *reg, int bit) {
    if (bit >= 0 && bit < 32)  // Guard!
        *reg |= (1U << bit);   // Note: 1U, not 1 (avoids signed shift)
}
```

### Division
```c
// Division by zero is UB (even for unsigned)
uint32_t ratio = total / count;  // Must check count != 0

// Integer division truncates toward zero (C99+)
int x = -7 / 2;  // = -3, not -4
int y = -7 % 2;  // = -1 (sign follows dividend in C99+)
```

## Compiler & Optimization Traps

### volatile Misuse
```c
// volatile tells compiler: "this value may change without your knowledge"
// REQUIRED for:
// - Hardware registers (MMIO)
// - Variables shared with ISR
// - Variables shared between RTOS tasks (in addition to synchronization)

// NOT a substitute for:
// - Atomic operations (volatile doesn't guarantee atomicity)
// - Memory barriers (volatile doesn't prevent CPU reordering on multi-core)
// - Mutexes/critical sections (volatile doesn't provide mutual exclusion)

// WRONG: volatile pointer vs pointer to volatile
volatile uint32_t *reg = (volatile uint32_t*)0x40001000;  // pointer to volatile (CORRECT)
uint32_t *volatile ptr;  // volatile pointer to non-volatile (rarely what you want)
```

### Optimization Surprises
```c
// 1. Dead store elimination
void clear_secret(uint8_t *buf, size_t len) {
    memset(buf, 0, len);  // Compiler may remove this if buf isn't used after
}
// Fix: use volatile or explicit_bzero/SecureZeroMemory

// 2. Loop removal
// Compiler may remove delay loops with no side effects
for (volatile int i = 0; i < 1000; i++);  // volatile prevents removal
// Better: use hardware timer for precise delays

// 3. Reordering
x = 1;
y = 2;
// Compiler may swap these. If hardware ordering matters:
x = 1;
__DMB();  // Data Memory Barrier
y = 2;
```

### Compiler-Specific Gotchas
- `-O2` or `-Os` may break code that depends on UB (especially integer overflow checks)
- `-fno-strict-aliasing` is common in embedded (Linux kernel uses it)
- Different compilers handle packed structs differently (padding, alignment)
- `#pragma once` vs include guards: `#pragma once` not guaranteed by standard (but widely supported)

## Preprocessor Hazards

### Macro Pitfalls
```c
// 1. Missing parentheses
#define SQUARE(x) x * x
int y = SQUARE(1 + 2);  // = 1 + 2 * 1 + 2 = 5, not 9
// Fix:
#define SQUARE(x) ((x) * (x))

// 2. Double evaluation
#define MAX(a, b) ((a) > (b) ? (a) : (b))
int z = MAX(i++, j);  // i++ evaluated twice if i > j!
// Fix: use inline function or GCC statement expression
#define MAX(a, b) ({ typeof(a) _a = (a); typeof(b) _b = (b); _a > _b ? _a : _b; })

// 3. Macro with semicolon
#define LOG(msg) printf("%s\n", msg);
if (debug)
    LOG("test");  // Semicolon creates empty statement, else attaches wrong
else
    ...
// Fix: use do { ... } while(0)
#define LOG(msg) do { printf("%s\n", msg); } while(0)

// 4. Stringification and token pasting
#define STR(x) #x      // STR(foo) → "foo"
#define CONCAT(a,b) a##b  // CONCAT(foo,bar) → foobar
// Nested macros need indirection:
#define XSTR(x) STR(x)  // XSTR(VERSION) → "3" (expands VERSION first)
```

### Conditional Compilation
```c
// 1. #if vs #ifdef
#define FEATURE 0
#ifdef FEATURE   // TRUE — FEATURE is defined (even though it's 0)
#if FEATURE      // FALSE — FEATURE is 0

// 2. Include guard naming collision
// Use unique names: PROJECT_MODULE_FILE_H
#ifndef FIRMWARE_PRO2_NFC_HANDLER_H
#define FIRMWARE_PRO2_NFC_HANDLER_H
...
#endif

// 3. Unintended macro expansion in includes
#define status 0  // Now every use of "status" in included headers is broken
```

## Linker & Memory Layout

### Common Issues
- **Missing `extern "C"`**: C++ name mangling prevents C linkage
  ```c
  #ifdef __cplusplus
  extern "C" {
  #endif
  void ISR_Handler(void);  // Must use C linkage for vector table
  #ifdef __cplusplus
  }
  #endif
  ```
- **Weak symbol surprises**: `__weak` default handlers silently swallow errors
- **Section placement**: Critical code/data in wrong memory region (flash vs SRAM vs DTCM)
  ```c
  __attribute__((section(".dtcm_data"))) uint8_t fast_buffer[1024];
  ```
- **Stack/heap overlap**: Linker script must separate stack, heap, and static data
- **.bss initialization**: Zero-init depends on startup code — verify it runs before main

### Startup Code
- Global constructors (C++): Called before main — no RTOS, no heap yet
- Static initialization order: Undefined across translation units (C++ "fiasco")
- `__libc_init_array` must be called for C++ static constructors

## Portability

### Dangerous Assumptions
| Assumption | Reality |
|-----------|---------|
| `sizeof(int) == 4` | int is 16-bit on some targets (MSP430, AVR) |
| `sizeof(long) == 4` | long is 8 bytes on 64-bit hosts (affects host-target tests) |
| `char` is signed | ARM default is unsigned char; x86 default is signed |
| Byte order is little-endian | Network protocols and some peripherals use big-endian |
| `NULL == 0` | True in C, but null pointer may not be all-zero-bits on exotic targets |
| Struct layout matches wire format | Padding, alignment, endianness all differ |

### Fixed-Width Types
```c
// ALWAYS use <stdint.h> types in embedded:
uint8_t, int8_t, uint16_t, int16_t, uint32_t, int32_t
// NOT: char, short, int, long (sizes vary by platform)

// For "at least N bits" (allows compiler to pick efficient size):
uint_fast8_t, uint_least8_t

// For pointer-sized integers:
uintptr_t, intptr_t
```

### Endianness
```c
// Converting between host and network/protocol byte order:
uint16_t __builtin_bswap16(uint16_t);
uint32_t __builtin_bswap32(uint32_t);

// Or portable approach:
uint16_t read_be16(const uint8_t *p) {
    return ((uint16_t)p[0] << 8) | p[1];
}

// Don't do this:
uint16_t val = *(uint16_t*)packet;  // Wrong endian + possibly unaligned
```

## Questions for Every Review
1. Any signed/unsigned comparison or implicit narrowing?
2. Any shift by variable amount without bounds check?
3. Any `volatile` missing on ISR-shared or MMIO variables?
4. Any macro that evaluates arguments more than once?
5. Any pointer cast that violates alignment or strict aliasing?
6. Any assumption about `sizeof(int)` or byte order?
7. Any function callable from both C and C++ without `extern "C"`?
