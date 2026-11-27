# Director screen: build spec

The Bethel version of the director screen, modelled on the layout in Timothy Sandberg's
"Auto Director" screen recordings (November 2026), built on this app's own engine and
Bethel's setup (Cam Link multiview, Middle Control gimbals, ceiling limits, thirds,
dissolve/cut style, service parts). His name and branding are not used.

## 1. Start screen

- App mark and name, one line on what it does.
- "Choose a switcher to begin": two cards.
  - **Real ATEM**: the address field (10.0.1.188), "Connect to the real ATEM".
  - **Practice switcher**: a pretend ATEM inside the app for training and layouts. Nothing
    reaches the real switcher; the cameras are still the real ones.
- "Ask every time the app opens" checkbox. Off: opens straight to the last choice.

## 2. Top bar

Logo · **Director** · Stage scan · Routing · Full switcher · Setup · Status ·
status pills: Online / Practice switcher, "Auto Direct: Sermon" while it runs, and warnings
("Cam 1 not answering").

## 3. Monitors

- Big **PREVIEW** (green border, label top left) and **PROGRAM** (red border) side by side.
- Over each, while tracking: a **FOLLOWING ×** badge top right (× stops it); "LOOKING FOR
  SOMEONE ×" in orange while it searches.
- On the tracked person: skeleton (blue lines, white joints, red/yellow eyes), outline box,
  and a label: Standing / Walking / Walking · crossing / Turning / Seated.
- **Edge warning**: the monitor's edge glows orange, then red, as the person nears it.
- Below: a row of camera tiles (Cam 2 PGM, Cam 1, Cam 3 PVW, Lower 3rd), each with its
  picture, name, PGM/PVW tag and a small "tracking" icon; + and − to add or remove tiles;
  click to put on Preview.

## 4. Panels (draggable, each with a grab handle)

**Camera and shots**: the selected camera's name chip; SHOTS: a row per camera (name,
PGM/PVW tag), + saves a shot.

**Movement**: "Tracking · joystick takes over" note; camera tabs (Cam 2 · Cam 1 · Cam 3);
joystick; zoom rocker (T/W); **Lock pan** · **Lock tilt**; CAM SPEED (Middle Control):
Move and Zoom sliders with values; GIMBAL SETUP: **Calib Zoom** (Middle Control
MOTORAUTOCALIB) · **Autotune** (GIMBALAUTOCALIB).

**Tracking**: "TRACKING Cam 3 · ON PROGRAM"; FOLLOW: big **Track** button (becomes
"Stop tracking" / "Tracking · Auto Direct"), **Mic** button (follow whoever is talking);
hint "Or click a person on Preview or Program, or double-click one on a feed"; status line
("Looking for someone", "Auto Direct ready: pastor, full length", "Auto Direct: live:
pastor, wide"); SHOT: **Close · Waist · Full · Wide** ("Tracking starts at the size the
camera is nearest"; under auto direct, "Auto Direct frames Cam 3 full length: tap it again
for its own choice"); ASSIST: **Frame assist** + Low · Medium · High, **Walk-off prevent**;
SETTINGS: Follow speed − 0.5× +.

**Take**: **AUTO** (1.0 s · Return), **CUT** (Space), **BLACK**, **LOWER 3RD**.

**Auto direct**: ON pill; **WORSHIP** and **SERMON** buttons ("ON · press to stop");
Pace: Slow · Medium · Fast; **Learn stage**; Worship options: Moving shots ✓, Hard cuts ✓;
"Runs the cameras and the switching by itself. Press a button again to stop."; a live line:
"Cam 3 (pastor, wide) is live · Cam 1 (pastor, navel up) is next in 7 s", and a light per
camera (ready / live).

## 5. Stage scan page

1. **Camera setup** table, a row per camera: Gimbal · Body · Lens (native lenses first,
   then "on an adapter" with the adapter named) · FPS · Crop · Breathing comp (On · 1.1×) ·
   Stabilization · Distance (ft) · Stands (Left / Center / Right) · status · remove. "+ Add
   a camera".
2. **Scan**: Frame each person: Navel up · Waist up · Full length · Wide; "Scan the stage"
   (or why it can't: "No camera is free to scan right now").
3. **The stage in 3D**: **Learn stage**; each camera where it stands, where it points and
   how wide it sees, and everyone on stage now; drag to turn it. Bethel: positions measured
   from the tape-mark walk, not guessed.
4. **Name people and save**: after a scan, each person each camera saw, with a box for
   their name.

## 6. Behaviour behind it (Bethel)

- **Sermon**: Cams 1, 2 and 4 all follow the minister at different sizes; Cam 3 holds the
  pulpit. The next camera is framed (and focused) on Preview before it's taken. Hard cuts.
- **Worship**: leader, band and instruments with slow moves; dissolves on slow and medium
  songs (2-3 s, 1.5-2.5 s), hard cuts on fast songs; instrument shots 4-7 s.
- **Prayer**: Cam 3 on the pulpit. **Altar**: wide. **Walk-off**: hard cut to a camera
  that still sees them, else Cam 4.
- **Frame assist**: once camera and subject hold still, nudge headroom (6-inch rule) and
  thirds; Low/Medium/High = how soon and how firmly.
- **Focus**: sharpen on Preview by sweeping focus for the crispest face before a take;
  follow focus from distance while live.
- **Learn mode**: watch a service run by people (switcher, gimbals, multiview, audio),
  send nothing, and learn the team's timings and habits.

## Open questions

- Sermon shot sizes per camera; sermon shot length; Cam 1's fixed third; next service date.
