# AgroMind — AI-Driven Agroforestry Decision-Support System

> **Project 2030: MyAI Future Hackathon** — Track 1: Padi & Plates (Agrotech & Food Security)
> Organised by Google Developer Groups On Campus, Universiti Teknologi Malaysia

---

##  Problem Statement

Timber farmers in Malaysia face a painful financial reality: commercial timber species commonly grown in Malaysia can take 10 to 15 years to reach harvest maturity, meaning farmers who commit their land to timber cultivation must endure over a decade of little to no income while waiting for their trees to grow. Every year that passes without a return is a year of mounting losses loan repayments, land maintenance costs, and lost opportunity with no way to course-correct once the trees are in the ground. On top of that, most farmers make these critical long-term decisions without access to soil scientists, agronomists, or geospatial planning tools, meaning they may not even be planting the right timber species for their specific land conditions in the first place.


**AgroMind solves this.** The key insight is simple: the empty space between timber trees does not have to go to waste. By planting short-term cash crops, such as chilli, banana, or pineapple, in between the timber rows during the establishment years, farmers can generate income while their timber matures, turning a decade of waiting into a decade of earning. AgroMind automates this entire planning process, a farmer simply draws their farm boundary on a map and types a single prompt. The system automatically analyses the land using real satellite data, recommends the most suitable timber species and intercrop pairings for that specific location, calculates the full 15-year financial ROI, computes an exact GPS-accurate planting grid showing where every tree and crop should be planted, and generates a professional agroforestry business plan, all in under 3 minutes.

---

##  Key Features

- **AI Land Profiling** — Fetches real elevation and temperature data from Google Earth Engine for any farm location in Malaysia
- **RAG-Powered Crop Recommendations** — Queries the MTC Timber Knowledge Base via Vertex AI Search to recommend species matched to the site's exact climate profile
- **15-Year Financial Projections** — Calculates setup costs, short-term intercrop revenue, and long-term timber ROI
- **Geometric Planting Grid** — Computes exact GPS coordinates for every plant in a 2m-spaced checkerboard pattern using shapely + pyproj
- **AI Business Plan Generation** — Produces a full professional Markdown business plan compiled from all agent outputs
- **Interactive Map UI** — Draw farm boundaries directly on a satellite map; planting grid renders as colour-coded circles
- **Follow-Up Chatbot** — Ask questions about your analysis results in seconds without re-running the full pipeline
- **Persistent Projects** — All reports, boundary points, and planting grids are saved to Firestore and reload on revisit

---

##  System Architecture

AgroMind is a full-stack application — a Python/FastAPI backend running a 5-agent AI pipeline, and a Flutter frontend with an interactive Google Maps interface.

```
Flutter Frontend  ──POST /api/analyze──▶  FastAPI Backend
                                               │
                                    SequentialAgent (ADK)
                                               │
                              ┌────────────────┼────────────────┐
                              ▼                ▼                ▼
                      Land Profiler     Agronomist        ParallelAgent
                       (GEE data)      (RAG / Pro)       ┌──────┴──────┐
                                                     Economist    Plotter
                                                     (Flash)      (shapely)
                                                          └──────┬──────┘
                                                          Documentarian
                                                         (Business Plan)
```

### Google AI Ecosystem Stack

| Component | Technology Used |
|---|---|
| **Intelligence (Brain)** | Gemini 2.5 Pro (Agronomist) + Gemini 2.5 Flash (all other agents) |
| **Orchestrator** | Google Agent Development Kit (ADK) — SequentialAgent + ParallelAgent |
| **Context / RAG** | Vertex AI Search — MTC Timber Knowledge Base (`agromind-sovereign-data_1776315921942`) |
| **Session Memory** | Vertex AI Session Service (VertexAiSessionService) |
| **Long-term Memory** | Vertex AI Memory Bank (VertexAiMemoryBankService) |
| **Deployment** | Google Cloud Run (via Docker + `gcloud run deploy`) |
| **Development** | Google Cloud Workstations + Google Antigravity IDE |
| **Database** | Google Cloud Firestore |
| **Geospatial Data** | Google Earth Engine (SRTM elevation + MODIS temperature) |
| **Geocoding** | Google Maps Geocoding API (proxied server-side) |

