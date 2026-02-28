# Interrupt & Concurrency Safety Checklist (Embedded)

## Shared Variable Access

### The Golden Rule
Any variable accessed from **both ISR and main/task context** MUST be:
1. Declared `volatile` (prevents compiler optimization)
2. Accessed atomically OR inside a critical section

```c
// WRONG: compiler may cache 'flag' in register, loop never exits
bool flag = false;
void ISR(void) { flag = true; }
void main(void) { while (!flag); }

// RIGHT:
volatile bool flag = false;
void ISR(void) { flag = true; }
void main(void) { while (!flag); }

// BUT volatile alone isn't enough for multi-byte values:
volatile uint32_t counter;  // 32-bit read is atomic on Cortex-M, but...
volatile uint64_t timestamp; // 64-bit read is NOT atomic — needs critical section
```

### Atomicity by Width (ARM Cortex-M)
| Width | Atomic on Cortex-M3/M4? | Notes |
|-------|------------------------|-------|
| 8-bit | Yes (LDRB/STRB) | Safe without protection |
| 16-bit | Yes (LDRH/STRH) | If naturally aligned |
| 32-bit | Yes (LDR/STR) | If naturally aligned |
| 64-bit | **No** | Needs critical section or LDREXD/STREXD |
| struct | **No** | Always needs critical section |

### Questions to Ask
- "Is this variable accessed from ISR? Is it volatile?"
- "Is this access atomic for the target architecture?"
- "What happens if the ISR fires between these two lines?"

## Critical Sections

### Bare-metal
```c
// Method 1: Global interrupt disable (simplest, blocks ALL interrupts)
uint32_t primask = __get_PRIMASK();
__disable_irq();
// ... critical section ...
__set_PRIMASK(primask);  // Restore previous state, don't blindly enable

// Method 2: BASEPRI (Cortex-M3+ only, allows higher-priority IRQs)
__set_BASEPRI(configMAX_SYSCALL_INTERRUPT_PRIORITY);
// ... critical section ...
__set_BASEPRI(0);
```

### FreeRTOS
```c
// From task context:
taskENTER_CRITICAL();    // Disables interrupts up to configMAX_SYSCALL_INTERRUPT_PRIORITY
// ... critical section ...
taskEXIT_CRITICAL();

// From ISR context:
UBaseType_t saved = taskENTER_CRITICAL_FROM_ISR();
// ... critical section ...
taskEXIT_CRITICAL_FROM_ISR(saved);

// WRONG: using task version in ISR or vice versa → undefined behavior
```

### Anti-patterns
- Critical section too long (>10µs) — increases interrupt latency
- Forgetting to restore interrupt state (using `__enable_irq()` instead of restoring PRIMASK)
- Nested critical sections without proper save/restore
- **Ask**: "How long is this critical section? Can it be shorter?"

## ISR Best Practices

### What NOT to do in ISR
| Forbidden | Why | Alternative |
|-----------|-----|-------------|
| `printf` / logging | Slow, may use heap, not reentrant | Set flag, print in main loop |
| `malloc` / `free` | Not ISR-safe, fragmentation | Pre-allocate buffers |
| Floating point (without lazy stacking) | Corrupts FPU context | Use integer math or ensure FPU context save |
| Blocking calls (`delay`, `mutex_lock`) | ISR can't block | Use `FromISR` variants, defer to task |
| Long computation | Increases latency for all interrupts | Defer to task via queue/semaphore |

### FreeRTOS API in ISR
```c
// WRONG:
void UART_IRQHandler(void) {
    xQueueSend(queue, &data, portMAX_DELAY);  // WRONG: task version, may block
}

// RIGHT:
void UART_IRQHandler(void) {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;
    xQueueSendFromISR(queue, &data, &xHigherPriorityTaskWoken);
    portYIELD_FROM_ISR(xHigherPriorityTaskWoken);  // Context switch if needed
}
```

### ISR Hygiene
- Clear interrupt flag BEFORE processing (to avoid re-entry on level-triggered)
- Or clear AFTER if edge-triggered (to catch events during processing)
- Check which interrupt source fired (multi-source IRQ handlers)
- Keep ISR < 1µs if possible; < 10µs maximum

## RTOS-Specific Pitfalls

### Priority Inversion
```
Task A (high priority) waits for mutex held by Task C (low priority)
Task B (medium priority) preempts Task C
→ Task A is effectively blocked by Task B
```
- **Fix**: Use `xSemaphoreCreateMutex()` (supports priority inheritance), not binary semaphore
- **Ask**: "Is this mutex shared between tasks of different priority?"

### Deadlock
- Task A locks Mutex 1, then tries to lock Mutex 2
- Task B locks Mutex 2, then tries to lock Mutex 1
- **Fix**: Always acquire mutexes in the same order; use timeout instead of `portMAX_DELAY`
- **Ask**: "What other mutexes might this task hold when acquiring this one?"

### Task Starvation
- High-priority task never blocks → lower tasks never run
- `taskYIELD()` only yields to same-priority tasks, not lower
- **Fix**: Ensure high-priority tasks block on event/queue/delay

### Stack Overflow (RTOS)
- Each task has its own stack — allocated at creation, not growable
- `configCHECK_FOR_STACK_OVERFLOW` should be **2** during development
- Use `uxTaskGetStackHighWaterMark()` to check remaining stack
- **Rule of thumb**: Allocate 1.5-2x the measured high-water mark

### Queue/Semaphore Misuse
- Queue full → `xQueueSend` blocks (timeout!) or drops data
- Semaphore give without take → count overflow (binary semaphore max 1)
- Event group bits set from ISR must use `xEventGroupSetBitsFromISR()`

## Race Condition Patterns

```c
// 1. Check-then-act (non-atomic)
if (uart_rx_ready) {           // ISR sets this
    process(uart_rx_buffer);   // ISR may overwrite buffer HERE
    uart_rx_ready = false;
}
// Fix: copy buffer in critical section, then process outside

// 2. Read-modify-write on hardware register
GPIOA->ODR |= GPIO_PIN_5;     // ISR modifying other GPIOA pins can corrupt
// Fix: use BSRR register (atomic set/reset) or critical section

// 3. Multi-byte update torn read
void ISR(void) {
    timestamp_high++;  // ISR updates high word
    timestamp_low = 0; // then low word
}
void main(void) {
    uint32_t h = timestamp_high;  // could read new high + old low
    uint32_t l = timestamp_low;
}
// Fix: read in critical section, or use sequence counter pattern

// 4. Shared peripheral access
// Task A configures SPI for device 1 (CPOL=0)
// Task B configures SPI for device 2 (CPOL=1) — preempts A mid-transfer
// Fix: mutex per peripheral bus
```

## Questions for Every ISR Review
1. Is the ISR flag cleared properly?
2. Are all shared variables volatile?
3. Are multi-byte shared accesses protected?
4. Is the ISR short enough? (<10µs?)
5. Any blocking or heap operations?
6. Using `FromISR` variants of RTOS API?
7. Is `portYIELD_FROM_ISR` called when needed?
