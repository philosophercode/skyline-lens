#!/usr/bin/env python3
"""Milestone 0 error budget for Skyline Lens.

Answers, before any field data exists:
  1. How much label error does a given position error cause, by distance?
  2. Does the pure-rotation assumption hold for hand nudges?
  3. If we resect position + heading from landmark tops, how precise is the fix
     given a per-landmark angular measurement noise, and does it meet the 0.5° goal?

Only needs numpy. Uses a flat local East-North-Up frame (fine at < 15 km for
error analysis; the app itself uses full WGS84).

    python3 tools/m0_error_budget.py
"""

import math

import numpy as np

RNG = np.random.default_rng(7)
LAT0 = 40.7625  # Roosevelt Island reference
LON0 = -73.9495
M_PER_DEG_LAT = 111_132.0
M_PER_DEG_LON = 111_320.0 * math.cos(math.radians(LAT0))

# Same starter catalogue as SkylineCore/Landmarks.swift (approximate coordinates).
LANDMARKS = {
    "Empire State": (40.74844, -73.98566, 15 + 443),
    "Chrysler": (40.75165, -73.97531, 12 + 319),
    "One Vanderbilt": (40.75300, -73.97870, 14 + 427),
    "432 Park": (40.76163, -73.97191, 20 + 426),
    "Citigroup": (40.75845, -73.97040, 18 + 279),
    "One WTC": (40.71274, -74.01338, 3 + 541),
    "Central Park Tower": (40.76658, -73.98095, 22 + 472),
    "Steinway": (40.76462, -73.97770, 22 + 435),
    "BofA Tower": (40.75545, -73.98446, 15 + 366),
    "UN Secretariat": (40.74892, -73.96803, 5 + 155),
    "30 Hudson Yards": (40.75380, -74.00090, 8 + 387),
    "MetLife": (40.75335, -73.97648, 14 + 246),
}
OBSERVER_UP = 5 + 81.5  # ground + 26th floor


def enu(lat, lon, up):
    return np.array([(lon - LON0) * M_PER_DEG_LON, (lat - LAT0) * M_PER_DEG_LAT, up])


def angles(obs, pts):
    """Bearing (deg, clockwise from north) and elevation (deg) from obs to each point."""
    d = pts - obs
    bearing = np.degrees(np.arctan2(d[:, 0], d[:, 1]))
    horiz = np.hypot(d[:, 0], d[:, 1])
    elev = np.degrees(np.arctan2(d[:, 2], horiz))
    return bearing, elev


def wrap(a):
    return (a + 180) % 360 - 180


def section(title):
    print("\n" + title)
    print("-" * len(title))


def label_error_table():
    section("1. Label error (deg) from a sideways position error")
    dists = [500, 1000, 2000, 4000, 8000]
    errs = [5, 10, 20, 50]
    print("pos err \\ dist " + "".join(f"{d/1000:>8.1f}km" for d in dists))
    for e in errs:
        print(f"{e:>8} m      " + "".join(f"{math.degrees(math.atan(e / d)):>10.2f}" for d in dists))
    print("Vertical: a 10 m altitude error shifts elevation by "
          + ", ".join(f"{math.degrees(math.atan(10 / d)):.2f}° at {d/1000:.1f} km" for d in dists))


def pure_rotation_check():
    section("2. Pure-rotation check (iPad nudged by hand)")
    for nudge in [0.1, 0.3, 1.0]:
        worst = math.degrees(math.atan(nudge / 300))
        print(f"{nudge:.1f} m nudge: at most {worst:.3f}° at 300 m, {math.degrees(math.atan(nudge / 1000)):.3f}° at 1 km")


