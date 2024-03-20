VIC20 for MEGA65 Regression Testing
=================================

Before releasing a new version we strive to run all regression tests described
here.

Version 1 - March 20, 2024
-------------------------

| Status                 | Test                                                 | Done by                | Date
|:-----------------------|------------------------------------------------------|:-----------------------|:--------------------------
| :white_check_mark:     | Basic regression tests: Main menu                    | MJoergen               | 3/20/24
| :x:                    | Basic regression tests: Additional Smoke Tests       | MJoergen               | 3/20/24
| :x:                    | HDMI & VGA                                           | MJoergen               | 3/20/24
| :x:                    | Writing to `*.d64` images                            | MJoergen               | 3/20/24
| :white_check_mark:     | Dedicated RAM expansion tests                        | MJoergen               | 3/20/24
| :x:                    | Dedicated simulated cartridge tests                  | MJoergen               | 3/20/24

### Basic regression tests

#### Main menu

Work with the main menu and run software that allows to test the following and make sure that
you have a JTAG connection and an **active serial terminal** to observe the debug output of the core:

* Filebrowser
* Mount disk
* Load `*.prg`
* Short reset vs. long reset: Test drive led's behavior
* Stress the OSM ("unexpected" resets, opening closing "all the time" while things that change the OSM are happening in the background, etc.)
* Flip joystick ports
* Save configuration: Switch off/switch, check configuration
* Save configuration: Switch the SD card while the core is running and observe how settings are not saved.
* Save configuration: Omit the config file and use a wrong config file
* About and Help
* Close Menu

#### Additional Smoke Tests

* Try to mount disk while SD card is empty
* Work with both SD cards (and switch back and forth in file-browser)
* Remove external SD card while menu and file browser are not open;
  reinsert while file browser is open
* Work with large directory trees / game libraries
* Eagle's Nest: Reset-tests: Short reset leads to main screen. Long reset
  resets the whole core (not only the C64).

### HDMI & VGA

#### HDMI

Test if the resolutions and frequencies are correct:

```
16:9 720p 50 Hz = 1,280 x 720 pixel
16:9 720p 60 Hz = 1,280 x 720 pixel
4:3  576p 50 Hz =   720 x 576 pixel
5:4  576p 50 Hz =   720 x 576 pixel
```

Test HDMI modes:

* Flicker-free: Use the [Testcase from README.md](../README.md#flicker-free-hdmi)
* DVI (no sound)
* CRT emulation
* Zoom-in

#### VGA

Switch-off "HDMI: Flicker-free" before performing the following VGA tests and
check for each VGA mode if the **OSM completely fits on the screen**:

* Standard
* Retro 15 kHz with HS/VS
* Retro 15 kHz with CSYNC

Make sure that the Retro 15 kHz tests are performed on real analog retro CRTs.

### Writing to `*.d64` images

* Work with `Disk-Write-Test.d64` and create some files and re-load them
* Try to interrupt the saving by pressing <kbd>Reset</kbd> while the yellow light is on.
  Do this with the OSM open and also with the OSM closed. Watch if the `<Saving>` is
  being influenced by the reset attempt.

### Dedicated RAM expansion tests

All done by MJoergen on 3/20/24

* Used [this RAM test](https://github.com/svenpetersen1965/VIC-20-RAM-Expansion-Test-Software) on all 32 menu combinations.

### Dedicated simulated cartridge tests

All done by MJoergen on 3/20/24

| Status             | Game Name                                                                     | Cartridge Type                             | Comment
|:-------------------|:------------------------------------------------------------------------------|:-------------------------------------------|:---------------------------------------------------------------------
| :x:                |                                                                               | 0 - generic cartridge                      |