---

##  Quick Start

### Prerequisites

- Python 3.11+
- Flutter 3.x
- Google Cloud project with the following APIs enabled:
  - Vertex AI API
  - Earth Engine API
  - Cloud Firestore API
  - Maps JavaScript API
  - Geocoding API
- A Google Earth Engine service account key (`gee-key.json`)
- `gcloud` CLI authenticated: `gcloud auth application-default login`

---

### Backend Setup

```bash
# 1. Navigate to the backend directory
cd backend

# 2. Create and activate a virtual environment
python -m venv venv
.\venv\Scripts\Activate.ps1        # Windows PowerShell
# source venv/bin/activate         # Mac/Linux

# 3. Install dependencies
pip install -r requirements.txt

# 4. Set up credentials
#    Place your GEE service account key as:
#    backend/gee-key.json
#    (This file is gitignored and must NEVER be committed)

# 5. Configure environment variables
cp .env.example .env
# Edit .env and fill in:
#   GEOCODING_API_KEY=<your Google Maps Geocoding API key>

# 6. Authenticate with Google Cloud
gcloud auth application-default login

# 7. Run the backend server
uvicorn main:app --port 8000
```

On successful startup you will see:
```
[OK] Google Earth Engine initialized successfully.
INFO:     Uvicorn running on http://0.0.0.0:8000
```

**Available endpoints:**
- `POST /api/analyze` — Run the full 5-agent pipeline
- `POST /api/chat` — Lightweight follow-up chat
- `POST /api/geocode` — Server-side geocoding proxy

> **Note:** Always run via the virtual environment. From a fresh terminal: `& .\venv\Scripts\python.exe -m uvicorn main:app --port 8000`

---

### Frontend Setup

```bash
# 1. Navigate to the frontend directory
cd frontend

# 2. Install Flutter dependencies
flutter pub get

# 3. Configure environment variables
cp .env.example .env
# Edit .env and fill in:
#   MAPS_API_KEY=<your Google Maps JavaScript API key>
#   FIREBASE_API_KEY=<your Firebase API key>
#   FIREBASE_APP_ID=<your Firebase App ID>
#   FIREBASE_PROJECT_ID=<your Firebase project ID>
#   FIREBASE_MESSAGING_SENDER_ID=<your sender ID>
#   FIREBASE_STORAGE_BUCKET=<your storage bucket>
#   (and any other values listed in .env.example)

# 4. Add your Maps JS API key to web/index.html
#    Replace YOUR_RESTRICTED_MAPS_KEY with your actual key

# 5. Run on web
flutter run -d chrome --web-port=3000 --dart-define-from-file=.env

# Or run on Windows desktop
flutter run -d windows --dart-define-from-file=.env
```

> **Important:** `--dart-define-from-file=.env` is **required**. It injects all API keys into `firebase_options.dart` at compile time via `String.fromEnvironment()`.

---

##  Project Structure

