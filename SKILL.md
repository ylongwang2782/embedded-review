---
name: embedded-review
description: "Expert code review for embedded/firmware projects. Detects memory safety, interrupt hazards, RTOS pitfalls, hardware interface bugs, and C/C++ anti-patterns with a senior embedded engineer lens."
---

# Embedded Code Review Expert

## Overview

Perform a structured review of current git changes in embedded/firmware projects. Covers memory safety, interrupt correctness, RTOS patterns, hardware interface bugs, and C-specific pitfalls. Default to review-only output unless the user asks to implement changes.

Target environments: bare-metal MCU, RTOS (FreeRTOS/Zephyr/ThreadX), Linux embedded, mixed C/C++ firmware.

## Severity Levels

| Level | Name | Description | Action |
|-------|------|-------------|--------|
| **P0** | Critical | Memory corruption, interrupt safety violation, security vulnerability, brick risk | Must block merge |
| **P1** | High | Race condition, resource leak, undefined behavior, RTOS misuse | Should fix before merge |
| **P2** | Medium | Code smell, portability issue, missing error handling, suboptimal pattern | Fix or create follow-up |
| **P3** | Low | Style, naming, documentation, minor suggestion | Optional improvement |

## Workflow

### 1) Preflight — scope & target identification

- Use `git status -sb`, `git diff --stat`, and `git diff` to scope changes.
- Identify the target: MCU family, RTOS, compiler (GCC ARM, IAR, ARMCC), build system (CMake, Make, Keil).
- Use `rg` or `grep` to find related modules — especially ISRs, DMA configs, linker scripts, and peripheral drivers.
- Identify critical paths: interrupt handlers, boot sequence, communication stacks, cryptographic operations.

**Edge cases:**
- **No changes**: Inform user; offer to review staged changes or a commit range.
- **Large diff (>500 lines)**: Summarize by file/module first, then review in batches by subsystem (BSP, drivers, app logic).
- **Mixed HAL + application**: Review HAL/driver layer with stricter hardware-safety lens; application layer with architecture lens.

### 2) Memory safety scan

- Load `references/memory-safety.md` for detailed checklist.
- Look for:
  - **Stack overflow risk**: Large local arrays, deep recursion, unbounded alloca
  - **Buffer overrun**: Missing bounds checks on memcpy/sprintf/array indexing
  - **Alignment violations**: Casting `uint8_t*` to wider types, packed struct access on strict-align targets
  - **DMA buffer issues**: Cache coherence, alignment requirements, volatile marking
  - **Memory-mapped I/O**: Missing volatile, read-modify-write races on hardware registers
  - **Heap fragmentation**: malloc/free patterns in long-running systems
  - **Use-after-free / double-free**: Dynamic memory in ISR context or across task boundaries
- Flag any use of `sprintf`, `strcpy`, `gets`, `strcat` — suggest bounded alternatives.

### 3) Interrupt & concurrency correctness

- Load `references/interrupt-safety.md` for detailed checklist.
- Look for:
  - **Shared variable access**: Variables accessed from ISR + main/task without volatile or atomic
  - **Critical section issues**: Missing `__disable_irq()` / `taskENTER_CRITICAL()` around shared state
  - **ISR duration**: Heavy work in ISR (printf, malloc, floating point, blocking calls)
  - **Priority inversion**: RTOS mutex without priority inheritance
  - **Reentrancy**: Non-reentrant functions called from multiple contexts (strtok, static buffers)
  - **Signal/flag races**: Check-then-act on flags without atomic operations
  - **Nested interrupt handling**: Incorrect NVIC priority grouping or masking
  - **RTOS API in ISR**: Using non-`FromISR` variants of FreeRTOS calls

### 4) Hardware interface review

