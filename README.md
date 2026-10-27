# Skyline Lens

A native iPadOS app that turns an iPad mounted on a high window into a live, tappable
guide to the Manhattan skyline: labels for buildings, water and sky on the live
camera feed. Think PeakFinder, but for towers.

Reference deployment: about the 26th floor of 430 Main St, Roosevelt Island, looking
at Manhattan. Nothing is hard-coded to that spot; the app is meant to calibrate from
any elevated NYC viewpoint (15 m+ up, most buildings 300 m+ away).

## Status

| Milestone | State |
|---|---|
| 0. De-risk (offline pose solve from field captures) | Plan + desk analysis done ([docs/milestone-0-derisk.md](docs/milestone-0-derisk.md)); capture tool in the app; prototype not built |
| 1. Camera stream + Core Motion compass ticks | Built, needs on-device check |
| 2. Offline visibility index | Not started |
| 3. Skyline-silhouette auto-registration | Not started |
| 4–7. Tap to identify, zoom, water/sky cards, night mode | Not started |

## What Milestone 1 does

- Full-screen rear wide camera (aspect-fill), upright in all four orientations.
- Core Motion attitude in the true-north, z-up frame drives an overlay:
  - the 0° elevation line, with ticks every 1°, labels every 10°, and N/NE/E… cardinals,
  - a dashed line at the visible-horizon dip for your height,
  - a centre reticle,
  - orange sanity markers for a dozen well-known towers (approximate coordinates).
- Debug HUD: view bearing/elevation/roll, visible FOV and focal length, Core Motion frame
  and magnetometer accuracy, GPS fix and accuracy, barometer, height, envelope warning.
- Settings: floor number (sets height), debug manual yaw bias (checking only; Milestone 3
  solves it automatically), HUD and marker toggles, site label.
- Field capture for Milestone 0: the camera button saves a JPEG plus a JSON sidecar of
  pose, lens and GPS into Files › On My iPad › Skyline Lens › captures.
- Screen never sleeps (ambient mode).

## Setup

Requirements: Xcode 16 or later, an iPad on iPadOS 17 or later. The simulator has no
camera or real motion data, so the overlay only shows "Waiting for camera and motion…"
there.

1. Open `SkylineLens.xcodeproj`.
2. Select the SkylineLens target › Signing & Capabilities, and choose your team.
   Change the bundle identifier if `com.philosophercode.skylinelens` is taken.
3. Plug in the iPad, select it as the run destination, and run.
4. Allow camera, location and motion access when asked.

Tests for the geometry core run anywhere Swift does:

```sh
cd Packages/SkylineKit && swift test
```

Milestone 0 desk analysis (needs numpy):

```sh
python3 tools/m0_error_budget.py
```

### API keys

None yet. Later milestones will need, and read from an untracked `Secrets.xcconfig`:

| Key | Used for | Milestone |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude vision tap disambiguation, narration, Q&A | 4 |
| NOAA CO-OPS (no key) | tides and currents | 6 |
| AIS feed key (provider TBD) | ship traffic | 6 |
| ADS-B feed key (provider TBD) | aircraft | 6 |
| weather API key (provider TBD) | weather cards | 6 |
| eBird API key | bird sightings/migration | 6 |

For a shipped app the Anthropic key should sit behind a small proxy rather than in the
binary.

## Layout

```
SkylineLens.xcodeproj        app project (synchronized folder, no per-file entries)
SkylineLens/                 app shell: SkylineLensApp.swift, assets
Packages/SkylineKit/         all real code, as a local Swift package
  Sources/SkylineCore/       pure Swift, no Apple frameworks (tests run on Linux)
    Geodesy.swift            WGS84, ECEF/ENU, look angles, refraction, horizon dip
    Frames.swift             reference frame, attitude, matrix-convention check, UI orientation
    CameraModel.swift        aspect-fill intrinsics, pose correction, project/unproject
    CompassTicks.swift       bearing ticks and level lines on screen
    Landmarks.swift          starter landmark catalogue, viewpoint, operating envelope
    CaptureMetadata.swift    field-capture sidecar schema
  Sources/SkylineSensors/    Core Motion attitude, Core Location, barometer
  Sources/SkylineCamera/     AVFoundation session, preview, still capture
  Sources/SkylineUI/         live view, compass overlay, debug HUD, settings
  Tests/SkylineCoreTests/    geometry tests
docs/                        milestone notes
tools/                       offline scripts (Milestone 0 analysis)
```

Planned modules as milestones land: `SkylineIndex` (visibility index, SQLite),
`SkylineRegistration` (sky segmentation + silhouette solve), `SkylineIdentify`
(raycast candidates + Claude vision pick), `SkylineLiveData` (NOAA, AIS, ADS-B,
weather, eBird).

## Conventions worth knowing

- **Reference frame** is Core Motion's `.xTrueNorthZVertical`: +x north, +y west, +z up.
  Bearings are degrees clockwise from true north.
- **Attitude** is stored as `deviceFromReference` (`device = M * world`). Core Motion's
  matrix convention is easy to get transposed, so `AttitudeConvention.detect` checks it
  against measured gravity at runtime; the HUD shows which reading won.
- **Pose correction** (yaw, pitch, roll, focal scale) sits on top of the sensor attitude.
  Milestone 3's registration will solve it; for now only the debug yaw bias feeds it.
- **Pure rotation**: everything of interest is 0.5–10 km away, so only rotation and FOV
  are tracked live. Position is solved once per site (Milestone 0/3).

## CI

GitHub Actions runs the SkylineCore tests on Linux, then on macOS runs the package tests
and builds the app for the iOS Simulator (no signing). macOS minutes count 10x on private
repos, so there is only one macOS job.
