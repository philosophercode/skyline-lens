# Milestone 0: de-risk plan and first findings

Goal from the spec: from a cold start with noisy GPS (20–50 m indoors), solve position
and orientation from stills/video at 5+ NYC viewpoints. **Go** if daytime cold-start
calibration takes under 60 s with under 0.5° label error at 4 of 5 sites.

This document has three parts: what the desk analysis already tells us, the offline
prototype to build, and the field capture protocol (the app's capture button exists
for this).

## 1. Desk analysis (`tools/m0_error_budget.py`)

Run `python3 tools/m0_error_budget.py` (numpy only). Key numbers:

**Position error dominates near buildings.** A sideways position error `e` shifts a
label at distance `d` by `atan(e/d)`:

| position error | 0.5 km | 1 km | 2 km | 4 km | 8 km |
|---|---|---|---|---|---|
| 5 m  | 0.57° | 0.29° | 0.14° | 0.07° | 0.04° |
| 20 m | 2.29° | 1.15° | 0.57° | 0.29° | 0.14° |
| 50 m | 5.71° | 2.86° | 1.43° | 0.72° | 0.36° |

So raw indoor GPS cannot meet 0.5° for anything closer than about 4 km. Altitude
matters the same way (10 m error = 0.57° of elevation at 1 km), so the floor number
or barometer must be in the solve too.

**The pure-rotation assumption is safe.** A 0.3 m hand nudge moves a label by at most
0.06° at 300 m, 0.02° at 1 km.

**Resection works, but only with enough well-spread landmarks.** Monte Carlo of a
Gauss-Newton solve for (east, north, up, yaw) from landmark-top bearings and
elevations, Roosevelt Island 26th floor, GPS seed σ = 35 m, true magnetometer bias 12°.
"Label error" is the worst error over six probe buildings at 0.9–5 km.

| landmarks used | angular noise σ | position error (median) | label error median / p95 |
|---|---|---|---|
| GPS only, perfect heading | – | ~35 m | 2.01° / 4.12° |
| 3 (ESB, Chrysler, One WTC; 19° bearing spread) | 0.05° | 30 m | 1.19° / 3.33° |
| 3 (same) | 0.10° | 57 m | 2.24° / 6.78° |
| 5, wider spread | 0.10° | 7.7 m | 0.32° / 0.67° |
| 12 | 0.10° | 5.1 m | 0.23° / 0.48° |
| 12 | 0.20° | 11.3 m | 0.52° / 0.98° |

**Implications (these change the plan):**

1. "Triangulate 3+ landmarks" in the spec is not enough on its own. Three landmarks
   clustered in bearing (the usual case: Midtown towers all sit in a ~40° wedge from
   most vantage points) leave position poorly constrained. We need **5+ landmarks with
   wide bearing spread, measured to ~0.1°**, or more constraints.
2. The cheapest extra constraints are the **skyline silhouette itself**: hundreds of
   columns, each a bearing/elevation pair against the 3D model. The resection and the
   silhouette registration (Milestone 3) should be **one joint solve** over position,
   yaw/pitch/roll and focal length, not two stages.
3. Angular precision of ~0.1° per landmark means sub-pixel-ish detection: at the iPad
   wide camera's ~64° FOV over 1920 px, 0.1° ≈ 3 px. Achievable for crisp crowns in
   daylight, doubtful at night or in haze, which is why night mode holds the last
   good daytime pose.
4. The lens field of view must be solved, not trusted: a 1% focal error is 0.3° at
   the edge of the frame.

These are model results with an approximate landmark catalogue; field data decides.

## 2. Offline prototype (to build next, throwaway)

Python, outside the app, reading the captures from section 3.

1. **Model**: NYC building footprints with roof heights and ground elevation (BIN
   keyed), clipped to 10 km around the GPS seed. Rasterise into a per-site panorama
   "depth/height" map: for each bearing (0.05° bins), the max elevation angle of any
   roof edge, plus which BIN produced it.
2. **Detect**: sky segmentation per photo (start with a simple colour/gradient method,
   then a small pretrained segmentation model) to a 1D skyline profile, height per
   column, plus a confidence per column (glass reflections and haze show up as low
   confidence).
3. **Solve**: coarse yaw by 1D cross-correlation of detected vs rendered profiles over
   ±25° around the magnetometer heading, then joint nonlinear least squares over
   (E, N, U, yaw, pitch, roll, focal) with a robust loss (Huber) so occluders and
   missing new towers do not drag the fit. Landmark-crown detections, when present,
   enter as extra residuals.
4. **Report** per capture: solved position vs surveyed truth, yaw/pitch/roll vs a
   hand-labelled reference, silhouette residual, and label error on hand-labelled
   tap points. Failure taxonomy: glare/reflection, haze, night, occlusion (window
   frames, nearby buildings), missing/new towers, model height errors.

Dependencies this would add (needs your OK): `numpy`, `opencv-python`, `shapely` or
`geopandas`, and `scipy` for the solver. A segmentation model (for example a
DeepLabV3/SegFormer checkpoint) is optional at first.

## 3. Field capture protocol

The app's camera button (right edge) saves a JPEG plus a JSON sidecar with the attitude
matrix, gravity, magnetometer accuracy, GPS fix, barometer change, floor, lens FOV and
zoom. Files appear in **Files › On My iPad › Skyline Lens › captures**.

At each site:

1. In settings, set the floor and a site label (for example `Roosevelt Island 26F`).
2. Wave the iPad in a figure-eight once to calibrate the magnetometer.
3. Capture 8–12 stills panning across the whole view, overlapping by about a third.
4. Repeat at dusk and after dark at the reference site.
5. Note ground truth: the exact address/floor, and if possible the lat/lon of the
   window from a map (drop a pin), so position error can be measured.

Suggested sites (from the spec): Roosevelt Island (reference), Brooklyn Heights or
DUMBO waterfront, Long Island City, a Midtown high floor, Jersey City or Hoboken, an
Upper Manhattan rooftop.

## Go / no-go

Go when the offline solver, cold-starting from the capture's GPS and magnetometer,
reaches under 0.5° median label error at 4 of 5 sites in daylight, in under 60 s of
compute on a laptop (the on-device budget is set after we see how much of that is
model preparation that can be cached per site).
