import os
import ee
from google.adk.agents.llm_agent import LlmAgent
from google.adk.tools.google_search_tool import GoogleSearchTool

from . import prompt

# --- Google Earth Engine Authentication ---
# Resolve the path to the service account key relative to the backend root.
_KEY_FILE = os.path.join(os.path.dirname(__file__), "..", "..", "..", "gee-key.json")
_SERVICE_ACCOUNT = "aura-gee-service@aura-487117.iam.gserviceaccount.com"

try:
    credentials = ee.ServiceAccountCredentials(_SERVICE_ACCOUNT, _KEY_FILE)
    ee.Initialize(credentials)
    print("[OK] Google Earth Engine initialized successfully.")
except Exception as e:
    print(f"[ERROR] Failed to initialize Google Earth Engine: {e}")


def fetch_land_data(lat: float, lng: float) -> str:
    """Fetches elevation and average land-surface temperature data from Google
    Earth Engine for a given latitude and longitude.

    Args:
        lat: Latitude of the point of interest.
        lng: Longitude of the point of interest.

    Returns:
        A formatted string containing the elevation (m) and 2025 average
        temperature (°C) for the location, or an error message if the
        data could not be retrieved.
    """
    import time
    t0 = time.time()
    print(f"[GEE] fetch_land_data({lat}, {lng}) START", flush=True)
    try:
        point = ee.Geometry.Point([lng, lat])

        # --- Elevation (SRTM 30m) ---
        srtm = ee.Image("USGS/SRTMGL1_003")
        elevation_result = srtm.sample(point, scale=30).first().get("elevation").getInfo()

        # --- Average Land Surface Temperature (MODIS — 2025 only) ---
        modis = (
            ee.ImageCollection("MODIS/061/MOD11A2")
            .filterDate("2025-01-01", "2025-12-31")
            .select("LST_Day_1km")
            .mean()
        )
        temp_kelvin_scaled = modis.sample(point, scale=1000).first().get("LST_Day_1km").getInfo()

        # MODIS LST scale factor is 0.02; result is in Kelvin → convert to Celsius
        temp_celsius = round((temp_kelvin_scaled * 0.02) - 273.15, 2)

        result = (
            f"Land Profile for ({lat}, {lng}):\n"
            f"  - Elevation: {elevation_result} meters above sea level\n"
            f"  - Avg. Land Surface Temperature (2025): {temp_celsius} deg C\n"
        )
        print(f"[GEE] fetch_land_data DONE in {time.time()-t0:.1f}s", flush=True)
        return result

    except Exception as e:
        print(f"[GEE] fetch_land_data FAILED in {time.time()-t0:.1f}s: {e}", flush=True)
        return f"Error fetching land data: {e}"


land_profiler_agent = LlmAgent(
    name="Land_Profiler_Agent",
    model="gemini-2.5-flash",
    description="Analyzes soil and climate data for a given geographic boundary.",
    instruction=prompt.LAND_PROFILER_PROMPT,
    tools=[fetch_land_data],
)
