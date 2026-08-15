# EdgeTX Automation Lua Scripts

A collection of non-destructive utility scripts designed to automate repetitive setup tasks on EdgeTX-compatible transmitters. These scripts scan your active model configuration and dynamically append the necessary curves, logical switches, mixes, and special functions without overwriting your existing settings.

---

> [!WARNING]
> **DISCLAIMER: USE AT YOUR OWN RISK**
> These scripts modify active model configurations, including mixer lines, curves, and logical switches. Incorrect configuration or unexpected script behavior could result in corrupted model files, loss of control, or unexpected flyaways. 
> 
> *   **Always backup your radio's models and settings** using EdgeTX Companion before running any script.
> *   **Always perform bench testing (WITH PROPELLERS REMOVED!)** to verify that all switch overrides, mixes, and safety cutoffs function as intended before attempting flight.
> *   The authors accept no responsibility for damage, injury, or data loss resulting from the use of these scripts.

---

## Installation

1. Connect your transmitter to your computer via USB in **SD Card Connection** mode.
2. Copy the `.lua` files from this repository into the `/SCRIPTS/TOOLS/` directory on your transmitter's SD card.
3. Disconnect USB, turn on your radio, long-press the **SYS** (System) button, and navigate to the **Tools** menu.
4. Select the desired script from the list to launch its interactive setup wizard.

---

## Included Scripts

### 1. Auto Wobble Setup (`auto_wob.lua`)
**Purpose:** Automates the configuration of the PID Toolbox "infinite wobble" controller. This setup induces controlled rolling/pitching oscillations to assist in telemetry-based PID tuning.

*   **Resources Appended:**
    *   **2 Logical Switches** (loop controls for the oscillation sequence).
    *   **4 Custom 17-Point Curves** (`R1`, `R2` for Roll; `P1`, `P2` for Pitch) to generate smoothed alternating sine wave signals.
    *   **4 Mixers** (appended in **ADD** mode to CH1 Aileron and CH2 Elevator to overlay wobble oscillations on top of normal stick inputs).
*   **User Configurable Options:**
    *   **Wobble Switch:** Physical trigger switch to activate the oscillations (options: `sh↓`, `sf↓`, `sg↓`).
    *   **Wobble Weight:** Amplitude percentage of the oscillation (10% to 100%).

---

### 2. Chirp Setup Wizard (`chirp_setup.lua`)
**Purpose:** Configures UAVTech's log-sine chirp setpoint sequence (designed by Wood2026). This is used to sweep through a range of frequencies on Roll and Pitch to analyze drone dynamics and transfer functions.

*   **Resources Appended:**
    *   **4 Logical Switches** (latching, timing, and sequence phase shifting).
    *   **4 Custom 17-Point Smoothed Curves** (`Sc1` to `Sc4`) mapped to specific logarithmic spacing intervals.
    *   **8 Mixers** (4 added to CH1 Roll and 4 added to CH2 Pitch, sequenced with ascending delay and speed settings).
*   **User Configurable Options:**
    *   **Chirp Switch:** Main physical trigger switch (options: `sc↑`, `sd↓`, `sf↓`).
    *   **Safety Switch:** Safety/Arm switch position required to execute the chirp (options: `sb-`, `sc-`, `sa-`).
    *   **Chirp Weight:** Setpoint deflection amplitude (5% to 40%).

---

### 3. Telemetry Callout Setup (`telem_callout.lua`)
**Purpose:** Dynamically configures voice/sound callout warnings for vital UAV telemetry metrics. It also programs a telemetry change-based callout for transmitter power.

*   **Resources Appended:**
    *   **5 Logical Switches** (threshold gates for low RSSI, low RSNR, low LQ, low battery voltage, and power output change).
    *   **5 Special Functions** (configured to read out values or play alerts at regular intervals).
*   **User Configurable Options:**
    *   **Battery Cells:** Voltage configuration (0 for Avg Cell Voltage, or 1S–8S).
    *   **Low Cell Lvl:** Minimum cell voltage limit (3.00V to 4.20V).
    *   **Link Quality:** Minimum link quality percentage threshold (10% to 100%).
    *   **RSSI (1RSS):** Critical RSSI cutoff (dBm).
    *   **RSNR Limit:** Minimum signal-to-noise ratio threshold (dB).
    *   **Repeat Alarm:** Audio announcement frequency interval (2s to 60s).

---

### 4. Trainer Auto-Setup (`trainer_setup.lua`)
**Purpose:** Programs a smart teacher/student trainer setup. Control is passed to the student radio using a toggle, but the instructor can instantly retake command by deflecting their sticks.

*   **Resources Appended:**
    *   **4 Logical Switches** (stick movement detection, sticky trainer latch switch).
    *   **2 Special Functions** (plays `"trnon"` when student is flying, and `"trnoff"` when instructor retakes control).
    *   **4 Student Overriding Mixers** (appended in **REPLACE** multiplex mode to CH1–CH4, mapped to student trainer channels `TR1`–`TR4`).
    *   **4 Instructor Mixer Restrictions** (modifies your first CH1–CH4 mixer lines to active only when student mode is disengaged).
*   **Trigger Switch:** Uses the Throttle Trim toggle button (`trm3+` / `trm5+`) as the dynamic toggle switch to hand control over. Deflecting the instructor's Aileron or Elevator sticks beyond 10% instantly overrides student control.

---

## Technical Information

### Non-Destructive Design
All scripts use scanning loops to search for empty slots before modifying anything:
*   **Logical Switches:** Scans slots `L01` through `L64` for items set to `LS_FUNC_NONE` or `0`.
*   **Curves:** Scans curve slots `1` through `32` for curves with no name and an empty coordinate table.
*   **Special Functions:** Scans slots `SF1` through `SF64` for unassigned functions.
*   **Mixes:** Mixer modifications either append mixers in **ADD** mode to keep stick control active, or safely replace stick control under specific switch positions.

If the script detects insufficient free slots for the requested setup, it will halt and display an error warning without making any modifications.
