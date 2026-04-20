# AgroMind — Full System Overview

AgroMind is an AI-driven geospatial decision-support system built for the "Project 2030: MyAI Future Hackathon." It helps farmers maximize land yield through agroforestry planning. A farmer provides a location, and the system automatically analyzes the land, recommends crops, calculates financials, plans planting layout, and generates a professional business plan — all through a single chat prompt.

The system is a full-stack application with a Python backend and a Flutter frontend.


---


## Part 1: Backend (Python / FastAPI)


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


### Backend File Structure

```
backend/
├── main.py                   ← Instrumented streaming loop, captures planting grid from Plotter tool output
├── .gitignore                ← Credential patterns, venv, __pycache__, IDE files
├── .dockerignore             ← Prevents secrets from being baked into Docker images
├── .env                      ← GEOCODING_API_KEY and other server-side secrets (GITIGNORED — never committed)
├── .env.example              ← Template with placeholder values (safe to commit)
├── gee-key.json              ← GEE service account key (GITIGNORED — never committed)
├── fast_memory_setup.py      ← Utility script to provision an empty Agent Engine for Memory Bank on Vertex AI
├── agent.py                  ← DEPRECATED / unused legacy file — do not import
├── Dockerfile
├── requirements.txt
├── agromind_engine/
│   ├── __init__.py           ← Re-exports orchestrator_agent + chat_agent
│   ├── agent.py              ← SequentialAgent wrapping: Land_Profiler → Agronomist → Parallel(Economist, Plotter) → Documentarian
│   ├── chat_agent.py         ← Lightweight LlmAgent for follow-up questions (Flash, no tools)
│   └── sub_agents/
│       ├── __init__.py
│       ├── land_profiler/
│       │   ├── __init__.py
│       │   ├── prompt.py
│       │   └── agent.py      ← Flash; GEE auth; fetch_land_data tool
│       ├── agronomist/
│       │   ├── __init__.py
│       │   ├── prompt.py     ← Tightened: "EXACTLY TWO queries, then stop"
│       │   └── agent.py      ← Pro; search_local_agriculture RAG tool
│       ├── economist/
│       │   ├── __init__.py
│       │   ├── prompt.py
│       │   └── agent.py      ← Flash; no tools
│       ├── plotter/
│       │   ├── __init__.py
│       │   ├── prompt.py     ← Rewritten: "call the tool, trust its numbers"
│       │   └── agent.py      ← Flash; calculate_planting_grid tool (shapely + pyproj)
│       └── documentarian/
│           ├── __init__.py
│           ├── prompt.py
│           └── agent.py      ← Flash; no tools
```


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


### Chat Agent

A separate **AgroMind_Chat_Agent** (`chat_agent.py`) handles lightweight follow-up questions after the analysis pipeline has completed. It is wrapped in its own `AdkApp` instance (`chat_app`) that shares the same Agent Engine ID as the analysis pipeline, so both agents see the same Vertex AI session history.

- Internal name: `AgroMind_Chat_Agent`
- Model: `gemini-2.5-flash`
- Tools: None — pure LLM reasoning against conversation context.
- Behaviour rules:
  - Answers concisely (under 200 words unless more detail is requested).
  - Only uses information from the prior conversation — does not fabricate numbers or species.
  - Honestly states when something was not covered in the analysis.
  - Does not call tools or other agents.
- Timeout: 60 seconds (compared to 300 seconds for the full pipeline).


### The 5 Pipeline Agents


#### 1. Land Profiler

- Internal name: Land_Profiler_Agent
- Model: `gemini-2.5-flash`
- File: agromind_engine/sub_agents/land_profiler/agent.py
- Role: Land and climate analyst specializing in tropical agroforestry for Malaysia. Fetches real elevation and temperature data from Google Earth Engine, then interprets it for agroforestry and intercropping viability.
- GEE Authentication: On module load, authenticates with Google Earth Engine using `ee.ServiceAccountCredentials` with email `aura-gee-service@aura-487117.iam.gserviceaccount.com` and the key file `gee-key.json` (path resolved relative to the backend root via `os.path.dirname(__file__)`). Initialization is wrapped in a try/except and prints `[OK] Google Earth Engine initialized successfully.` on success.
- Instrumentation: `fetch_land_data` prints `[GEE] fetch_land_data(...) START/DONE/FAILED` with timing for each call.
- System instruction (multi-step workflow):
  1. Read the "System Context" block from the pipeline (contains `boundaries` list and `land_area_hectares`).
  2. Extract the first `[lat, lng]` coordinate pair from the boundaries.
  3. Call the `fetch_land_data` tool with those coordinates.
  4. Analyze the elevation and 2025 temperature data for agroforestry and intercropping viability in Malaysia.
  5. Output a structured, scientific Land Profile Summary.
- Tools:
  - `fetch_land_data(lat: float, lng: float) -> str` — fetches SRTM elevation (`USGS/SRTMGL1_003`, 30m) and MODIS mean 2025 land-surface temperature (`MODIS/061/MOD11A2`, 1km) for the given point. Converts Kelvin to Celsius. Returns a formatted string or an error message.


#### 2. Symbiotic Agronomist

