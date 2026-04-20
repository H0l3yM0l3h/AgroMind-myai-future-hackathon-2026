# main.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import uvicorn
import time
import asyncio
import os
import httpx
from dotenv import load_dotenv

from vertexai.preview.reasoning_engines import AdkApp
from google.cloud import firestore

from agromind_engine import orchestrator_agent, chat_agent


# Load environment variables from backend/.env (gitignored)
load_dotenv()

GEOCODING_API_KEY = os.environ.get("GEOCODING_API_KEY", "")

AGENT_ENGINE_ID = "7339574916695457792"

# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------
app = FastAPI(title="AgroMind — Agroforestry Decision-Support API")

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
class LatLngPoint(BaseModel):
    latitude: float
    longitude: float


class ChatRequest(BaseModel):
    session_id: str
    message: str


class AnalyzeRequest(BaseModel):
    """Request body for the /api/analyze endpoint."""
    session_id: str
    project_id: str
    message: str
    boundary_points: list[LatLngPoint] = []


class GeocodeRequest(BaseModel):
    query: str


@app.post("/api/chat")
async def chat_with_orchestrator(request: ChatRequest):
    t0 = time.time()
    print(f"\n[CHAT] session={request.session_id} msg={request.message[:80]!r}", flush=True)

    full_response = ""

    async def run_chat():
        nonlocal full_response
        async for chunk in chat_app.async_stream_query(
            message=request.message,
            user_id=request.session_id,
        ):
            content = chunk.get("content", {}) or {}
            parts = content.get("parts", []) or []
            for part in parts:
                if "text" in part and part["text"].strip():
                    full_response += part["text"]

    try:
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
    if not GEOCODING_API_KEY:
        return {
            "status": "REQUEST_DENIED",
            "error_message": "Geocoding key not configured on server",
            "results": [],
        }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                "https://maps.googleapis.com/maps/api/geocode/json",
                params={
                    "address": request.query,
                    "key": GEOCODING_API_KEY,
                    "components": "country:MY",  # restrict to Malaysia
                },
            )
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
        async for chunk in adk_app.async_stream_query(
            user_id=request.session_id,
            message=request.message,
        ):
            elapsed = time.time() - t0
            author = chunk.get("author", "?")
            content = chunk.get("content", {}) or {}
            parts = content.get("parts", []) or []

            for part in parts:
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
                        candidate = resp.get("result", resp)
                        if isinstance(candidate, dict) and "error" not in candidate:
                            planting_grid = candidate
                            print(f"[{elapsed:6.1f}s] [PLOTTER GRID CAPTURED] "
                                  f"{candidate.get('total_plants')} plants, "
                                  f"{candidate.get('area_hectares')} ha", flush=True)

                    resp_preview = str(fr.get("response", ""))[:200].replace("\n", " ")
                    print(f"[{elapsed:6.1f}s] {author:30s} ← RESP {fr.get('name')}: {resp_preview}", flush=True)

                elif "text" in part:
                    text = part.get("text", "")
                    if text and text.strip():
                        preview = text[:120].replace("\n", " ")
                        print(f"[{elapsed:6.1f}s] {author:30s} TEXT: {preview}", flush=True)
                        full_response += text

    try:
        await asyncio.wait_for(run_pipeline(), timeout=300)
    except asyncio.TimeoutError:
        print(f"\n[TIMEOUT] Pipeline exceeded 300s — see last agent above", flush=True)
        raise HTTPException(504, "Agent pipeline timed out after 5 minutes")

    print(f"\n[DONE] Total time: {time.time()-t0:.1f}s, response: {len(full_response)} chars, "
          f"grid: {'yes' if planting_grid else 'no'}", flush=True)

    report = full_response.strip()

    # ── 2. Serialise boundary points for Firestore ────────────────────────
    boundary_data = [
        {"latitude": pt.latitude, "longitude": pt.longitude}
        for pt in request.boundary_points
    ]

    # ── 3. Write results back to the project document ─────────────────────
    update_data = {
        "reportMarkdown": report,
        "boundaryPoints": boundary_data,
    }
    if planting_grid:
        update_data["plantingGrid"] = planting_grid

    project_ref = db.collection("projects").document(request.project_id)
    project_ref.update(update_data)

    return {
        "reply": report,
        "plantingGrid": planting_grid,
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)