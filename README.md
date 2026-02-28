# Embedded Code Review Expert

A code review skill for embedded/firmware projects with **dual-model cross-review** support. Claude Code and Codex independently review the same diff, then findings are cross-compared to catch blind spots that single-model review misses.

## Features

### Review Capabilities
- **Memory Safety** — Stack overflow, buffer overrun, alignment, DMA cache coherence, heap fragmentation
- **Interrupt & Concurrency** — Volatile correctness, critical sections, ISR best practices, RTOS pitfalls (priority inversion, deadlock)
- **Hardware Interfaces** — Peripheral init ordering, register access patterns, I2C/SPI/UART/NFC protocol issues, clock & timing
- **C/C++ Pitfalls** — Undefined behavior, integer gotchas, compiler optimization traps, preprocessor hazards, portability
- **Architecture** — HAL/BSP layering, testability, configuration management
- **Security** — Debug interface exposure, firmware update integrity, side channels, input validation

### Dual-Model Cross-Review (via OpenClaw ACP)
- **Claude Code** reviews with embedded systems expertise
- **Codex (GPT-5.3)** reviews independently for heterogeneous perspective
- **Cross-comparison** identifies consensus bugs (high confidence) and model-specific catches
- Based on research: [arXiv:2602.03794](https://arxiv.org/abs/2602.03794) — heterogeneous models outperform homogeneous multi-agent setups

### Review Modes
| Mode | When | Cost |
|------|------|------|
| **Single-model** | Small diffs (≤100 lines), quick reviews | Low |
| **Dual-model** | New features, critical paths, architecture changes | Higher (2x model calls) |

## Target Environments

- Bare-metal MCU (STM32, nRF, ESP32, RP2040)
- RTOS (FreeRTOS, Zephyr, ThreadX)
- Linux embedded
- Mixed C/C++ firmware

## Installation

### As OpenClaw Skill
```bash
# Clone into workspace skills directory
cd ~/.openclaw/workspace/skills
git clone https://github.com/ylongwang2782/embedded-review.git
```

### As Claude Code Skill
```bash
mkdir -p ~/.claude/skills
git clone https://github.com/ylongwang2782/embedded-review.git ~/.claude/skills/embedded-review
```

## Usage

### Basic (single-model)
```
Review my current git changes in firmware-pro2
```

### Dual-model cross-review
```
用双模型 review firmware-pro2 feat/nfc 的改动
```

### Specific commit range
```
/embedded-review ~/Documents/dec/firmware-pro2 HEAD~5..HEAD
```

### GitHub PR
```
/embedded-review https://github.com/user/repo/pull/42
```

## How Dual-Model Works

```
User: "review firmware-pro2"
         │
    OpenClaw (orchestrator)
         │
    ┌────┴────┐
    │         │
Claude Code  Codex
(embedded    (independent
 checklist)   perspective)
    │         │
    └────┬────┘
         │
    Cross-Compare
    ├─ 🤝 Consensus → HIGH CONFIDENCE (real bugs)
    ├─ 🔵 Claude-only → may catch embedded-specific issues
    ├─ 🟢 Codex-only → heterogeneous blind spot catches
    └─ ⚠️ Contradictions → escalate to human
         │
    Unified Report
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
├── SKILL.md                          # Main skill (review workflow + ACP orchestration)
├── README.md                         # This file
├── LICENSE                           # MIT
├── scripts/
│   └── prepare-diff.sh              # Extract git diff and build review context
└── references/
    ├── memory-safety.md              # Stack, buffer, alignment, DMA, heap
    ├── interrupt-safety.md           # ISR, volatile, critical sections, RTOS
    ├── hardware-interface.md         # Peripherals, registers, protocols, timing
    └── c-pitfalls.md                 # UB, integers, compiler, preprocessor, portability
```

## Requirements

- OpenClaw with ACP enabled (for dual-model mode)
- Claude Code and/or Codex CLI configured as ACP agents
- Git (for diff extraction)
- Target repository accessible locally

## Credits

Dual-model cross-review approach inspired by [@LumaoDoggie](https://x.com/LumaoDoggie/status/2027356094813667416)'s Claude + Codex workflow and the research paper "Understanding Agent Scaling in LLM-Based Multi-Agent Systems via Diversity" (arXiv:2602.03794).

## License

MIT