- Internal name: Symbiotic_Agronomist_Agent
- Model: `gemini-2.5-pro` (only agent still on Pro — needs reasoning over RAG results)
- File: agromind_engine/sub_agents/agronomist/agent.py
- Role: Elite Agronomist specializing in Malaysian agroforestry. Uses RAG via Vertex AI Search to query the MTC Timber Knowledge Base, then cross-references results with the Land Profiler's climate data to recommend optimal timber species and intercrop pairings.
- RAG Data Store: Vertex AI Search (Discovery Engine) data store `agromind-sovereign-data_1776315921942` in project `aura-487117`, location `global`.
- Instrumentation: `search_local_agriculture` prints `[RAG] search(...) START/DONE/FAILED` with timing and result character count.
- System instruction (tightened to prevent retry loops):
  1. Analyse the Land Profiler's elevation and 2025 temperature data. Classify the site as lowland (< 300 m), hill (300–900 m), or montane (> 900 m).
  2. Call `search_local_agriculture` **EXACTLY TWICE**:
     - Query 1: timber species matching the elevation band and temperature range.
     - Query 2: compatible short-term intercrops for the chosen timber during the establishment phase (Years 1–5).
  3. After the second tool call, STOP. Do not call the tool a third time under any circumstances. Immediately write the recommendation.
  4. Output a concise structured recommendation: Primary Timber, Secondary Timber, Intercrop, Confidence & Sources.
- Tools:
  - `search_local_agriculture(query: str) -> str` — calls Vertex AI Search, returns combined top-3 snippets as formatted text.


#### 3. Agro-Economist

- Internal name: Agro_Economic_Agent
- Model: `gemini-2.5-flash`
- File: agromind_engine/sub_agents/economist/agent.py
- Role: Financial analyst. Calculates estimated costs, short-term revenue from cash crops, and the 15-year long-term ROI from timber harvest based on the recommended species.
- Tools: None. Pure LLM reasoning.
- Execution: Runs concurrently with the Plotter in Stage 3 of the pipeline.


#### 4. Plotter

- Internal name: Plotter_Agent
- Model: `gemini-2.5-flash`
- File: agromind_engine/sub_agents/plotter/agent.py
- Role: Geospatial engineer. Computes the exact number and GPS coordinates of every timber tree and intercrop plant that fits in the given area, using a strict 2-meter spacing rule in a checkerboard pattern.
- **Replaced LLM math with a real geometric tool.** Previously, the Plotter had no tools and produced plausible-but-unverified numbers via LLM reasoning. It now delegates all math to a Python function.
- System instruction: Call the `calculate_planting_grid` tool with the boundary coordinates from System Context, trust its numbers exactly, and write a short (<120 word) summary. Do not perform arithmetic. Do not include the raw coordinate lists in the text output (the frontend reads them separately from the tool output).
- Tools:
  - `calculate_planting_grid(boundary_points: list, spacing_meters: float = 2.0) -> dict` — a Python function that:
    - Accepts a list of `{"latitude", "longitude"}` dicts.
    - Picks a UTM zone based on the polygon's centroid for metric-accurate math.
    - Builds a `shapely.Polygon` in UTM coordinates (meters).
    - Fixes invalid self-intersecting polygons via `.buffer(0)`.
    - Auto-adjusts `spacing_meters` upward if the grid would exceed 5,000 plants (safety cap to keep the Flutter map responsive).
    - Generates a 2m-spaced grid of `Point`s, filters to those inside the polygon, and alternates them between timber and intercrop in a checkerboard pattern (`(row + col) % 2`).
    - Converts every grid point back to WGS84 lat/lng for rendering.
    - Returns a dict: `{total_plants, timber_count, intercrop_count, area_hectares, spacing_meters, timber_positions: [{latitude, longitude}, ...], intercrop_positions: [...]}`
    - Instrumentation: Prints `[PLOTTER] calculate_planting_grid(...) START/DONE/FAILED` with timing.
- Execution: Runs concurrently with the Economist in Stage 3 of the pipeline. The tool itself completes in <0.1s; the agent's inference + summary takes ~50s.


#### 5. Documentarian

- Internal name: Documentarian_Agent
- Model: `gemini-2.5-flash`
- File: agromind_engine/sub_agents/documentarian/agent.py
- Role: Technical writer. Takes the outputs of all prior agents (available via shared session state) and formats them into a professional, structured Agroforestry Business Plan in Markdown.
- System instruction: Pure text generation and formatting.
- Tools: None.


### API Endpoints

There are three endpoints:

#### POST /api/chat

A lightweight chat endpoint for follow-up questions. Uses the dedicated `AgroMind_Chat_Agent` (not the full analysis pipeline), so responses arrive in seconds rather than minutes. The chat agent shares the same Vertex AI session as the analysis pipeline, giving it full visibility of prior agent outputs.

Request body (JSON):
  - session_id: A string identifying the conversation session.
  - message: The user's natural-language query.

Response body (JSON):
  - reply: The chat agent's full aggregated text response.

Timeout: 60 seconds.

#### POST /api/geocode

A server-side proxy for the Google Maps Geocoding API. Keeps the Geocoding API key (`GEOCODING_API_KEY` from `backend/.env`) on the server so it never touches the browser. Results are biased toward Malaysia via the `components=country:MY` parameter.

Request body (JSON):
  - query: The place name or address to geocode.

Response body (JSON): Google's raw geocoding response shape (`status`, `results`, `error_message`), passed through from the upstream API for minimum changes on the Flutter side.

Error handling:
  - Returns `REQUEST_DENIED` if `GEOCODING_API_KEY` is not configured.
  - Returns `ERROR` with message on timeout (10s) or proxy failure.

#### POST /api/analyze

The primary analysis endpoint. Runs the AI agent pipeline AND writes the results back to Firestore.

