# Hardware Interface Checklist (Embedded)

## Peripheral Initialization Order

### Correct Sequence
```
1. Enable clock to peripheral        (RCC->APBxENR |= ...)
2. Configure GPIO pins              (alternate function, pull-up/down, speed)
3. Configure peripheral registers   (baud rate, mode, DMA, interrupts)
4. Enable peripheral                (USARTx->CR1 |= USART_CR1_UE)
5. Enable interrupt in NVIC         (NVIC_EnableIRQ)
```

### Common Mistakes
- Configuring peripheral BEFORE enabling its clock → writes to dead registers (silently ignored)
- Enabling NVIC interrupt BEFORE peripheral is fully configured → spurious interrupt on garbage state
- GPIO alternate function mismatch → pin works as GPIO, not peripheral
- Forgetting `__HAL_RCC_GPIOx_CLK_ENABLE()` → GPIO config has no effect
- **Ask**: "Is the clock enabled before this peripheral is configured?"

## Register Access Patterns

### Read-Modify-Write Hazards
```c
// DANGEROUS in ISR-accessible registers:
GPIOA->ODR |= (1 << 5);  // RMW: read ODR, OR bit, write ODR
// If ISR modifies another bit between read and write → that bit is lost

// SAFE: use atomic set/reset registers
GPIOA->BSRR = (1 << 5);       // Atomic set bit 5
GPIOA->BSRR = (1 << (5+16));  // Atomic reset bit 5
```

### Bit-Field Pitfalls
```c
// DANGEROUS: compiler may generate RMW for bit-field access
typedef struct {
    uint32_t MODE : 2;
    uint32_t SPEED : 2;
    uint32_t PULL : 2;
} GPIO_Bits;
// If ISR accesses different fields in same word → race condition

// SAFE: use explicit mask-and-shift
reg = (reg & ~MASK) | (value << SHIFT);
```

### Write-Only Registers
- Cannot read-modify-write (read returns undefined/zero)
- Must maintain a shadow copy in RAM
- Common: some interrupt clear registers, some LCD controllers
- **Ask**: "Is this register read-write or write-only?"

### Write-1-to-Clear (W1C)
```c
// DANGEROUS: clearing all flags unintentionally
USART1->SR = 0;  // May clear flags you didn't intend to clear

// CORRECT: write 1 only to the flag you want to clear
USART1->SR = ~USART_SR_TC;  // Clear TC, preserve others (on W1C registers)
// BUT: read the reference manual — some registers are W1C, others are W0C!
```

## Timing and Delays

### Required Delays
| Situation | Typical Delay | Why |
|-----------|--------------|-----|
| After clock enable | 2 clock cycles | Register access needs clock propagating |
| After PLL enable | Wait for PLLRDY | PLL lock time is non-deterministic |
| After ADC enable | T_STAB (µs) | Internal reference stabilization |
| After flash erase/write | Wait for BSY | Flash operation in progress |
| Peripheral reset release | Device-specific | IC needs time to initialize |
| I2C START condition | Per spec (4.7µs for 100kHz) | Bus timing requirement |
| External IC reset pin | Check datasheet | Power-on reset time varies widely |

### Busy-Wait vs Timeout
```c
// DANGEROUS: infinite wait
while (!(SPI1->SR & SPI_SR_TXE));  // Hangs if SPI is misconfigured

// SAFE: with timeout
uint32_t timeout = HAL_GetTick() + 100;
while (!(SPI1->SR & SPI_SR_TXE)) {
    if (HAL_GetTick() > timeout) {
        return ERROR_TIMEOUT;
    }
}

// ALSO DANGEROUS: timeout using loop counter
for (int i = 0; i < 100000; i++) {  // Compiler may optimize away!
    if (SPI1->SR & SPI_SR_TXE) break;
}
// Fix: make loop variable volatile, or use hardware timer
```

### Watchdog
- Feed watchdog in main loop, **not in ISR** (hides main loop hangs)
- Feed watchdog in **one place** — multiple feed points mask problems
- Don't feed during flash erase (may timeout if erase is slow → design for it)
- Window watchdog: feed too early is also a reset trigger
- **Ask**: "If this code path takes 10x longer than expected, will the watchdog fire?"

## Communication Protocols

