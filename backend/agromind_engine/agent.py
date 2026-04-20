import logging
from google.adk.agents.sequential_agent import SequentialAgent
from google.adk.agents.parallel_agent import ParallelAgent

from .sub_agents import (
    land_profiler_agent,
    agronomist_agent,
    economist_agent,
    plotter_agent,
    documentarian_agent,
)


async def _save_session_to_memory(callback_context):
    try:
        await callback_context.add_session_to_memory()
        logging.info("Session saved to Memory Bank.")
    except ValueError:
        pass
    except Exception as e:
        logging.warning(f"Memory save failed (non-fatal): {e}")
    return None


economist_and_plotter_parallel = ParallelAgent(
    name="Economist_And_Plotter_Parallel",
    description=(
        "Runs financial analysis and planting grid calculations concurrently "
        "since they are independent."
    ),
    sub_agents=[
        economist_agent,
        plotter_agent,
    ],
)

orchestrator_agent = SequentialAgent(
    name="Orchestrator_Agent",
    description=(
        "Runs the agroforestry pipeline: profile land, recommend crops, "
        "then run economics and plotting in parallel, and finally compile "
        "the business plan."
    ),
    sub_agents=[
        land_profiler_agent,
        agronomist_agent,
        economist_and_plotter_parallel,
        documentarian_agent,
    ],
    after_agent_callback=_save_session_to_memory,
)