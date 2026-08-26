# VIC20MEGA65 — Project Guide

Port of the MiSTer VIC-20 core to the [MEGA65](https://github.com/sy2002/MiSTer2MEGA65/wiki),
using the **MiSTer2MEGA65 (M2M)** porting framework and **QNICE-FPGA** as the
on-board helper CPU. Done by MJoergen and sy2002, licensed GPL v3.

Background: the **Commodore VIC-20** (1981) is an 8-bit home computer, MOS 6502
@ ~1 MHz, VIC video chip, very limited RAM (expandable via cartridges/RAM
packs). The **MEGA65** is a modern Xilinx-Artix-7-based recreation of the
unreleased Commodore 65. **MiSTer** is the FPGA platform this core originated
on; the MiSTer VIC-20 core lives in the `CORE/VIC20_MiSTer` submodule
(originally by MikeJ / WoS, extended by Sorgelig for MiSTer).

## Repository layout

```
CORE/                    core-dependent, board-independent
├── CORE-R{3,4,5,6}.xpr    Vivado projects, one per MEGA65 board revision —
│                          the single source of truth for the file list/build
├── vhdl/
│   ├── mega65.vhd         entity MEGA65_Core — top of the port; glue only
│   ├── main.vhd           entity main; wraps the MiSTer core in its own
│   │                      clock domain (keyboard, joystick/paddle, audio, video CE)
│   ├── clk.vhd             MMCM clock generation
│   ├── config.vhd          OSM/help/welcome text + menu structure
│   ├── globals.vhd         constants: clock speeds, device IDs, ROMs
│   ├── keyboard.vhd        MEGA65 keyboard → VIC-20 CIA1 matrix
│   └── gen_rom.vhd         generic ROM helper
├── m2m-rom/               QNICE assembly: core-specific Shell entry
│   ├── m2m-rom.asm          pulls in M2M/rom/*.asm, implements callbacks
│   └── make_rom.sh          builds m2m-rom.rom (read by qnice.vhd at synthesis)
└── VIC20_MiSTer/          git submodule: the MiSTer VIC-20 core (rtl/, sys/)

M2M/                     core-independent, board-dependent (the framework)
├── MEGA65-R{3,4,5,6}.xdc  per-board pin constraints
├── vhdl/
│   ├── top_mega65-rX.vhd   FPGA top entities; instantiate framework.vhd AND
│   │                       CORE/vhdl/mega65.vhd
│   ├── framework.vhd       HAL: QNICE, AV pipeline, controllers, resets
│   ├── vdrives.vhd         virtual disk drive / mount engine
│   ├── av_pipeline/        video pipeline (scandoubler, ascal/HDMI scaler)
│   └── QNICE/, controllers/, memory/, i2c/
├── QNICE/                 QNICE-FPGA submodule (CPU + "Monitor" OS + toolchain)
└── rom/                   M2M Shell sources (QNICE assembly): menu.asm,
                            shell.asm, vdrives.asm, keyboard.asm, options.asm, …

doc/                      developer notes (m2m/, wiki/, temp/)
```

**Key separation (the M2M philosophy):** `CORE/` is core-dependent and
board-independent; `M2M/` is core-independent and board-dependent. The
contract between them is the entity `mega65_core` declared in
`CORE/vhdl/mega65.vhd`.

## Architecture

`M2M/vhdl/top_mega65-rX.vhd` (one per board revision) instantiates both
`M2M/vhdl/framework.vhd` (QNICE + AV pipeline + resets + controllers) and
`CORE/vhdl/mega65.vhd` (entity `mega65_core`), which in turn instantiates
`clk.vhd`, `config.vhd`, and `main.vhd`. `main.vhd` wraps the MiSTer core
(`CORE/VIC20_MiSTer/rtl/vic20.vhd`) together with everything that needs the
core's clock domain: `keyboard.vhd`, joystick/paddle handling, audio, and the
video clock-enable divider.

QNICE (`M2M/QNICE/`) is the on-board helper CPU that runs the **Shell**: the
on-screen menu, file/directory browser, disk-image mounting, and ROM/PRG
loading. Its firmware is QNICE assembly: `M2M/rom/*.asm` (framework) plus
`CORE/m2m-rom/m2m-rom.asm` (core-specific entry + callbacks like
`FILTER_FILES`). Switch between the release Shell firmware and the debug
"Monitor" firmware via `QNICE_FIRMWARE` in `CORE/vhdl/globals.vhd`.

The On-Screen Menu is text defined in `CORE/vhdl/config.vhd`
(`OPTM_ITEMS`/`OPTM_GROUPS`); group IDs are referenced both in VHDL
(`mega65.vhd`) and in QNICE assembly (`CORE/m2m-rom/m2m-rom.asm`).

Virtual drives (`M2M/vhdl/vdrives.vhd`) simulate the MiSTer-style mount
interface for the core, backed by an in-FPGA RAM disk-image cache that QNICE
fills from the SD card's FAT32 filesystem.

Cartridge/tape support (`.CRT`, `.CTx`, `.TAP`) and RAM-expansion regions are
VIC-20-specific quirks — see the root `README.md` before touching
cartridge-loading logic; VIC-20 cartridges have inconsistent header
conventions (see the `.CRT` vs `.CTx` distinction there).

## Build workflow

```bash
git submodule update --init --recursive     # M2M/QNICE and CORE/VIC20_MiSTer

# 1) QNICE toolchain (one-time; produces M2M/QNICE/monitor/monitor.rom)
cd M2M/QNICE/tools && ./make-toolchain.sh && cd ../../..

# 2) Rebuild the Shell ROM after changing CORE/m2m-rom/*.asm or M2M/rom/*.asm
cd CORE/m2m-rom && ./make_rom.sh && cd ../..
# Output: CORE/m2m-rom/m2m-rom.rom, consumed by qnice.vhd at synthesis

# 3) Bitstream: open the per-revision CORE-R{3,4,5,6}.xpr in Vivado
#    (single source of truth for file list, target part, and XDC order),
#    then Run Synthesis → Run Implementation → Generate Bitstream.
```

## Conventions worth knowing before editing VHDL

- Never use `reset_soft_i` / `reset_hard_i` directly outside their entry
  point — a reset pulse must be ≥32 clock cycles wide; check for a similar
  reset-semantics comment block in `main.vhd` before changing reset logic.
- `CORE/VIC20_MiSTer/` is a near-verbatim drop of the upstream MiSTer core;
  don't refactor it without reason — match upstream conventions.
- Clock-speed constants (`CORE_CLK_SPEED` etc. in `globals.vhd`) must be
  exact — several core timings (e.g. CIA time-of-day) derive from them.