def resect(obs_bearing, obs_elev, pts, guess, iters=10):
    """Gauss-Newton solve for [E, N, U, yaw] from relative bearings and elevations.

    Bearings are measured relative to the (unknown) sensor heading, so yaw is a
    nuisance parameter. Pitch/roll come from gravity and are assumed known here.
    """
    x = np.array(guess, dtype=float)
    for _ in range(iters):
        b, e = angles(x[:3], pts)
        r = np.concatenate([wrap(obs_bearing - (b - x[3])), obs_elev - e])
        J = np.zeros((2 * len(pts), 4))
        h = np.array([1.0, 1.0, 1.0, 0.01])
        for k in range(4):
            dx = np.zeros(4)
            dx[k] = h[k]
            b2, e2 = angles(x[:3] + dx[:3], pts)
            pred1 = np.concatenate([b - x[3], e])
            pred2 = np.concatenate([b2 - (x[3] + dx[3]), e2])
            J[:, k] = np.concatenate([wrap(pred2[: len(pts)] - pred1[: len(pts)]), pred2[len(pts):] - pred1[len(pts):]]) / h[k]
        step, *_ = np.linalg.lstsq(J, r, rcond=None)
        x += step
        if np.linalg.norm(step[:3]) < 1e-3:
            break
    return x


def resection_monte_carlo():
    section("3. Resection from landmark tops (Roosevelt Island, 26th floor)")
    names = list(LANDMARKS)
    pts = np.array([enu(*LANDMARKS[n]) for n in names])
    truth = np.array([0.0, 0.0, OBSERVER_UP])
    true_yaw = 12.0  # magnetometer bias, deg
    tb, te = angles(truth, pts)
    print("Landmark look angles from the reference site:")
    for n, b, e, p in zip(names, tb, te, pts):
        print(f"  {n:<20} bearing {b % 360:6.1f}°  elev {e:5.2f}°  {np.hypot(*(p - truth)[:2]) / 1000:4.1f} km")

    # Test buildings for label error: lower, nearer towers in several directions.
    probes = np.array([
        [-800, -300, 120], [-1500, -900, 200], [-2500, 300, 250],
        [-1200, -2500, 150], [-3000, -4000, 300], [600, -1200, 60],
    ], dtype=float)
    pb, pe = angles(truth, probes)

    for subset_name, idx in [("3 landmarks (ESB, Chrysler, One WTC)", [0, 1, 5]),
                             ("5 landmarks", [0, 1, 3, 5, 9]),
                             (f"all {len(names)}", list(range(len(names))))]:
        print(f"\n  {subset_name}")
        sub = pts[idx]
        for sigma in [0.05, 0.1, 0.2]:
            pos_err, yaw_err, label_err = [], [], []
            for _ in range(300):
                gps = truth + np.array([*RNG.normal(0, 35, 2), RNG.normal(0, 10)])  # 20-50 m indoor GPS
                ob = tb[idx] - true_yaw + RNG.normal(0, sigma, len(idx))
                oe = te[idx] + RNG.normal(0, sigma, len(idx))
                x = resect(ob, oe, sub, [*gps, 0.0])
                pos_err.append(np.linalg.norm(x[:2] - truth[:2]))
                yaw_err.append(abs(wrap(x[3] - true_yaw)))
                b, e = angles(x[:3], probes)
                label_err.append(np.max(np.hypot(wrap((b - x[3]) - (pb - true_yaw)), e - pe)))
            pos_err, yaw_err, label_err = map(np.array, (pos_err, yaw_err, label_err))
            print(f"    σ={sigma:.2f}°  horiz pos err median {np.median(pos_err):5.1f} m (p95 {np.percentile(pos_err, 95):5.1f})"
                  f"  yaw err median {np.median(yaw_err):.3f}°"
                  f"  worst-probe label err median {np.median(label_err):.2f}° (p95 {np.percentile(label_err, 95):.2f}°)")

    # Baseline: GPS only (no resection), heading solved perfectly.
    errs = []
    for _ in range(300):
        gps = truth + np.array([*RNG.normal(0, 35, 2), RNG.normal(0, 10)])
        b, e = angles(gps, probes)
        errs.append(np.max(np.hypot(wrap(b - pb), e - pe)))
    print(f"\n  GPS only (35 m σ), perfect heading: worst-probe label err median {np.median(errs):.2f}°"
          f" (p95 {np.percentile(errs, 95):.2f}°)")


if __name__ == "__main__":
    label_error_table()
    pure_rotation_check()
    resection_monte_carlo()