### I2C
- **Bus recovery**: SDA stuck low → clock out 9+ SCL pulses to release
- **Clock stretching**: Slave holds SCL low — master must handle (timeout!)
- **Multi-master**: Arbitration loss handling — retry with backoff
- **Repeated START**: Don't send STOP between address and data for register reads
- **NACK handling**: Missing pull-ups, wrong address, or device not ready
- **Timing registers**: TIMINGR (STM32) must match actual bus speed — wrong prescaler = communication failure
- **Ask**: "What happens if the I2C device doesn't ACK?"

### SPI
- **Chip select timing**: CS must go low BEFORE clock starts, high AFTER last byte
- **Clock polarity/phase (CPOL/CPHA)**: Must match slave device — check datasheet
- **Full-duplex awareness**: Every read is also a write (and vice versa)
- **DMA with SPI**: Ensure TX DMA completes before de-asserting CS
- **Multiple slaves**: Each CS is independent — wrong CS pin = talking to wrong device
- **Ask**: "Are CPOL and CPHA set correctly for this device?"

### UART
- **Baud rate mismatch**: Clock source accuracy matters — HSI has ±1-5% tolerance
- **Buffer overrun**: UART receives while previous byte not read → data lost
- **DMA circular mode**: Position tracking with `NDTR` register
- **Idle line detection**: Useful for variable-length frame reception
- **RS-485**: Direction control timing — DE pin must be set before TX, cleared after
- **Ask**: "What happens if data arrives faster than it's processed?"

### NFC / Contactless
- **RF field timing**: Field on → wait for guard time → send command
- **FWT (Frame Waiting Time)**: Reader must wait long enough for card response
- **CRC handling**: Hardware CRC vs software — double-check which is enabled
- **Anti-collision**: Proper state machine for multi-card environments
- **Power budget**: Card emulation power from field — complex operations may brownout
- **NCI protocol**: Check for proprietary notifications (e.g., `6F xx`) mixed with standard responses

## GPIO Configuration

### Common Mistakes
- **Speed setting too low**: High-speed peripheral (SPI >10MHz) on low-speed GPIO → signal integrity issues
- **Speed setting too high**: Unnecessary EMI, increased power consumption
- **Missing pull-up/pull-down**: Open-drain outputs (I2C) need external pull-ups
- **Push-pull on shared bus**: I2C must be open-drain — push-pull = bus conflict
- **Analog mode for unused pins**: Saves power, reduces leakage
- **Lock register**: GPIO pins can be locked to prevent accidental reconfiguration
- **Ask**: "Is this pin configured correctly for the peripheral it serves?"

## Clock Configuration

### Critical Checks
- **HSE vs HSI**: External crystal accuracy vs internal RC tolerance
- **PLL multiplication/division**: Output frequency must not exceed MCU max
- **Flash wait states**: Must increase BEFORE increasing clock speed
- **Peripheral clock dividers**: APB1/APB2 prescalers affect timer frequencies
- **Timer clock**: If APBx prescaler ≠ 1, timer clock = 2× APBx clock (common trap)
- **USB requires 48MHz ± 0.25%**: HSI usually too inaccurate
- **Ask**: "Has the clock tree been verified against the reference manual?"

## Power Management

- **Sleep mode entry**: Pending interrupts prevent sleep — check NVIC
- **Peripheral clock gating**: Disable unused peripheral clocks to save power
- **GPIO state during sleep**: Floating inputs consume extra current
- **Wake-up source**: Not all peripherals can wake from all sleep modes
- **Voltage regulator scaling**: Low-power mode may limit max clock speed
- **Ask**: "Is this peripheral disabled when not in use?"

## DMA Configuration

### Common Mistakes
- **Wrong DMA channel/stream**: Each peripheral maps to specific DMA channels
- **Direction mismatch**: Peripheral-to-memory vs memory-to-peripheral
- **Data width mismatch**: Peripheral is 8-bit, DMA configured for 16-bit
- **Memory increment**: Forgot to enable → all data goes to same address
- **Circular vs normal mode**: Circular keeps running — normal stops after count
- **Transfer complete vs half-transfer**: Use half-transfer for double-buffering
- **Priority**: DMA channels can starve each other
- **Ask**: "Is this DMA configuration consistent with the peripheral's data register width?"
