# Update Screensaver Ship

Update the screensaver's "torch cruiser" to match the new Rocinante ship and engine plume implementation used in the waveform.

## Proposed Changes

### [lib/ui/screensaver_torch_cruiser.dart](file:///C:/Users/Green/playa_clean/lib/ui/screensaver_torch_cruiser.dart)

- Remove dependency on `TorchPlumeEngine` and `TorchShipPainter`.
- Port the following private drawing methods from `lib/ui/waveform_widget.dart` into `_ScreensaverTorchPainter`:
    - `_drawRocinante`
    - `_drawEnginePlume`
    - `_drawRCS`
    - `_buildRociHull`
- Update `_ScreensaverTorchPainter.paint` to use these new methods.
- Adjust the ship size and positioning for the screensaver context.

## Verification Plan

### Manual Verification
- Launch the screensaver on the device and verify that the ship now matches the new Rocinante style.
- Ensure the engine plume and shock diamonds are rendering correctly.
- Verify that the ship still cruises across the screen as expected.