```
AgroMind/
├── backend/
│   ├── main.py                   ← FastAPI app — 3 endpoints, streaming pipeline loop
│   ├── Dockerfile                ← Cloud Run deployment container
│   ├── requirements.txt
│   ├── .env.example              ← Template — copy to .env and fill in secrets
│   ├── fast_memory_setup.py      ← One-time utility to provision Vertex AI Agent Engine
│   └── agromind_engine/
│       ├── agent.py              ← SequentialAgent + ParallelAgent orchestrator
│       ├── chat_agent.py         ← Lightweight follow-up chat agent (Flash, no tools)
│       └── sub_agents/
│           ├── land_profiler/    ← Stage 1: GEE elevation + temperature fetch
│           ├── agronomist/       ← Stage 2: RAG timber + intercrop recommendations
│           ├── economist/        ← Stage 3a: 15-year financial projections
│           ├── plotter/          ← Stage 3b: Geometric planting grid (shapely + pyproj)
│           └── documentarian/   ← Stage 4: Final Markdown business plan
└── frontend/
    ├── lib/
    │   ├── main.dart             ← Firebase init + app entry point
    │   ├── router.dart           ← go_router: /, /dashboard, /project/:id
    │   ├── theme.dart            ← Dark glassmorphic design tokens
    │   ├── models/               ← Project, LatLng, AgentStep, ChatMessage
    │   ├── providers/            ← Riverpod per-project state providers
    │   ├── services/             ← ApiService (HTTP) + ProjectService (Firestore)
    │   ├── screens/              ← LandingScreen, DashboardScreen, ProjectScreen
    │   └── widgets/              ← GlassCard, AgentStepper, AppTopBar
    └── .env.example              ← Template — copy to .env and fill in secrets
```

---

##  The 5 Pipeline Agents

| Stage | Agent | Model | Role | Tools |
|---|---|---|---|---|
| 1 | Land Profiler | Gemini 2.5 Flash | Fetches real GEE elevation + 2025 temperature data | `fetch_land_data` (GEE) |
| 2 | Symbiotic Agronomist | Gemini 2.5 Pro | RAG-based timber + intercrop recommendations | `search_local_agriculture` (Vertex AI Search) |
| 3a | Agro-Economist | Gemini 2.5 Flash | 15-year ROI, costs, and revenue projections | None |
| 3b | Plotter | Gemini 2.5 Flash | Exact GPS coordinates for every plant in a checkerboard grid | `calculate_planting_grid` (shapely + pyproj) |
| 4 | Documentarian | Gemini 2.5 Flash | Compiles all outputs into a professional Markdown business plan | None |

Stages 3a and 3b run **concurrently** inside a `ParallelAgent` — both only depend on the Agronomist's output, saving ~50 seconds of pipeline time.

---

##  Performance

| Stage | Duration |
|---|---|
| Startup → first agent call | ~25–30s |
| Land Profiler (Flash, GEE ~2s) | ~20s |
| Agronomist (Pro, RAG ~5s) | ~40s |
| Parallel (Economist ∥ Plotter) | ~50s |
| Documentarian (Flash) | ~30s |
| **Total (full analysis)** | **~150–165s (~2.5 min)** |
| **Follow-up chat** | **~3–5s** |

---

##  Security & Credential Management

All secrets are managed outside of source control via `.env` files and a layered `.gitignore` structure.

| Secret | Location | Protection |
|---|---|---|
| GEE service account key | `backend/gee-key.json` | Gitignored + dockerignored |
| Geocoding API key | `backend/.env` | Gitignored |
| Firebase config + Maps key | `frontend/.env` | Gitignored |
| `firebase_options.dart` | `frontend/lib/` | Gitignored — generated at build time |

No secrets are hardcoded anywhere in the codebase. All keys are injected via environment variables at runtime (backend) or compile time (frontend).

---

##  Architecture Deep Dive

For full technical documentation including the complete orchestrator design, all API endpoint specifications, the Firestore data model, memory architecture, per-project state isolation, end-to-end data flow, and observability logging — see the sections below.

<details>
<summary><strong>Part 1: Backend (Python / FastAPI)</strong></summary>

### What It Does

The backend is the AI brain of AgroMind. It receives a chat message from the frontend, processes it through a pipeline of 5 coordinated AI agents orchestrated by a SequentialAgent/ParallelAgent structure, and returns a complete analysis response including a Markdown business plan and a geometrically-computed planting grid. All agents run on Google Gemini models via the Google Agent Development Kit (ADK). A separate lightweight chat agent handles follow-up questions without re-running the full pipeline.

### Technology Stack