Request body (JSON):
  - session_id: A string identifying the conversation session.
  - project_id: The Firestore document ID of the project to update.
  - message: The user's natural-language query (with geospatial context).
  - boundary_points: A list of `{"latitude": float, "longitude": float}` objects representing the farm boundary.

Response body (JSON):
  - reply: The orchestrator's full aggregated text response (Markdown business plan).
  - plantingGrid: The computed planting grid dict from the Plotter's tool (or null if not generated).

The endpoint runs the agent pipeline under a 300-second timeout (`asyncio.wait_for`). It streams events chunk-by-chunk, logging each `function_call`, `function_response`, and `text` part with elapsed-time stamps. It specifically captures the `calculate_planting_grid` tool response and exposes it separately to the frontend.

After the AI generates the report, the endpoint updates the Firestore document at `projects/{project_id}` with:
  - `reportMarkdown`: The full Markdown business plan.
  - `boundaryPoints`: The farm boundary coordinates.
  - `plantingGrid`: The computed grid (only if successfully generated and error-free).


### Observability / Instrumentation

Every request produces a structured terminal log showing per-agent timing and tool activity. Example:

```
============================================================
[ANALYZE] Session: <uuid>
[ANALYZE] Project: <uuid>
============================================================
[  25.8s] Land_Profiler_Agent            → CALL fetch_land_data(...)
[GEE]     fetch_land_data(...) START
[GEE]     fetch_land_data DONE in 3.3s
[  32.2s] Land_Profiler_Agent            ← RESP fetch_land_data: {...}
[  45.3s] Land_Profiler_Agent            TEXT: ### Land Profile Summary ...
[  53.5s] Symbiotic_Agronomist_Agent     → CALL search_local_agriculture(...)
[RAG]     search(...) DONE in 1.4s, 557 chars returned
[  93.1s] Symbiotic_Agronomist_Agent     TEXT: ### Primary Timber ...
[ 103.1s] Plotter_Agent                  → CALL calculate_planting_grid(...)
[PLOTTER] calculate_planting_grid(4 pts, spacing=2m) START
[PLOTTER] DONE in 0.0s: 661 plants (329 timber, 332 intercrop) on 0.2643 ha
[ 106.9s] [PLOTTER GRID CAPTURED] 661 plants, 0.2643 ha
[ 126.1s] Agro_Economic_Agent            TEXT: ...financial analysis...
[ 156.5s] Documentarian_Agent            TEXT: # Agroforestry Business Plan ...
[DONE] Total time: 160.0s, response: 23428 chars, grid: yes
```

Chat requests log a shorter form:
```
[CHAT] session=<uuid> msg='What was the primary timber?'
[CHAT] done in 4.2s, 312 chars
```

This log is the primary debugging tool — every tool call, response, and text emission is visible with sub-second precision.


### Firestore Client

A `firestore.Client(project="aura-487117")` is instantiated once at module level and reused across all requests. It writes to the `projects` collection, using the project's UUID as the document ID.


### How the Backend Processes a Request

#### Analysis Request (`/api/analyze`)

1. The frontend sends a POST request to `/api/analyze` with a session_id, project_id, message, and boundary_points.
2. FastAPI passes the message to the `adk_app` (analysis AdkApp), which routes it to the top-level SequentialAgent.
3. Stage 1: Land Profiler (Flash) runs — reads System Context, calls `fetch_land_data`, writes a Land Profile Summary.
4. Stage 2: Agronomist (Pro) runs — classifies elevation band, calls `search_local_agriculture` exactly twice, writes a timber + intercrop recommendation.
5. Stage 3 (parallel): Economist (Flash) and Plotter (Flash) run concurrently. Plotter calls `calculate_planting_grid` which synchronously returns exact counts and every plant's lat/lng.
6. Stage 4: Documentarian (Flash) reads all prior outputs from shared session state and writes the final Markdown business plan.
7. Throughout, the backend captures the `calculate_planting_grid` tool response separately for return to the frontend.
8. The backend writes `reportMarkdown`, `boundaryPoints`, and `plantingGrid` to Firestore.
9. The backend returns JSON with both `reply` (Markdown) and `plantingGrid` (structured data) to the Flutter frontend.

#### Chat Request (`/api/chat`)

1. The frontend sends a POST request to `/api/chat` with a session_id and message.
2. FastAPI passes the message to the `chat_app` (chat AdkApp), which routes it to the `AgroMind_Chat_Agent`.
3. The chat agent reads the existing conversation history (including all prior analysis outputs) from the shared Vertex AI session and generates a concise answer.
4. The backend returns `{reply}` JSON to the Flutter frontend.


### Memory Architecture

The system uses a two-tier memory architecture, though long-term memory is currently inactive following the SequentialAgent migration.

#### Short-Term Memory (Session) — ACTIVE

Managed by `VertexAiSessionService`. Server-side session store on Vertex AI. Within a single session (identified by `session_id`), all agents see prior messages and prior agent outputs via shared session state. Each new `session_id` starts with a blank slate. Both the analysis pipeline and the chat agent share the same session, enabling the chat agent to answer follow-up questions about prior analysis results.

#### Long-Term Memory (Memory Bank) — CURRENTLY INACTIVE

Managed by `VertexAiMemoryBankService` with Agent Engine resource `7339574916695457792`.

**Write path:** The `_save_session_to_memory` callback remains registered on the top-level SequentialAgent. Whether `callback_context.add_session_to_memory()` still functions correctly under SequentialAgent (vs. the old LlmAgent) has not been verified in this session; errors are silently caught.

