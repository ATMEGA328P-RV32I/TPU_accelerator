# Custom Tensor Processing Unit (TPU) for 1D CNN Inference

A fully custom, cycle-accurate Tensor Processing Unit (TPU) written in SystemVerilog, designed specifically for running 1D Convolutional Neural Network (CNN) inference. 

This architecture is tailored for time-series data processing, specifically **ECG (Electrocardiogram) Anomaly Detection**. It features a custom instruction set, a 5x5 systolic array for matrix multiplication, and hardware-accelerated pooling and softmax functions.

**Author:** Atul Kumar  
**Year:** 2026  
**License:** GNU Affero General Public License v3 (AGPL-3.0)

---

## Key Features

*   **Custom Instruction Set Architecture (ISA):** Driven by a 128-bit custom instruction set for loading, convolution, pooling, and dense layer execution.
*   **5x5 Systolic Array Math Core:** Implements highly parallel Multiply-Accumulate (MAC) operations utilizing an `im2col` sliding window buffer for efficient 1D convolutions.
*   **Unified Activation Buffer (UAB):** VLIW-style custom SRAM block storing 4x32-bit words per address, using AXI4-inspired 40-bit address spaces to maintain high throughput with the MAC arrays.
*   **Fixed-Point Arithmetic:** Uses optimized **Q8.8 fixed-point** representation. Multiplication results are natively truncated back to Q8.8 to save hardware resources without losing precision.
*   **Hardware ReLU & Softmax:** 
    *   Pooling engine includes a zero-latency hardware ReLU via multiplexers (clipping negative values to `32'sd0`).
    *   Custom `tpu_softmax` engine uses a highly optimized Lookup Table (LUT) to translate logit differences directly into anomaly vs. normal probabilities without expensive floating-point exponentials.
*   **Overflow Protection:** The Dense Engine uses a custom 48-bit massive accumulator to prevent overflow during deep dot-products.

---

## Hardware Architecture

The TPU consists of several specialized processing engines arbitrated by a top-level controller:

### 1. `tpu_top` (Top-Level Wrapper)
Integrates all sub-modules, memories (IRAM, WRAM, UAB), and the master bus controller. It arbitrates UAB access between the Host, Convolution Engine, Pooling Engine, and Dense Engine.

### 2. `tpu_controller` (Instruction Sequencer)
Fetches 128-bit instructions from the Instruction RAM (IRAM) and triggers the appropriate execution engines. 
*   **Opcode `1`:** Load
*   **Opcode `2`:** Convolution 1D
*   **Opcode `3`:** Max Pooling
*   **Opcode `4`:** Dense / Fully Connected
*   **Opcode `F`:** Halt / Done

### 3. `tpu_conv1d_engine` & `systolic_core`
The workhorse of the TPU. It uses an `im2col_buffer` to format incoming 1D serial data into a parallel 5-element sliding window, feeding it into a 5x5 Systolic MAC array. Uses modulo/division math to efficiently map 1D weight streams onto the 2D physical grid. 

### 4. `tpu_pool_engine`
Performs Max Pooling and ReLU activation. It features a "traffic cop" toggle mechanism to manage the memory bandwidth mismatch (reading 1 row per cycle from UAB but requiring 2 rows to perform a max comparison). 

### 5. `tpu_dense_engine`
Calculates the final fully-connected layers. Reads weights from WRAM and activations from UAB. Features a 48-bit accumulator (`accum`) to safely sum hundreds of 32-bit × 16-bit multiplications without overflowing.

---

## Memory Subsystem

*   **IRAM (Instruction RAM):** Holds the 128-bit microcode instructions. Programmed by the host prior to execution.
*   **WRAM (Weight RAM):** Holds the static weights and biases for the network (Q8.8 16-bit format). 
*   **UAB (Unified Activation Buffer):** Intermediary memory where all engines read input feature maps and write output feature maps. 4096 deep × 128-bit wide (4 blocks of 32-bits).

---

## Simulation and Testing

A comprehensive testbench (`tb_tpu.sv`) is included. It simulates a complete ECG anomaly detection inference pass:

1.  **Boot & Load:** The host programs the IRAM with a sequence of 4 instructions (Conv ➔ Pool ➔ Dense ➔ Halt).
2.  **Weight Loading:** Pre-loads the WRAM with specific `conv_weights`, `conv_biases`, `dense_w`, and `dense_biases`.
3.  **Data Ingestion:** Loads 260 samples of Q8.8 formatted ECG data into the UAB.
4.  **Execution:** Asserts `host_start`. The TPU automatically streams the data through the systolic core, pools the results, runs the dense layer, and halts.
5.  **Output:** The TPU flags the result via the `anomaly_flag` pin and outputs confidence percentages on `prob_normal_out` and `prob_anomaly_out`.

### Running the Testbench
You can run this using any standard SystemVerilog simulator (e.g., ModelSim, Questa, Vivado, or Verilator):
```bash
# Example using generic verilog compilation
xvlog -sv *.sv
xelab tb_tpu
xsim tb_tpu -run all