- Python web framework: FastAPI
- AI agent framework: Google Agent Development Kit (google.adk), run through Vertex AI
- LLM models:
  - Gemini 2.5 Pro — Symbiotic Agronomist (reasoning over RAG results)
  - Gemini 2.5 Flash — Land Profiler, Agro-Economist, Plotter, Documentarian, Chat Agent (3–5× faster than Pro; used for all non-reasoning agents)
- Geospatial data: Google Earth Engine (earthengine-api), authenticated via a service account key (`gee-key.json`) stored in the `backend/` root (gitignored — never committed)
- Geometric computation: shapely and pyproj (used by the Plotter to compute exact planting grids in a local UTM projection)
- RAG / Knowledge retrieval: Vertex AI Search (Discovery Engine) via `google-cloud-discoveryengine`, querying the MTC Timber Knowledge Base data store
- Cloud database: Google Cloud Firestore (google-cloud-firestore) — used to persist AI-generated reports, boundary points, and computed planting grids back to the project document
- Geocoding proxy: httpx (async HTTP client) — used by the `/api/geocode` endpoint to proxy Google Maps Geocoding API requests server-side, keeping the API key off the Flutter client
- Environment variables: python-dotenv — loads `backend/.env` for secrets like `GEOCODING_API_KEY`
- Session memory (short-term): VertexAiSessionService (conversation history stored server-side on Vertex AI, scoped per session ID)
- Long-term memory: VertexAiMemoryBankService with Agent Engine resource `7339574916695457792` on Vertex AI (project `aura-487117`, region `us-central1`). NOTE: Currently inactive — see "Memory Architecture" below.
- Memory save callback: An `after_agent_callback` (`_save_session_to_memory`) registered on the top-level SequentialAgent that writes session data to the Memory Bank after each pipeline completion via `callback_context.add_session_to_memory()`.
- Deployment wrapper: AdkApp from vertexai.preview.reasoning_engines, initialised via `env_vars={"GOOGLE_CLOUD_AGENT_ENGINE_ID": "7339574916695457792"}` so the underlying VertexAiSessionService binds to the correct Reasoning Engine resource. Two AdkApp instances exist: one for the analysis pipeline (`adk_app`) and one for the lightweight chat agent (`chat_app`), both sharing the same Agent Engine ID for session continuity.
- Server: Uvicorn, listening on port 8000

### Orchestrator Architecture

The orchestrator is a **SequentialAgent** (not an LlmAgent) that wraps a 4-stage pipeline:

1. **Land_Profiler_Agent** (Flash)
2. **Symbiotic_Agronomist_Agent** (Pro)
3. **Economist_And_Plotter_Parallel** — a nested `ParallelAgent` containing:
   - **Agro_Economic_Agent** (Flash)
   - **Plotter_Agent** (Flash)
4. **Documentarian_Agent** (Flash)

This structure replaces the earlier LlmAgent + AgentTool pattern and the separate Orchestrator LLM. Key effects:

- No LLM deliberation happens between agent hand-offs. Stages run back-to-back via direct session-state passing, eliminating the ~15–20s per-step orchestrator wrapping tax previously observed.
- The Economist and Plotter run concurrently in Stage 3 since they're independent — both only need the Agronomist's output. The Documentarian reads both results from shared session state in Stage 4.
- Overall pipeline runs in ~150–165 seconds (2.5–2.8 minutes) per request, down from 5.5+ minutes on the original all-Pro LlmAgent orchestrator.

The `_save_session_to_memory` async callback is attached to the top-level SequentialAgent only (not to the nested ParallelAgent).

### API Endpoints

There are three endpoints:

**POST /api/chat** — Lightweight follow-up chat. Uses `AgroMind_Chat_Agent` (not the full pipeline). Timeout: 60s.

**POST /api/geocode** — Server-side proxy for Google Maps Geocoding API. Keeps the key off the browser. Biased toward Malaysia via `components=country:MY`.