**Read path:** Non-functional in the current architecture:
- `PreloadMemoryTool` was disabled before the SequentialAgent migration to eliminate ~30s of per-request startup latency. It cannot simply be re-enabled because SequentialAgent does not accept a `tools=[]` parameter.
- `LoadMemoryTool` was removed during the SequentialAgent migration for the same reason.

**To restore long-term memory:** the cleanest approach is to add `PreloadMemoryTool` and `LoadMemoryTool` to the Agronomist (the one agent where cross-session knowledge genuinely helps — e.g. "last time in a similar climate, user chose Meranti"). The other four agents derive everything from the current request and don't benefit from memory. This is a post-hackathon enhancement.


---


## Part 2: Frontend (Flutter)


### What It Does

The frontend is a cross-platform Flutter application (web, Windows, macOS, Android, iOS). It provides a dark-themed, glassmorphic interface where users create projects, draw farm boundaries on an interactive Google Map, send analysis queries to the backend, and view the resulting agroforestry business plan rendered in Markdown alongside a visual planting grid overlaid on the map. A dedicated Chatbot tab allows users to ask follow-up questions about their analysis results without re-running the full pipeline.


### Technology Stack

- Framework: Flutter (Dart)
- State management: flutter_riverpod (now using `StateProvider.family<T, String>` keyed by projectId for per-project state isolation)
- Routing: go_router
- Cloud platform: Firebase (firebase_core)
- Cloud database: Cloud Firestore (cloud_firestore)
- Typography: Inter font via google_fonts
- Markdown rendering: flutter_markdown
- Interactive map: google_maps_flutter (using `Marker` for boundary corners, `Polygon` for the AOI shape, `Circle` for planting-grid dots)
- Geocoding: Proxied through the backend's `/api/geocode` endpoint (keeps Google Maps Geocoding API key server-side)
- HTTP client: http package
- ID generation: uuid package
- Date formatting: intl package


### Design Language

