# main.py

# Standard FastAPI imports for building the REST API
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import uvicorn
import time
import asyncio
import os
import httpx

# Load environment variables from .env file before anything else
from dotenv import load_dotenv

# Vertex AI AdkApp wraps the ADK agent with session + memory services
from vertexai.preview.reasoning_engines import AdkApp

# Firestore client for persisting analysis results to the database
from google.cloud import firestore

# Import the two ADK agents: full pipeline orchestrator and lightweight chat agent
from agromind_engine import orchestrator_agent, chat_agent


# Load environment variables from backend/.env (gitignored)
load_dotenv()

# Google Maps Geocoding API key — loaded from env, never hardcoded
GEOCODING_API_KEY = os.environ.get("GEOCODING_API_KEY", "")

# Vertex AI Agent Engine resource ID for session and memory bank binding
AGENT_ENGINE_ID = "7339574916695457792"

# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------
app = FastAPI(title="AgroMind — Agroforestry Decision-Support API")

# Allow all origins so the Flutter web/desktop frontend can reach this backend
# In production, restrict allow_origins to your specific frontend domain
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Firestore client (reused across requests)
# ---------------------------------------------------------------------------
# Single Firestore client instance shared across all requests to avoid
# re-initialising the connection on every API call
db = firestore.Client(project="aura-487117")

# ---------------------------------------------------------------------------
# ADK application (wraps the orchestrator + session + long-term memory)
#
# AdkApp does not expose `app_name` as a kwarg. Instead, it reads
# GOOGLE_CLOUD_AGENT_ENGINE_ID from the environment during set_up() and uses
# it both as the session app_name and to construct VertexAiSessionService /
# VertexAiMemoryBankService with the correct agent_engine_id. Passing it via
# env_vars keeps all wiring inside the AdkApp lifecycle.
# ---------------------------------------------------------------------------

# Main analysis pipeline: runs all 5 agents sequentially (Land Profiler →
# Agronomist → Parallel(Economist + Plotter) → Documentarian)
adk_app = AdkApp(
    agent=orchestrator_agent,
    env_vars={"GOOGLE_CLOUD_AGENT_ENGINE_ID": AGENT_ENGINE_ID},
)
# NEW — lightweight chat app, shares same Agent Engine for session continuity:
chat_app = AdkApp(
    agent=chat_agent,
    env_vars={"GOOGLE_CLOUD_AGENT_ENGINE_ID": AGENT_ENGINE_ID},
)

# ---------------------------------------------------------------------------
# API models & endpoints
# ---------------------------------------------------------------------------

# Represents a single GPS coordinate point (used for farm boundary and planting grid)
class LatLngPoint(BaseModel):
    latitude: float
    longitude: float


# Request body for the /api/chat endpoint (lightweight follow-up questions)
class ChatRequest(BaseModel):
    session_id: str
    message: str


class AnalyzeRequest(BaseModel):
    """Request body for the /api/analyze endpoint."""
    session_id: str
    project_id: str
    message: str
    boundary_points: list[LatLngPoint] = []


# Request body for the /api/geocode endpoint (place name or address to look up)
class GeocodeRequest(BaseModel):
    query: str


@app.post("/api/chat")
async def chat_with_orchestrator(request: ChatRequest):
    t0 = time.time()
    print(f"\n[CHAT] session={request.session_id} msg={request.message[:80]!r}", flush=True)

    full_response = ""

    async def run_chat():
        # Stream response chunks from the lightweight chat agent
        nonlocal full_response
        async for chunk in chat_app.async_stream_query(
            message=request.message,
            user_id=request.session_id,
        ):
            # Extract text parts from each streamed chunk
            content = chunk.get("content", {}) or {}
            parts = content.get("parts", []) or []
            for part in parts:
                # Only accumulate non-empty text parts
                if "text" in part and part["text"].strip():
                    full_response += part["text"]

    try:
        # Chat should be fast — enforce a 60s timeout to avoid hanging requests
        await asyncio.wait_for(run_chat(), timeout=60)  # chat should be fast
    except asyncio.TimeoutError:
        print(f"[CHAT] TIMEOUT after 60s", flush=True)
        raise HTTPException(504, "Chat response timed out")

    print(f"[CHAT] done in {time.time()-t0:.1f}s, {len(full_response)} chars", flush=True)
    return {"reply": full_response.strip()}

@app.post("/api/geocode")
async def geocode(request: GeocodeRequest):
    """
    Proxy for Google Geocoding API.
    Keeps the Geocoding API key server-side so it never touches the browser.
    Biases results toward Malaysia since AgroMind is Malaysia-focused.
    Returns Google's raw response shape (status, results, error_message) for
    minimum changes on the Flutter side.
    """
    # Return an error response if the API key is missing from environment
    if not GEOCODING_API_KEY:
        return {
            "status": "REQUEST_DENIED",
            "error_message": "Geocoding key not configured on server",
            "results": [],
        }

    try:
        # Make an async HTTP request to the Google Geocoding API
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                "https://maps.googleapis.com/maps/api/geocode/json",
                params={
                    "address": request.query,
                    "key": GEOCODING_API_KEY,
                    "components": "country:MY",  # restrict to Malaysia
                },
            )
            # Pass Google's response directly to the Flutter client unchanged
            return response.json()
    except httpx.TimeoutException:
        return {
            "status": "ERROR",
            "error_message": "Geocoding request timed out",
            "results": [],
        }
    except Exception as e:
        return {
            "status": "ERROR",
            "error_message": f"Geocoding proxy error: {str(e)}",
            "results": [],
        }


