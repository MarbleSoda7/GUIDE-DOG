camremap stereo + PL distortion rectification (RMP2 build)
==========================================================

This folder is scanned before the copies inside image.ub, so files here
override the built-in ones. The application CODE lives inside image.ub;
nothing here is executed directly.

args                Extra arguments for 'python3 -u -m camremap'.
                    Current default: --fps 5 --frames 0  (rectify off)
disable             Create an empty file with this name to stop autostart.

left_remap.rmp      RMP2 LUT, left eye
right_remap.rmp     RMP2 LUT, right eye
remap_manifest.json LUT manifest (step/frac/geometry/calibration flag)

Modes (edit args, then reboot or run by hand):
  --rectify off
      raw pass-through, no PL core, default and safest first boot.
  --rectify pl --allow-synthetic-lut --verify-remap-crc
      runs the PL remap core. The shipped LUTs are SYNTHETIC
      (assumed 170 deg lens -> 100 deg output, 40 mm baseline),
      so --allow-synthetic-lut is mandatory until real calibration
      replaces them. Geometry only, not a calibrated result.

Manual smoke test:
  python3 -u -m camremap --rectify pl --allow-synthetic-lut --frames 20 --fps 5 --verify-remap-crc

After a failure the init script latches /run/camremap-fatal and stops
restarting. Clear it with: camremap-init clear-fatal

To replace the LUTs with measured ones, generate left/right .rmp plus
remap_manifest.json on the PC (tools/stereo_calibrate.py then
tools/generate_remap_lut.py) and copy the three files here.
Re-synthesising the PL core is NOT required - the step/frac contract is
fixed at step 16 / Q10.6.