- Background: Deep Dark (#0F172A)
- Surface panels: #1E293B
- Accent color: Electric Blue (#3B82F6), with a lighter variant (#60A5FA)
- Text primary: #F1F5F9, Text secondary: #94A3B8
- Success: #22C55E, Warning: #FBBF24, Error: #EF4444
- Planting grid: Timber = Green, Intercrop = Amber
- Glassmorphism: BackdropFilter blur sigma 10, white at 6% opacity background, white at 10% opacity border. Hover brightens to 10% opacity with accent-color border.
- All fonts: Inter via Google Fonts
- Border radius: 16px on cards, 12px on buttons and inputs
- All layouts are responsive using LayoutBuilder. Desktop (> ~900px) uses a 50/50 Row. Mobile stacks the map above the command center.


### Frontend File Structure

```
frontend/
├── .gitignore                ← Ignores .env, firebase_options.dart, build/, IDE files
├── .env                      ← All API keys & Firebase config (GITIGNORED — never committed)
├── .env.example              ← Template with placeholder values (safe to commit)
├── pubspec.yaml
├── firebase.json
├── web/
│   └── index.html            ← Maps JS API key placeholder (restrict via GCP Console)
├── android/app/
│   └── google-services.json  ← Firebase Android client config (identifier, not a secret)
└── lib/
    ├── main.dart                 ← Initialises Firebase before runApp
    ├── firebase_options.dart     ← Reads all keys from .env via String.fromEnvironment() (GITIGNORED)
    ├── theme.dart
    ├── router.dart
    ├── models/
    │   ├── project.dart          ← Includes toMap/fromMap + reportMarkdown, boundaryPoints, AND plantingGrid
    │   ├── agent_step.dart
    │   ├── chat_message.dart     ← ChatRole enum (user/assistant) + ChatMessage model
    │   └── lat_lng.dart
    ├── services/
    │   ├── api_service.dart      ← chat() + analyze() — two methods for two endpoints
    │   └── project_service.dart  ← Firestore CRUD
    ├── providers/
    │   └── app_providers.dart    ← Per-project family providers + global singletons + per-project chat providers
    ├── screens/
    │   ├── landing_screen.dart
    │   ├── dashboard_screen.dart
    │   └── project_screen.dart   ← Map with AOI + planting grid circles + search bar + tabbed Report/Chatbot pane
    └── widgets/
        ├── glass_card.dart
        ├── agent_stepper.dart
        └── app_top_bar.dart
```


### Per-Project State Isolation

To prevent state bleed between projects (e.g. a polygon drawn in Project A leaking into Project B), the following providers were converted from global `StateProvider<T>` to `StateProvider.family<T, String>` keyed by `projectId`:

- `aoiPointsProvider`
- `landAreaProvider`
- `latestPlantingGridProvider`
- `analysisResultProvider`
- `currentAgentStepProvider`
- `isAnalyzingProvider`
- `projectChatHistoryProvider` (per-project chat thread)
- `isChattingProvider` (per-project chat loading state)

Every consumer passes `widget.projectId` when reading or writing, e.g.:
```dart
ref.watch(aoiPointsProvider(widget.projectId))
ref.read(analysisResultProvider(widget.projectId).notifier).state = reply;
```

The following providers remain global singletons (no per-project keying):
- `apiServiceProvider`, `projectServiceProvider`, `projectListProvider`, `chatHistoryProvider`

Effects:
- Drawing a polygon in Project A does NOT leak into Project B.
- Analyzing Project A does NOT set `isAnalyzing` on Project B.
- Chatbot history is isolated per project — each project has its own chat thread.
- Navigating away and back within a session preserves each project's in-memory state under its key.
- Firestore-persisted fields (`reportMarkdown`, `boundaryPoints`, `plantingGrid`) still load correctly per project from the Firestore stream.


### File Descriptions


#### main.dart

App entry point. `WidgetsFlutterBinding.ensureInitialized()` → `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` → runApp inside a Riverpod `ProviderScope`. Builds a `MaterialApp.router` with the dark theme and the router config.


#### firebase_options.dart

Gitignored. All Firebase API keys and config values are read from compile-time environment variables via `const String.fromEnvironment()`. Injected at build time via `--dart-define-from-file=.env`.


#### theme.dart

AppTheme class with design tokens: brand colors, glassmorphic BoxDecorations, dark ThemeData, Inter font, themed buttons/inputs/dialogs.


#### router.dart

Three routes via go_router:
- `/` → LandingScreen
- `/dashboard` → DashboardScreen
- `/project/:id` → ProjectScreen


#### models/project.dart

The Project data model with eight fields:
- id (UUID)
- name
- description
- createdAt (DateTime)
- sessionId (UUID; separate from `id` so each project owns its own backend conversation session)
- reportMarkdown (nullable String) — AI-generated business plan persisted by the backend
- boundaryPoints (nullable List<Map<String, double>>) — persisted farm boundary
- **plantingGrid (nullable Map<String, dynamic>) — persisted computed grid from the Plotter**: contains `total_plants`, `timber_count`, `intercrop_count`, `area_hectares`, `spacing_meters`, `timber_positions` (list of {latitude, longitude}), `intercrop_positions` (list of {latitude, longitude}).

Includes `toMap()`, `fromMap()`, and `copyWith()`. All three handle the optional `plantingGrid` safely (only included when non-null; cast defensively in `fromMap`).


#### models/chat_message.dart

Lightweight chat message model used by the global `chatHistoryProvider` (analysis conversation). Contains:
- `ChatRole` enum: `user`, `assistant`.
- `ChatMessage` class: `role`, `content`, `timestamp`.


#### models/lat_lng.dart

Lightweight lat/lng model used by the AOI drawing system.


#### models/agent_step.dart

Enum for the 5 pipeline stages with labels + subtitles.


#### services/api_service.dart

Two methods:

- `chat(sessionId, message) -> Future<String>` — POSTs to `/api/chat`, returns the reply string. Used by the Chatbot tab for lightweight follow-up questions.
- `analyze(sessionId, projectId, message, boundaryPoints) -> Future<({String reply, Map<String, dynamic>? plantingGrid})>` — POSTs to `/api/analyze`. Returns a Dart record containing both the Markdown reply and the structured planting grid dict. All existing call sites were updated to use `result.reply` and `result.plantingGrid`.

The base URL is hardcoded to `http://localhost:8000`.


#### services/project_service.dart

Firestore CRUD:
- `streamProjects()` — Stream<List<Project>> ordered by createdAt desc.
- `addProject(name, description)` — writes a new project doc with UUIDs.
- `deleteProject(id)` — deletes a project doc.


#### providers/app_providers.dart

- `apiServiceProvider`, `projectServiceProvider` — global singletons.
- `projectListProvider` — global StreamProvider<List<Project>>.
- `aoiPointsProvider`, `landAreaProvider`, `latestPlantingGridProvider`, `analysisResultProvider`, `currentAgentStepProvider`, `isAnalyzingProvider` — **all are `StateProvider.family<T, String>` keyed by projectId**.
- `chatHistoryProvider` — global (not per-project). Uses `ChatMessage` model.
- `projectChatHistoryProvider` — **`StateProvider.family<List<Map<String, String>>, String>` keyed by projectId**. Stores per-project chatbot thread as `[{role, content}, ...]` maps.
- `isChattingProvider` — **`StateProvider.family<bool, String>` keyed by projectId**. Loading state for the chatbot.


#### widgets/glass_card.dart

Glassmorphic card with ClipRRect + BackdropFilter (sigma 10) + hover animation to accent color.


#### widgets/agent_stepper.dart

Vertical visual progress indicator for the 5 pipeline stages. Each step is Pending (outline), Active (spinner + glow), or Complete (green check). Displayed inside a non-dismissible glassmorphic modal popup triggered by the "Analyze" button.


#### widgets/app_top_bar.dart

64px glassmorphic top bar with AgroMind logo and optional "Launch Dashboard" button.


#### screens/landing_screen.dart

Hero landing page with decorative gradient orbs, title, subtitle, CTA button, feature grid, and footer.


#### screens/dashboard_screen.dart

Project management page. Watches `projectListProvider`. Empty state, project grid, new-project dialog, delete confirmation dialog.


#### screens/project_screen.dart

The main analysis interface at route `/project/:id`. Watches `projectListProvider` and looks up the project by matching `widget.projectId`. On desktop, 2-column Row; on mobile, stacked scrollable column.

**Left pane — `_InteractiveMap` widget:**

- A `google_maps_flutter` GoogleMap in hybrid (satellite + road) view.
- Initial camera: Malaysia (4.2105°N, 108.9758°E, zoom 6).
- **`_mapController` is a `Completer<GoogleMapController>`** so the search bar can animate the camera asynchronously.
- User taps on the map to draw AOI boundary points — stored in `aoiPointsProvider(projectId)`. First point is green, subsequent are azure, connected by a polyline (≥2 points) and filled as a semi-transparent blue polygon (≥3 points). Polygon area in hectares is computed via a spherical-excess formula and stored in `landAreaProvider(projectId)`.
- **Planting grid rendering**: when `latestPlantingGridProvider(projectId)` OR the persisted `project.plantingGrid` contains data, the map renders each plant position as a `Circle` (not a Marker):
  - Timber positions → green circle, radius 0.5m, stroke `Colors.green.shade900`
  - Intercrop positions → amber circle, radius 0.5m, stroke `Colors.amber.shade900`
  - (Markers with `BitmapDescriptor.defaultMarkerWithHue` were tried first but render as default red on Flutter Web; Circles work reliably across platforms.)
  - Grid points are passed to `GoogleMap` via the `circles:` parameter, not `markers:`. The boundary corner pins stay as Markers.

**Map overlays (inside the Stack):**

1. **Top-center: `_MapSearchBar`** — a glassmorphic input that accepts either a place name (e.g. "Kuala Lumpur") or direct coordinates (e.g. `3.1390, 101.6869` or `3.14 101.69`):
   - A regex first attempts to parse the input as two comma/space-separated numbers (optional `°` symbol allowed).
   - If the input is a place name, it calls the **backend geocoding proxy** via `POST http://localhost:8000/api/geocode` with `{"query": "..."}`. This keeps the Geocoding API key server-side.
   - On success, `animateCamera(CameraUpdate.newLatLngZoom(target, 15))` moves the map to the target.
   - On failure, shows a red floating SnackBar.
2. **Top-left (shifted to `top: 64` to avoid search-bar overlap): area badge** — shows "Tap on the map to draw boundary" / "2 points — need at least 3" / "5.23 ha (4 pts)".
3. **Top-right (shifted to `top: 64`): Undo and Clear buttons** — remove last point or reset the entire boundary.
4. **Bottom-left: legend overlay** — only shown when `plantingGrid` is non-null. Displays:
   - Green dot + "Timber (N)"
   - Amber dot + "Intercrop (N)"
   - "<total> plants @ Xm" caption
   Uses a private `_LegendRow` helper widget.

**Right pane — Tabbed AI Analysis Command Center (`_RightTabContainer`):**

The right pane is a `GlassCard` containing a title area and a `TabBarView` with two tabs:

1. Title area: "AI Analysis Command Center" + project name in accent blue.
2. **`_TabBarHeader`**: A styled tab bar with two tabs — "Report" (article icon) and "Chatbot" (chat bubble icon). Uses a custom rounded indicator with accent color.

**Tab 1 — Report (`_ReportTab`):**

- Results display with 3-tier priority:
   - **Priority 1:** Fresh `analysisResultProvider(projectId)` from the current session.
   - **Priority 2:** Persisted `project.reportMarkdown` from Firestore.
   - **Priority 3:** Loading spinner or empty-state illustration ("No report generated yet").
- All Markdown is rendered via flutter_markdown with custom styled headings, paragraphs, bullet points, tables, blockquotes, and code blocks (Fira Code for monospace).
- **Bottom input bar:** TextField + "Analyze" button (both disabled while `isAnalyzingProvider(projectId)` is true).

**Tab 2 — Chatbot (`_ChatbotTab`):**

- Per-project chat thread stored in `projectChatHistoryProvider(projectId)` as a list of `{role, content}` maps.
- Messages rendered as **bubble-style chat** with alignment (user messages right, assistant messages left) and distinct styling:
  - User bubbles: accent blue background with 25% opacity.
  - Assistant bubbles: surface color with 60% opacity. Content rendered as `MarkdownBody` with custom stylesheet.
  - Typing indicator: spinner + "Thinking…" shown while `isChattingProvider(projectId)` is true.
- **Auto-scroll**: `ref.listen` triggers `_scrollToBottom()` on new messages via `ScrollController.animateTo`.
- Empty state: "Ask follow-up questions" illustration.
- **Bottom input bar:** TextField + "Send" button (both disabled while chatting).

**`_sendMessage` behavior (analysis):**
1. Validate that `aoiPointsProvider(projectId)` is non-empty and `landAreaProvider(projectId) > 0`. If not, show a floating SnackBar: "Please draw your farm boundary on the map before analyzing." and abort.
2. Build an enriched payload prepending a "System Context" header with the land area and boundary coordinates.
3. Clear the input, set `isAnalyzing` to true, clear prior result.
4. Show a non-dismissible glassmorphic modal dialog containing the `AgentStepper`.
5. Step through the 5 AgentStep enum values for the animated stepper (800ms between non-final steps).
6. On the final step, call `ApiService.analyze(...)` — receive a record containing both `reply` and `plantingGrid`.
7. Store `reply` in `analysisResultProvider(projectId)` and `plantingGrid` in `latestPlantingGridProvider(projectId)` for immediate display.
8. On error, display a structured Markdown error message.
9. `isAnalyzing` reset to false in a `finally` block. Dialog auto-closes.

**`_sendChatMessage` behavior (chatbot):**
1. Read the text from `_chatController`, look up the project's `sessionId`.
2. Append the user message to `projectChatHistoryProvider(projectId)`.
3. Set `isChattingProvider(projectId)` to true (shows typing indicator).
4. Call `ApiService.chat(sessionId, message)` — hits the lightweight `/api/chat` endpoint.
5. Append the assistant reply to the chat thread.
6. On error, append an error message to the thread.
7. Reset `isChatting` in a `finally` block.

Enriched payload format (for analysis, unchanged):
```
System Context:
- Land Area: 5.00 Hectares
- Boundaries: [3.1234, 101.5678], [3.1240, 101.5690], ...

User Request: <original user message>
```


---


## Part 3: End-to-End Data Flow


### Analysis Flow

1. User opens the Flutter app; Firebase initialises before the first frame.
2. User lands on `/`.
3. User clicks "Get Started" or "Launch Dashboard" → `/dashboard`.
4. Dashboard subscribes to a Firestore real-time stream of projects ordered by createdAt desc.
5. User clicks "+ New Project," enters a name/description, clicks "Create & Analyze."
6. `ProjectService.addProject()` writes a new Firestore doc with UUIDs for id and sessionId. Router navigates to `/project/:id`.
7. On the project page, the Firestore stream provides the project (including any persisted `reportMarkdown`, `boundaryPoints`, and `plantingGrid`). If they exist, the markdown renders immediately in the Report tab and the planting grid circles appear on the map.
8. User either:
   - Uses the search bar to pan to a region (place name or coords — geocoded via the backend proxy), OR
   - Zooms in and taps the map to draw a boundary polygon. Each tap updates `aoiPointsProvider(projectId)`. The polygon area is computed and stored in `landAreaProvider(projectId)`.
9. User types "Analyze this land for agroforestry" and clicks "Analyze" in the Report tab.
10. Frontend validates boundary data. If missing, shows a SnackBar and blocks the request.
11. Frontend prepends the System Context header to the message.
12. Frontend opens a glassmorphic modal and animates through the 5 pipeline steps.
13. On the final step, it POSTs to `http://localhost:8000/api/analyze` with project id, sessionId, enriched message, and boundary points.
14. FastAPI passes the message to the `adk_app` → SequentialAgent.
15. Stage 1 — Land Profiler reads System Context → `fetch_land_data(lat, lng)` (GEE) → Land Profile Summary.
16. Stage 2 — Agronomist classifies the elevation band → `search_local_agriculture` (×2) → timber + intercrop recommendation.
17. Stage 3 (parallel):
    - Economist calculates financial projections.
    - Plotter calls `calculate_planting_grid(boundary_points, spacing=2.0)` → gets exact counts and lat/lng for every plant.
18. Stage 4 — Documentarian reads all prior outputs from shared session state → writes the full Markdown business plan.
19. Backend captures `calculate_planting_grid` tool output separately.
20. Backend writes `reportMarkdown`, `boundaryPoints`, and `plantingGrid` to `projects/{project_id}` in Firestore.
21. Backend returns `{reply, plantingGrid}` JSON.
22. Flutter stores the reply in `analysisResultProvider(projectId)` and the grid in `latestPlantingGridProvider(projectId)`.
23. Modal auto-closes. Markdown widget renders the report in the Report tab; map renders green + amber circles in a checkerboard pattern; legend shows counts.
24. Because Firestore was updated, the StreamProvider emits the new project data — navigating away and back still shows the same report and grid.
25. Follow-up messages in the same project reuse the same sessionId, preserving backend conversation context.

### Chatbot Flow

1. After an analysis has completed (or at any time), the user switches to the "Chatbot" tab.
2. User types a follow-up question (e.g. "What was the primary timber?") and clicks "Send".
3. Frontend appends the user message to `projectChatHistoryProvider(projectId)` and sets `isChattingProvider(projectId)` to true.
4. Frontend POSTs to `http://localhost:8000/api/chat` with the project's sessionId and the message.
5. Backend routes the message to the `AgroMind_Chat_Agent` via the `chat_app` AdkApp.
6. The chat agent reads the Vertex AI session history (which includes all prior analysis outputs) and generates a concise response.
7. Backend returns `{reply}` JSON within seconds (60s timeout).
8. Frontend appends the assistant reply to the per-project chat thread.
9. The chatbot UI auto-scrolls to the latest message. User and assistant messages render as styled bubbles.


---


## Part 4: Performance


Measured end-to-end latency for a typical `/api/analyze` request on a ~0.25 ha polygon:

| Stage | Duration |
|---|---|
| Startup → first agent call | ~25–30s |
| Land Profiler (Flash, GEE ~2s) | ~20s |
| Agronomist (Pro, RAG ~5s) | ~40s |
| Parallel(Economist \|\| Plotter) | ~50s (longest of the two) |
| Documentarian (Flash) | ~30s |
| **Total** | **~150–165s (~2.5–2.8 min)** |

Measured end-to-end latency for a typical `/api/chat` request:

| Stage | Duration |
|---|---|
| Chat Agent (Flash, no tools) | ~3–5s |

Measured improvements from the session's optimizations:

| Change | Impact |
|---|---|
| Baseline (all-Pro LlmAgent orchestrator, tool-call Plotter) | 10+ min, frequent timeouts |
| Switched sub-agents to Flash, tightened Agronomist prompt | ~5.5 min, full pipeline completes |
| Replaced LlmAgent + AgentTool with SequentialAgent | ~4.2 min (eliminated per-step orchestrator wrapping tax) |
| Parallelized Economist + Plotter via nested ParallelAgent | ~2.6 min |
| Replaced LLM Plotter math with shapely + pyproj tool | Plotter stage reliability improved; numbers now verifiable; visualizable |
| Added lightweight chat agent for follow-ups | Follow-up questions answered in ~3–5s instead of re-running the full ~2.6 min pipeline |


---


## Part 5: How to Run


### Backend

1. Navigate to the backend directory.
2. Activate the Python virtual environment: `.\venv\Scripts\Activate.ps1` (PowerShell) or `venv\Scripts\activate` (CMD).
3. Install dependencies: `pip install -r requirements.txt` (includes earthengine-api, google-cloud-discoveryengine, google-cloud-firestore, shapely, pyproj, httpx, python-dotenv).
4. Ensure Google Cloud credentials are configured for Vertex AI and Firestore access (`gcloud auth application-default login`).
5. Place the GEE service account key file as `gee-key.json` in the `backend/` root. Gitignored.
6. Copy `.env.example` to `.env` and fill in `GEOCODING_API_KEY` (Google Maps Geocoding API key for the server-side proxy).
7. Run: `uvicorn main:app --port 8000` (recommended — skip `--reload` for production / demo runs to avoid module-reload edge cases).
8. API available at http://localhost:8000 with `/api/chat`, `/api/geocode`, and `/api/analyze`.
9. On startup, look for `[OK] Google Earth Engine initialized successfully.`.
10. Firestore client connects to project `aura-487117` via Application Default Credentials.

**Important:** Always run via the virtual environment. If running from a fresh terminal without activating venv, use: `& .\venv\Scripts\python.exe -m uvicorn main:app --port 8000`


### Frontend

1. Navigate to the frontend directory.
2. Install dependencies: `flutter pub get`.
3. Copy `.env.example` to `.env` and fill in your Firebase API keys and Google Maps API key.
4. Run on web: `flutter run -d chrome --web-port=3000 --dart-define-from-file=.env`
5. Or run on Windows: `flutter run -d windows --dart-define-from-file=.env`
6. `--dart-define-from-file=.env` is **required** — it injects all Firebase and Maps API keys into `firebase_options.dart` via `String.fromEnvironment()` at compile time.
7. The map search bar's geocoding now calls the backend proxy (`/api/geocode`) — no frontend-side Geocoding API key is needed. The **Geocoding API** must be enabled on the GCP project associated with the backend's `GEOCODING_API_KEY`.
8. For the Google Map itself, the Maps **JavaScript API** must be enabled and the key placed in `web/index.html`.


---


## Part 6: Security & Environment Configuration


### Credential Management

All secrets are managed outside of source control:

- **Backend GEE key** (`gee-key.json`): gitignored in `backend/.gitignore` via `gee-key.json` and `*-key.json`.
- **Backend `.env`**: Contains `GEOCODING_API_KEY` for the server-side geocoding proxy. Gitignored.
- **Frontend `.env`**: Contains all Firebase API keys, the Google Maps API key (used for Maps JS only — geocoding now goes through the backend proxy), and shared Firebase config. Gitignored.
- **firebase_options.dart**: Uses `const String.fromEnvironment()` to read all config at compile time. Gitignored. Requires `--dart-define-from-file=.env`.


### .gitignore Structure

Three `.gitignore` files provide layered protection:

1. **Root `.gitignore`**: Catches `.env`, `.env.*` (with `!.env.example` exception), OS files, IDE dirs.
2. **`backend/.gitignore`**: Credential patterns, Python artifacts, venvs, testing, Docker overrides.
3. **`frontend/.gitignore`**: Env files, `lib/firebase_options.dart`, Flutter/Dart build artifacts, platform outputs, IDE files.


### .dockerignore

`backend/.dockerignore` excludes: `gee-key.json`, `*-key.json`, `*-credentials.json`, `.env`, `venv/`, `__pycache__/`, `.git/`, IDE dirs.


### .env.example Files

- **`backend/.env.example`**: `GEE_KEY_FILE`, `GEE_SERVICE_ACCOUNT`, `GOOGLE_CLOUD_PROJECT`. (Note: `GEOCODING_API_KEY` should be added here for completeness.)
- **`frontend/.env.example`**: `MAPS_API_KEY`, all `FIREBASE_*_API_KEY` values, shared Firebase config.


### Google Maps API Key (web/index.html)

Maps JavaScript API requires the key in the HTML `<script>` tag before Flutter bootstraps. `web/index.html` contains a `YOUR_RESTRICTED_MAPS_KEY` placeholder. For production, restrict by HTTP referrer and by API (enable Maps JavaScript API at minimum; Geocoding API is now handled server-side via the backend's `GEOCODING_API_KEY`).

---

## Setup & Installation Instructions

### Backend
1. **Navigate to the backend directory:** `cd backend`
2. **Create and activate a virtual environment:** `python -m venv venv` and `.\venv\Scripts\Activate.ps1` (Windows) or `source venv/bin/activate` (Mac/Linux)
3. **Install dependencies:** `pip install -r requirements.txt`
4. **Set up credentials:** Add your `.env` and `gee-key.json` as described in the architecture document.
5. **Run the FastAPI server:** `uvicorn main:app --port 8000`

### Frontend
1. **Navigate to the frontend directory:** `cd frontend`
2. **Install dependencies:** `flutter pub get`
3. **Set up credentials:** Create a `.env` file from the example and provide your keys.
4. **Run the application:** `flutter run -d chrome --web-port=3000 --dart-define-from-file=.env`

---

## AI-Generated Code Disclosure
**Disclaimer:** AI coding assistants (including Gemini and Antigravity) were utilized during the development of this project to accelerate boilerplate generation, assist with syntax debugging, and provide structural recommendations. However, all core system architecture, geospatial logic, agent workflows, and system designs were explicitly engineered by our agile team.
