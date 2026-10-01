# EdgeTX Automation Lua Scripts

A collection of utility scripts designed to automate repetitive setup tasks on EdgeTX-compatible transmitters. These scripts scan your active model configuration and append the necessary curves, logical switches, mixes, and special functions into free slots, leaving your existing settings in place (see [Non-Destructive Design](#non-destructive-design) for the one exception).

---

> [!CAUTION]
> **DISCLAIMER: USE THESE SCRIPTS ENTIRELY AT YOUR OWN RISK**
>
> These scripts modify active model configurations, including mixer lines, curves, logical switches, and special functions. Incorrect configuration, firmware differences between radios, or unexpected script behavior could result in corrupted model files, loss of control, flyaways, crashes, property damage, or personal injury.
>
> *   **Always back up your radio's models and settings** using EdgeTX Companion before running any script.
> *   **Always bench test with the PROPELLERS REMOVED** to verify that every switch, mix, override, and safety cutoff works as intended before flying.
> *   **Review every change the script makes** on the radio's Mixes, Logical Switches, Curves, and Special Functions pages before arming.
>
> These scripts are provided **"AS IS", without warranty of any kind**, express or implied. By using them you accept full responsibility for the outcome. **The developer assumes no liability whatsoever** for any damage, injury, loss of property, loss of data, or any other consequence, direct or indirect, arising from the use or misuse of these scripts.

---

## Requirements

*   **EdgeTX 2.6 or newer.** Switch detection relies on the `switches()`, `getSwitchValue()`, and `getSwitchIndex()` Lua APIs introduced in 2.6.
*   A model selected on the radio. All changes are written to the **currently active model**.

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
    *   **Wobble Switch:** Press ENTER, then flip the physical switch to the position that should activate the oscillations. The script detects it automatically.
    *   **Wobble Weight:** Amplitude percentage of the oscillation (10% to 100%).

---

### 2. Chirp Setup Wizard (`chirp_setup.lua`)
**Purpose:** Configures UAVTech's log-sine chirp setpoint sequence (designed by Wood2026). This is used to sweep through a range of frequencies on Roll and Pitch to analyze drone dynamics and transfer functions.

*   **Resources Appended:**
    *   **4 Logical Switches** (latching, timing, and sequence phase shifting).
    *   **4 Custom 17-Point Smoothed Curves** (`Sc1` to `Sc4`) mapped to specific logarithmic spacing intervals.
    *   **8 Mixers** (4 added to CH1 Roll and 4 added to CH2 Pitch, sequenced with ascending delay and speed settings).
*   **User Configurable Options:**
    *   **Chirp Switch:** Press ENTER, then flip the physical switch to the position that should trigger the chirp. The script detects it automatically.
    *   **Safety Switch:** Press ENTER, then flip the safety/arm switch to the position required to execute the chirp. The script detects it automatically.
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

### Switch Detection
Instead of picking from a fixed list of switch names (which vary between radios), the Auto Wobble and Chirp tools detect switches live:

1.  Select the switch option and press **ENTER**. The script records the current position of every physical switch.
2.  Flip the switch to the position that should **activate** the feature. The detected position (e.g. `SH↓`, `SC-`) is shown on screen.
3.  Press **ENTER** to confirm or **EXIT** to cancel.

Notes:
*   Only physical switches (`SA`, `SB`, ..., `SW1`, ...) are watched. Logical switches, trims, and other sources are ignored, so they cannot be picked by mistake.
*   The **last** position you move to is kept. Moving a 3-position switch from up through middle to down selects the down position.
*   The tool will not write anything until every required switch has been detected.

### Non-Destructive Design
All scripts use scanning loops to search for empty slots before modifying anything:
*   **Logical Switches:** Scans slots `L01` through `L64` for items set to `LS_FUNC_NONE` or `0`.
*   **Curves:** Scans curve slots `1` through `32` for curves with no name and all points still at `0`. Any named or edited curve is left alone.
*   **Special Functions:** Scans slots `SF1` through `SF64` for unassigned functions.
*   **Mixes:** New mixer lines are appended after your existing lines. Auto Wobble and Chirp add them in **ADD** mode to keep stick control active. **Exception:** Trainer Auto-Setup also edits your first CH1–CH4 mixer lines so they are active only when the student is not flying.

If there are not enough free slots, or a required switch has not been detected, the script halts with an error before making any changes. If a write fails partway through (for example, the radio runs out of curve memory), the script stops and shows the error, but changes written up to that point remain. This is one more reason to back up your models first.

---

## License

Released under the [MIT License](LICENSE). The software is provided "as is", without warranty of any kind. See the [disclaimer](#edgetx-automation-lua-scripts) above and the `LICENSE` file for full terms.
