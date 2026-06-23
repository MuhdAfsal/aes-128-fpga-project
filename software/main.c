/******************************************************************************
* Engineer: Muhammed Afsal
* 
* Date: 2026/06/11
* Description: Bare-metal software application to test the AES-128
*              Hardware Accelerator on Zybo Z7-10.
*
******************************************************************************/

#include <stdio.h>
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "sleep.h"

// Define Base Address of the Custom IP
// NOTE: Check your generated "xparameters.h" in the Vitis platform project
// to verify the base address name. Vivado usually generates a name like
// XPAR_AES_AXI_LITE_0_S00_AXI_BASEADDR or XPAR_AES_COPROCESSOR_0_BASEADDR
#ifdef XPAR_AES_AXI_LITE_0_S00_AXI_BASEADDR
#define AES_BASE_ADDR XPAR_AES_AXI_LITE_0_S00_AXI_BASEADDR
#else
// Fallback default address if xparameters name is different
#define AES_BASE_ADDR 0x43C00000 
#endif

// Register Offsets (in bytes)
#define REG_PLAIN_0  0x00  // Plaintext [127:96]
#define REG_PLAIN_1  0x04  // Plaintext [95:64]
#define REG_PLAIN_2  0x08  // Plaintext [63:32]
#define REG_PLAIN_3  0x0C  // Plaintext [31:0]

#define REG_KEY_0    0x10  // Cipher Key [127:96]
#define REG_KEY_1    0x14  // Cipher Key [95:64]
#define REG_KEY_2    0x18  // Cipher Key [63:32]
#define REG_KEY_3    0x1C  // Cipher Key [31:0]

#define REG_CIPHER_0 0x20  // Ciphertext [127:96] (Read Only)
#define REG_CIPHER_1 0x24  // Ciphertext [95:64] (Read Only)
#define REG_CIPHER_2 0x28  // Ciphertext [63:32] (Read Only)
#define REG_CIPHER_3 0x2C  // Ciphertext [31:0] (Read Only)

#define REG_CONTROL  0x30  // Control Register: Bit 0 = Start, Bit 1 = Soft Reset
#define REG_STATUS   0x34  // Status Register: Bit 0 = Done (Read Only)

// Function Declarations
void print_128bit(const char* label, u32 w0, u32 w1, u32 w2, u32 w3);
void run_aes_test(u32* key, u32* plaintext, u32* expected_ciphertext);

int main()
{
    print("--- AES-128 Encryption Accelerator Test on Zybo Z7-10 ---\n\r");
    xil_printf("Using Custom IP base address: 0x%08X\n\r", AES_BASE_ADDR);

    // Standard AES-128 Test Vector (FIPS 197)
    // Key:       2b7e1516 28aed2a6 abf71588 09cf4f3c
    // Plaintext: 3243f6a8 885a308d 313198a2 e0370734
    // Expected:  3ad77bb4 0d7a3660 a89ecaf3 2466ef97
    
    u32 key[4] = {
        0x2B7E1516, 
        0x28AED2A6, 
        0xABF71588, 
        0x09CF4F3C
    };

    u32 plaintext[4] = {
        0x3243F6A8, 
        0x885A308D, 
        0x313198A2, 
        0xE0370734
    };

    u32 expected_ciphertext[4] = {
        0x3925841D, 
        0x02DC09FB, 
        0xDC118597, 
        0x196A0B32
    };

    run_aes_test(key, plaintext, expected_ciphertext);

    print("--- AES Accelerator Test Completed ---\n\r");
    return 0;
}

void print_128bit(const char* label, u32 w0, u32 w1, u32 w2, u32 w3) {
    xil_printf("%s: %08X %08X %08X %08X\n\r", label, w0, w1, w2, w3);
}

void run_aes_test(u32* key, u32* plaintext, u32* expected_ciphertext) {
    u32 ct[4];
    u32 status;
    int timeout = 1000;

    print_128bit("Input Key       ", key[0], key[1], key[2], key[3]);
    print_128bit("Input Plaintext ", plaintext[0], plaintext[1], plaintext[2], plaintext[3]);

    // 1. Reset the core (assert soft reset bit 1)
    Xil_Out32(AES_BASE_ADDR + REG_CONTROL, 0x02);
    usleep(10); // Wait short duration
    Xil_Out32(AES_BASE_ADDR + REG_CONTROL, 0x00); // Release reset

    // 2. Load Key registers
    Xil_Out32(AES_BASE_ADDR + REG_KEY_0, key[0]);
    Xil_Out32(AES_BASE_ADDR + REG_KEY_1, key[1]);
    Xil_Out32(AES_BASE_ADDR + REG_KEY_2, key[2]);
    Xil_Out32(AES_BASE_ADDR + REG_KEY_3, key[3]);

    // 3. Load Plaintext registers
    Xil_Out32(AES_BASE_ADDR + REG_PLAIN_0, plaintext[0]);
    Xil_Out32(AES_BASE_ADDR + REG_PLAIN_1, plaintext[1]);
    Xil_Out32(AES_BASE_ADDR + REG_PLAIN_2, plaintext[2]);
    Xil_Out32(AES_BASE_ADDR + REG_PLAIN_3, plaintext[3]);

    // 4. Trigger Encryption (assert start bit 0)
    print("Triggering AES hardware encryption core...\n\r");
    Xil_Out32(AES_BASE_ADDR + REG_CONTROL, 0x01);

    // 5. Poll the status register done bit
    status = Xil_In32(AES_BASE_ADDR + REG_STATUS);
    while ((status & 0x01) == 0 && timeout > 0) {
        status = Xil_In32(AES_BASE_ADDR + REG_STATUS);
        timeout--;
        usleep(10);
    }

    if (timeout == 0) {
        print("[ERROR] AES Encryption Hardware Accelerator Timeout!\n\r");
        return;
    }

    // 6. Read back ciphertext
    ct[0] = Xil_In32(AES_BASE_ADDR + REG_CIPHER_0);
    ct[1] = Xil_In32(AES_BASE_ADDR + REG_CIPHER_1);
    ct[2] = Xil_In32(AES_BASE_ADDR + REG_CIPHER_2);
    ct[3] = Xil_In32(AES_BASE_ADDR + REG_CIPHER_3);

    // 7. Clear start bit (to allow next cycle)
    Xil_Out32(AES_BASE_ADDR + REG_CONTROL, 0x00);

    // 8. Print Results
    print_128bit("Hardware Cipher ", ct[0], ct[1], ct[2], ct[3]);
    print_128bit("Expected Cipher ", expected_ciphertext[0], expected_ciphertext[1], expected_ciphertext[2], expected_ciphertext[3]);

    // Verification check
    if (ct[0] == expected_ciphertext[0] &&
        ct[1] == expected_ciphertext[1] &&
        ct[2] == expected_ciphertext[2] &&
        ct[3] == expected_ciphertext[3]) {
        print("[SUCCESS] AES hardware acceleration verified successfully!\n\r");
    } else {
        print("[FAIL] Mismatch between hardware results and golden vectors!\n\r");
    }
}