**POST /api/analyze** — Primary analysis endpoint. Runs the full 5-agent pipeline and writes results to Firestore. Timeout: 300s.

### Memory Architecture

**Short-Term Memory (Session) — ACTIVE:** Managed by `VertexAiSessionService`. All agents within a session share conversation history. Both the analysis pipeline and chat agent share the same session.
S

</details>

<details>
<summary><strong>Part 2: Frontend (Flutter)</strong></summary>

### What It Does

The frontend is a cross-platform Flutter application (web, Windows, macOS, Android, iOS). It provides a dark-themed, glassmorphic interface where users create projects, draw farm boundaries on an interactive Google Map, send analysis queries to the backend, and view the resulting agroforestry business plan rendered in Markdown alongside a visual planting grid overlaid on the map.

### Technology Stack

- Framework: Flutter (Dart)
- State management: flutter_riverpod (`StateProvider.family<T, String>` keyed by projectId for per-project state isolation)
- Routing: go_router
- Cloud platform: Firebase (firebase_core)
- Cloud database: Cloud Firestore (cloud_firestore)
- Typography: Inter font via google_fonts
- Markdown rendering: flutter_markdown
- Interactive map: google_maps_flutter (Marker for corners, Polygon for AOI, Circle for planting grid)
- HTTP client: http package
- ID generation: uuid package
- Date formatting: intl package

### Design Language

- Background: Deep Dark (#0F172A) / Surface: #1E293B
- Accent: Electric Blue (#3B82F6) / Light: #60A5FA
- Text Primary: #F1F5F9 / Secondary: #94A3B8
- Success: #22C55E / Warning: #FBBF24 / Error: #EF4444
- Glassmorphism: BackdropFilter blur sigma 10, white at 6% opacity, hover to 10% with accent border
- Fully responsive: Desktop (>900px) uses 50/50 Row; mobile stacks map above command center

### Per-Project State Isolation

All interactive state is keyed by `projectId` using `StateProvider.family` to prevent state bleed between projects: `aoiPointsProvider`, `landAreaProvider`, `latestPlantingGridProvider`, `analysisResultProvider`, `currentAgentStepProvider`, `isAnalyzingProvider`, `projectChatHistoryProvider`, `isChattingProvider`.

</details>

<details>
<summary><strong>Part 3: End-to-End Data Flow</strong></summary>

### Analysis Flow

1. User opens the Flutter app; Firebase initialises before the first frame.
2. User navigates to `/dashboard` and creates a new project.
3. On the project page, user draws a farm boundary polygon by tapping the satellite map.
4. User types an analysis request and clicks "Analyze."
5. Frontend validates boundary data, prepends System Context (land area + coordinates), and shows the AgentStepper modal.
6. On the final step, POSTs to `/api/analyze` with sessionId, projectId, enriched message, and boundary points.
7. FastAPI routes to the SequentialAgent — 4 stages run in order, Economist + Plotter in parallel.
8. Backend captures the planting grid from the Plotter tool, writes `reportMarkdown`, `boundaryPoints`, and `plantingGrid` to Firestore, and returns `{reply, plantingGrid}`.
9. Flutter renders the Markdown report and map circles. Firestore stream ensures data persists across navigation.

### Chatbot Flow

1. User switches to the "Chatbot" tab after an analysis.
2. User types a follow-up question and clicks "Send."
3. Frontend POSTs to `/api/chat` with the project's `sessionId`.
4. Backend routes to `AgroMind_Chat_Agent` which reads the shared Vertex AI session history.
5. Response arrives in ~3–5 seconds. Frontend renders it as a styled assistant bubble.

</details>

---

##  AI-Generated Code Disclosure

AI coding assistants (including Gemini and Antigravity) were utilised during the development of this project to accelerate boilerplate generation, assist with syntax debugging, and provide structural recommendations. However, all core system architecture, geospatial logic, agent workflows, prompt engineering, and system designs were explicitly engineered by our team. Every team member is able to explain and defend all parts of the codebase.