- Load `references/hardware-interface.md` for detailed checklist.
- Look for:
  - **Peripheral init ordering**: Clock enable before peripheral config, GPIO before peripheral
  - **Register access patterns**: Read-modify-write without protection, wrong bit-field width
  - **Timing violations**: Missing delays after reset/enable, violating setup/hold times
  - **Pin conflicts**: Same pin configured for multiple peripherals
  - **Clock configuration**: PLL miscalculation, peripheral clock divider errors
  - **Power sequencing**: Peripheral use before power domain is stable
  - **Watchdog**: Missing feed in long operations, feed in ISR hiding hangs
  - **Communication protocols**: I2C/SPI/UART buffer management, timeout handling, bus error recovery

### 5) C/C++ language pitfalls

- Load `references/c-pitfalls.md` for detailed checklist.
- Look for:
  - **Undefined behavior**: Signed overflow, null dereference, uninitialized variables, sequence point violations
  - **Integer issues**: Implicit narrowing, sign extension, shift width >= type width
  - **Compiler assumptions**: Missing volatile, optimization removing "dead" stores to hardware registers
  - **Linker issues**: Missing `extern "C"`, weak symbol conflicts, section placement
  - **Preprocessor hazards**: Macro side effects, missing parentheses, token pasting bugs
  - **Portability**: Endianness assumptions, `sizeof(int)` assumptions, compiler-specific extensions
  - **Type safety**: Void pointer arithmetic, enum underlying type assumptions

### 6) Architecture & maintainability

- Apply embedded-relevant subset of SOLID:
  - **Layering**: Is HAL/BSP properly separated from application logic?
  - **Abstraction**: Can you swap the MCU/board without rewriting application code?
  - **Coupling**: Are peripheral drivers depending on application-specific types?
  - **Testability**: Can logic be unit-tested off-target (on host PC)?
  - **Configuration**: Magic numbers for register values, pin assignments, timing constants
- Check for dead code, unused `#define`s, commented-out blocks.

### 7) Security scan (embedded-specific)

- Look for:
  - **Secret storage**: Keys/credentials in flash without protection (readout protection, secure enclave)
  - **Debug interfaces**: JTAG/SWD left enabled in production builds
  - **Firmware update**: Unsigned OTA, no rollback protection, no anti-downgrade
  - **Side channels**: Timing-dependent comparisons for auth (use constant-time compare)
  - **Fault injection**: Missing redundant checks for critical decisions (unlock, crypto verify)
  - **Input validation**: External data (UART/USB/BLE/NFC) parsed without bounds checking
  - **Stack canaries**: Compiler protection enabled? (`-fstack-protector`)

### 8) Output format

```markdown
## Embedded Code Review Summary

**Target**: [MCU/Board] | [RTOS/Bare-metal] | [Compiler]
**Files reviewed**: X files, Y lines changed
**Overall assessment**: [APPROVE / REQUEST_CHANGES / COMMENT]

---

## Findings

### P0 - Critical (must block)
(none or list)

### P1 - High (fix before merge)
1. **[file:line]** Brief title
   - Description of issue
   - Risk: what can go wrong (crash, data corruption, security breach, hardware damage)
   - Suggested fix (with code if applicable)

### P2 - Medium (fix or follow-up)
...

### P3 - Low (optional)
...

---

## Hardware/Timing Concerns
(register access, peripheral init, timing-sensitive code)

## Architecture Notes
(layering, testability, portability observations)
```

### 9) Next steps confirmation

After presenting findings, ask user how to proceed:

```markdown
---
## Next Steps

I found X issues (P0: _, P1: _, P2: _, P3: _).

**How would you like to proceed?**
1. **Fix all** - I'll implement all suggested fixes
2. **Fix P0/P1 only** - Address critical and high priority
3. **Fix specific items** - Tell me which issues to fix
4. **No changes** - Review complete
```

**Important**: Do NOT implement changes until user explicitly confirms.

## Resources

### references/

| File | Purpose |
|------|---------|
| `memory-safety.md` | Buffer, stack, heap, DMA, alignment checklist |
| `interrupt-safety.md` | ISR, concurrency, RTOS, atomic operations checklist |
| `hardware-interface.md` | Peripheral, register, timing, protocol checklist |
| `c-pitfalls.md` | UB, integer, compiler, preprocessor, portability checklist |