@app.post("/api/analyze")
async def analyze_and_persist(request: AnalyzeRequest):
    """
    Run the AI agent pipeline AND write the results back to Firestore.

    1. Sends the user's message (with geospatial context) to the orchestrator.
    2. Collects the full Markdown report from the Documentarian agent.
    3. Captures the planting-grid output from the Plotter's tool call.
    4. Updates the project's Firestore document with:
       - `reportMarkdown`: the AI-generated business plan.
       - `boundaryPoints`: the farm boundary coordinates.
       - `plantingGrid`: computed timber + intercrop positions (if available).
    5. Returns the report AND the planting grid to the Flutter client.
    """
    # ── 1. Run the agent pipeline ─────────────────────────────────────────
    t0 = time.time()
    full_response = ""
    planting_grid = None

    print(f"\n{'='*60}", flush=True)
    print(f"[ANALYZE] Session: {request.session_id}", flush=True)
    print(f"[ANALYZE] Project: {request.project_id}", flush=True)
    print(f"{'='*60}", flush=True)

    async def run_pipeline():
        nonlocal full_response, planting_grid
        # Stream events from the full 5-agent SequentialAgent pipeline
        async for chunk in adk_app.async_stream_query(
            user_id=request.session_id,
            message=request.message,
        ):
            elapsed = time.time() - t0
            author = chunk.get("author", "?")
            content = chunk.get("content", {}) or {}
            parts = content.get("parts", []) or []

            for part in parts:
                # Log every tool call with its arguments for observability
                if "function_call" in part:
                    fc = part["function_call"]
                    args_str = str(fc.get("args", {}))[:150]
                    print(f"[{elapsed:6.1f}s] {author:30s} → CALL {fc.get('name')}({args_str})", flush=True)

                elif "function_response" in part:
                    fr = part["function_response"]
                    # Capture the planting-grid tool output for the frontend.
                    # ADK sometimes wraps tool returns in {"result": ...}, sometimes not.
                    if fr.get("name") == "calculate_planting_grid":
                        resp = fr.get("response", {}) or {}
                        # Handle both wrapped {"result": ...} and unwrapped response formats
                        candidate = resp.get("result", resp)
                        if isinstance(candidate, dict) and "error" not in candidate:
                            planting_grid = candidate
                            print(f"[{elapsed:6.1f}s] [PLOTTER GRID CAPTURED] "
                                  f"{candidate.get('total_plants')} plants, "
                                  f"{candidate.get('area_hectares')} ha", flush=True)

                    resp_preview = str(fr.get("response", ""))[:200].replace("\n", " ")
                    print(f"[{elapsed:6.1f}s] {author:30s} ← RESP {fr.get('name')}: {resp_preview}", flush=True)

                elif "text" in part:
                    # Accumulate all text output — the final Documentarian output
                    # becomes the Markdown business plan returned to the frontend
                    text = part.get("text", "")
                    if text and text.strip():
                        preview = text[:120].replace("\n", " ")
                        print(f"[{elapsed:6.1f}s] {author:30s} TEXT: {preview}", flush=True)
                        full_response += text

    try:
        # Full pipeline can take up to ~3 minutes — enforce a 300s hard timeout
        await asyncio.wait_for(run_pipeline(), timeout=300)
    except asyncio.TimeoutError:
        print(f"\n[TIMEOUT] Pipeline exceeded 300s — see last agent above", flush=True)
        raise HTTPException(504, "Agent pipeline timed out after 5 minutes")

    print(f"\n[DONE] Total time: {time.time()-t0:.1f}s, response: {len(full_response)} chars, "
          f"grid: {'yes' if planting_grid else 'no'}", flush=True)

    report = full_response.strip()

    # ── 2. Serialise boundary points for Firestore ────────────────────────
    # Convert Pydantic LatLngPoint objects to plain dicts for Firestore storage
    boundary_data = [
        {"latitude": pt.latitude, "longitude": pt.longitude}
        for pt in request.boundary_points
    ]

    # ── 3. Write results back to the project document ─────────────────────
    # Always update the report and boundary; only include plantingGrid if generated
    update_data = {
        "reportMarkdown": report,
        "boundaryPoints": boundary_data,
    }
    if planting_grid:
        update_data["plantingGrid"] = planting_grid

    # Update the specific project document in Firestore using its UUID
    project_ref = db.collection("projects").document(request.project_id)
    project_ref.update(update_data)

    # Return both the Markdown report and the structured planting grid to Flutter
    return {
        "reply": report,
        "plantingGrid": planting_grid,
    }


if __name__ == "__main__":
    # Entry point for running locally: `python main.py`
    # For production/Cloud Run, use: `uvicorn main:app --host 0.0.0.0 --port 8080`
    uvicorn.run(app, host="0.0.0.0", port=8000)