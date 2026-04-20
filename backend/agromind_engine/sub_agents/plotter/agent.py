import math
import time
from shapely.geometry import Polygon, Point
from pyproj import Transformer
from google.adk.agents.llm_agent import LlmAgent

from . import prompt


def calculate_planting_grid(
    boundary_points: list,
    spacing_meters: float = 2.0,
) -> dict:
    """Calculate an exact planting grid for the given polygon using shapely.

    Returns exact plant counts and GPS coordinates for every position,
    split alternately between timber and intercrop in a checkerboard pattern.

    Args:
        boundary_points: List of {"latitude": float, "longitude": float} dicts
            defining the farm boundary.
        spacing_meters: Distance between adjacent plants in meters. Default 2.0.

    Returns:
        Dict with:
          - total_plants (int)
          - timber_count (int)
          - intercrop_count (int)
          - area_hectares (float)
          - spacing_meters (float)
          - timber_positions: list of {"latitude", "longitude"}
          - intercrop_positions: list of {"latitude", "longitude"}
        Or {"error": "..."} on failure.
    """
    t0 = time.time()
    print(f"[PLOTTER] calculate_planting_grid({len(boundary_points)} pts, "
          f"spacing={spacing_meters}m) START", flush=True)

    try:
        if not boundary_points or len(boundary_points) < 3:
            msg = f"Need at least 3 boundary points to form a polygon (got {len(boundary_points)})"
            print(f"[PLOTTER] FAILED: {msg}", flush=True)
            return {"error": msg}

        # Pick a UTM zone based on the polygon's centroid for accurate metric math
        avg_lat = sum(p["latitude"] for p in boundary_points) / len(boundary_points)
        avg_lng = sum(p["longitude"] for p in boundary_points) / len(boundary_points)
        utm_zone = int((avg_lng + 180) / 6) + 1
        utm_epsg = 32600 + utm_zone if avg_lat >= 0 else 32700 + utm_zone

        to_utm = Transformer.from_crs("EPSG:4326", f"EPSG:{utm_epsg}", always_xy=True)
        to_wgs = Transformer.from_crs(f"EPSG:{utm_epsg}", "EPSG:4326", always_xy=True)

        # Build polygon in UTM (meters)
        utm_coords = [to_utm.transform(p["longitude"], p["latitude"]) for p in boundary_points]
        polygon = Polygon(utm_coords)

        if not polygon.is_valid:
            polygon = polygon.buffer(0)  # fix self-intersections

        area_m2 = polygon.area
        area_ha = area_m2 / 10_000

        # Safety cap: refuse to generate more than 5000 points (keeps Flutter happy)
        est_points = int(area_m2 / (spacing_meters ** 2))
        if est_points > 5000:
            # Auto-increase spacing to cap at ~5000 points
            spacing_meters = math.sqrt(area_m2 / 5000)
            print(f"[PLOTTER] Auto-adjusted spacing to {spacing_meters:.2f}m "
                  f"to cap grid at 5000 points", flush=True)

        # Generate grid points
        minx, miny, maxx, maxy = polygon.bounds
        timber_positions = []
        intercrop_positions = []

        row = 0
        y = miny
        while y <= maxy:
            col = 0
            x = minx
            while x <= maxx:
                pt = Point(x, y)
                if polygon.contains(pt):
                    lng, lat = to_wgs.transform(x, y)
                    # Checkerboard: even (row+col) → timber, odd → intercrop
                    if (row + col) % 2 == 0:
                        timber_positions.append({"latitude": lat, "longitude": lng})
                    else:
                        intercrop_positions.append({"latitude": lat, "longitude": lng})
                x += spacing_meters
                col += 1
            y += spacing_meters
            row += 1

        result = {
            "total_plants": len(timber_positions) + len(intercrop_positions),
            "timber_count": len(timber_positions),
            "intercrop_count": len(intercrop_positions),
            "area_hectares": round(area_ha, 4),
            "spacing_meters": round(spacing_meters, 2),
            "timber_positions": timber_positions,
            "intercrop_positions": intercrop_positions,
        }

        print(f"[PLOTTER] DONE in {time.time()-t0:.1f}s: "
              f"{result['total_plants']} plants "
              f"({result['timber_count']} timber, {result['intercrop_count']} intercrop) "
              f"on {area_ha:.4f} ha", flush=True)
        return result

    except Exception as e:
        print(f"[PLOTTER] FAILED in {time.time()-t0:.1f}s: {e}", flush=True)
        return {"error": f"Grid calculation failed: {e}"}


plotter_agent = LlmAgent(
    name="Plotter_Agent",
    model="gemini-2.5-flash",
    description="Generates precise planting grids using geometric computation.",
    instruction=prompt.PLOTTER_PROMPT,
    tools=[calculate_planting_grid],
)