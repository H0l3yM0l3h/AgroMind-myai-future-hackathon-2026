import logging

# SequentialAgent runs sub-agents one after another in a fixed order
from google.adk.agents.sequential_agent import SequentialAgent

# ParallelAgent runs sub-agents concurrently at the same time
from google.adk.agents.parallel_agent import ParallelAgent

# Import all 5 pipeline sub-agents from the sub_agents package
from .sub_agents import (
    land_profiler_agent,    # Stage 1: Fetches GEE land/climate data
    agronomist_agent,       # Stage 2: Recommends timber + intercrop via RAG
    economist_agent,        # Stage 3a: Calculates financial projections
    plotter_agent,          # Stage 3b: Computes exact planting grid positions
    documentarian_agent,    # Stage 4: Compiles the final Markdown business plan
)


async def _save_session_to_memory(callback_context):
    # After the full pipeline completes, save the session to the Vertex AI
    # Memory Bank so future sessions can recall past analyses
    try:
        await callback_context.add_session_to_memory()
        logging.info("Session saved to Memory Bank.")
    except ValueError:
        # ValueError is raised when memory saving is not supported in the
        # current environment (e.g. local dev without VertexAiMemoryBankService)
        pass
    except Exception as e:
        # Any other memory save failure is non-fatal — log it and continue
        # so the pipeline result is still returned to the user
        logging.warning(f"Memory save failed (non-fatal): {e}")
    return None


# Stage 3: Economist and Plotter run concurrently inside a ParallelAgent
# because they are independent — both only need the Agronomist's output
# Running them in parallel cuts total pipeline time by ~50s
economist_and_plotter_parallel = ParallelAgent(
    name="Economist_And_Plotter_Parallel",
    description=(
        "Runs financial analysis and planting grid calculations concurrently "
        "since they are independent."
    ),
    sub_agents=[
        economist_agent,    # Calculates costs, revenue, and 15-year ROI
        plotter_agent,      # Computes GPS coordinates for every plant position
    ],
)

# Root orchestrator: a SequentialAgent that drives the full 4-stage pipeline
# Stage 1 → Stage 2 → Stage 3 (parallel) → Stage 4
# Using SequentialAgent (not LlmAgent) ensures deterministic execution —
# the LLM cannot skip or reorder stages
orchestrator_agent = SequentialAgent(
    name="Orchestrator_Agent",
    description=(
        "Runs the agroforestry pipeline: profile land, recommend crops, "
        "then run economics and plotting in parallel, and finally compile "
        "the business plan."
    ),
    sub_agents=[
        land_profiler_agent,                # Stage 1
        agronomist_agent,                   # Stage 2
        economist_and_plotter_parallel,     # Stage 3 (parallel)
        documentarian_agent,                # Stage 4
    ],
    # Registered on the root agent only — fires once after the entire pipeline
    # completes, not after each individual sub-agent
    after_agent_callback=_save_session_to_memory,
)