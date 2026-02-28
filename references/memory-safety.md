# Memory Safety Checklist (Embedded)

## Stack Overflow

- **Large local arrays**: `uint8_t buf[2048]` on a task with 512-byte stack → instant corruption
- **Deep recursion**: Recursive parsers, tree walks on constrained stack
- **alloca / VLA**: Variable-length arrays on stack — size from external input is a bomb
- **Nested function calls**: Especially with large structs passed by value
- **FreeRTOS stack**: Check `uxTaskGetStackHighWaterMark()` — is headroom < 20%?
- **Ask**: "What's the worst-case stack depth of this call chain?"

## Buffer Overrun

| Dangerous | Safe Alternative |
|-----------|-----------------|
| `sprintf(buf, ...)` | `snprintf(buf, sizeof(buf), ...)` |
| `strcpy(dst, src)` | `strncpy` or `strlcpy` |
| `strcat(dst, src)` | `strncat` with remaining size |
| `gets(buf)` | `fgets(buf, size, stdin)` |
| `memcpy(dst, src, len)` | Validate `len <= dst_size` first |
| `scanf("%s", buf)` | `scanf("%255s", buf)` with width |

- **Array indexing**: Is `index < ARRAY_SIZE` checked before access?
- **Loop bounds**: Does the loop variable stay within buffer limits?
- **Protocol parsing**: Length field from wire data used as memcpy size without validation?
- **Ask**: "What if the input is longer than expected?"

## Memory Alignment

- **Casting `uint8_t*` to `uint32_t*`**: Unaligned access → HardFault on Cortex-M0/M0+
  ```c
  // DANGEROUS on strict-align targets:
  uint32_t val = *(uint32_t*)&rx_buf[3];
  
  // SAFE:
  uint32_t val;
  memcpy(&val, &rx_buf[3], sizeof(val));
  ```
- **Packed structs**: `__attribute__((packed))` forces unaligned access — compiler may generate slow byte-by-byte loads or fault
- **DMA buffer alignment**: Many peripherals require 4-byte or cache-line (32-byte) alignment
  ```c
  __attribute__((aligned(32))) uint8_t dma_buf[256];
  ```
- **Ask**: "Is this pointer guaranteed to be aligned for this access width?"

## DMA & Cache Coherence

- **Cache invalidate before DMA read**: CPU cache may hold stale data
  ```c
  SCB_InvalidateDCache_by_Addr(rx_buf, len);  // before reading DMA result
  ```
- **Cache clean before DMA write**: DMA reads from main memory, not cache
  ```c
  SCB_CleanDCache_by_Addr(tx_buf, len);  // before starting DMA TX
  ```
- **Volatile on DMA buffers**: Compiler may optimize away reads if it thinks value hasn't changed
- **Double-buffer / ping-pong**: Is the inactive buffer truly inactive before CPU touches it?
- **MPU regions**: DMA buffers in non-cacheable region avoids coherence issues entirely
- **Ask**: "Who else (DMA, another core) is touching this memory?"

## Memory-Mapped I/O

- **Missing volatile**: Hardware register access without `volatile` → compiler may cache/reorder/eliminate reads/writes
  ```c
  // WRONG: compiler may optimize away the read
  while (USART1->SR & USART_SR_RXNE) { ... }
  
  // RIGHT: register pointer is volatile in CMSIS headers
  // But watch out for custom register definitions!
  ```
- **Read-modify-write race**: `REG |= BIT` is three operations — ISR can change REG between read and write
  - Use atomic bit-banding (Cortex-M3/M4) or critical section
- **Write-only registers**: Reading a write-only register returns undefined value — can't do `REG |= BIT`
- **Ask**: "Is this register access atomic? Could an ISR interfere?"

## Heap Usage

- **Avoid malloc/free in embedded if possible**: Fragmentation in long-running systems
- **If using heap**:
  - Is there a defined max heap size? What happens on allocation failure?
  - Are all `malloc` return values checked for NULL?
  - Is `free` called exactly once per `malloc`?
  - Any heap use from ISR context? (usually forbidden)
- **FreeRTOS heap schemes**: heap_1 (no free), heap_4 (coalescing), heap_5 (multiple regions)
- **Static allocation**: Prefer `configSUPPORT_STATIC_ALLOCATION` where possible
- **Ask**: "What happens after running for 30 days non-stop?"

## Common Patterns to Flag

```c
// 1. Unbounded copy from external input
void handle_packet(uint8_t *data, uint16_t len) {
    uint8_t local_buf[64];
    memcpy(local_buf, data, len);  // P0: len could be > 64
}

// 2. Stack array too large for task
void process(void) {
    uint8_t frame[4096];  // P1: likely exceeds task stack
}

// 3. Unaligned access
uint16_t get_word(uint8_t *p) {
    return *(uint16_t*)p;  // P1: unaligned on M0
}

// 4. Missing NULL check
char *p = malloc(128);
memset(p, 0, 128);  // P0: p could be NULL
```
