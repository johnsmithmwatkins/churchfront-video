# Setups

Starting setup files for CueVideo. Copy one to
`~/Library/Application Support/CueVideo/config.json` on the booth Mac.

## bethel-church.json

Bethel church booth: ATEM Mini Extreme, Middle Control on the same Mac (127.0.0.1).

| Camera | Rig | Middle Control # | Lens setup |
|---|---|---|---|
| Cam 1 | Pocket 4K + Olympus 40-150, RS4 Pro | 1 | 18.96 mm sensor, 40-150 mm |
| Cam 2 | Pocket 6K + Canon 70-200, RS4 Pro | 2 | 23.10 mm sensor, 70-200 mm |
| Cam 3 | Studio 4K + Xeen 135, tripod (not motorised) | none | fixed shot |
| Cam 4 | Pocket 6K + Canon 24-105, RS4 Pro | 4 | 23.10 mm sensor, 24-105 mm |

Still to fill in on site:
- `atemHost`: the Mini Extreme's IP address.
- `atemInput` and `sources`: which Mini Extreme HDMI input each camera is on (1-4 here are a guess).
- Gimbal calibration (`countsPerDegree`, `maxDegreesPerSecond`) once the rigs are measured.

In Middle Control, turn ATEM Link off.
