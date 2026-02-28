# Embedded Code Review Expert

A code review skill for embedded/firmware projects. Performs structured reviews with a senior embedded engineer lens, covering memory safety, interrupt correctness, RTOS pitfalls, hardware interfaces, and C/C++ language traps.

## Installation

```bash
mkdir -p ~/.claude/skills
git clone <repo-url> ~/.claude/skills/embedded-review
```

Or copy `SKILL.md` and `references/` into your AI agent's skill directory.

## Features

- **Memory Safety** — Stack overflow, buffer overrun, alignment, DMA cache coherence, heap fragmentation
- **Interrupt & Concurrency** — Volatile correctness, critical sections, ISR best practices, RTOS pitfalls (priority inversion, deadlock)
- **Hardware Interfaces** — Peripheral init ordering, register access patterns, I2C/SPI/UART/NFC protocol issues, clock & timing
- **C/C++ Pitfalls** — Undefined behavior, integer gotchas, compiler optimization traps, preprocessor hazards, portability
- **Architecture** — HAL/BSP layering, testability, configuration management
- **Security** — Debug interface exposure, firmware update integrity, side channels, input validation

## Target Environments

- Bare-metal MCU (STM32, nRF, ESP32, etc.)
- RTOS (FreeRTOS, Zephyr, ThreadX)
- Linux embedded
- Mixed C/C++ firmware

## Usage

After installation, the skill auto-activates for embedded code review:

```
Review my current git changes
```

Or explicitly invoke:

```
/embedded-review
```

## Severity Levels

| Level | Name | Action |
|-------|------|--------|
| P0 | Critical | Must block merge — memory corruption, security, hardware damage |
| P1 | High | Fix before merge — race condition, UB, resource leak |
| P2 | Medium | Fix or follow-up — code smell, portability, missing error handling |
| P3 | Low | Optional — style, naming, documentation |

## Structure

```
embedded-review/
├── SKILL.md                          # Main skill definition
├── README.md                         # This file
└── references/
    ├── memory-safety.md              # Stack, buffer, alignment, DMA, heap
    ├── interrupt-safety.md           # ISR, volatile, critical sections, RTOS
    ├── hardware-interface.md         # Peripherals, registers, protocols, timing
    └── c-pitfalls.md                 # UB, integers, compiler, preprocessor, portability
```

## License

MIT
