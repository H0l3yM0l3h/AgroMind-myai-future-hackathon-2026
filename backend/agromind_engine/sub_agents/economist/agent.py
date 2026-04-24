# LlmAgent is the base class for a single LLM-powered agent with tools
from google.adk.agents.llm_agent import LlmAgent

from . import prompt  # Economist system prompt defined in prompt.py

# Instantiate the Agro-Economist agent.
# This is Stage 3a of the pipeline — runs concurrently with the Plotter inside
# the ParallelAgent. It reads the Agronomist's timber + intercrop recommendations
# from shared session state and produces financial projections purely through
# LLM reasoning (no external tools needed).
economist_agent = LlmAgent(
    name="Agro_Economic_Agent",
    model="gemini-2.5-flash",  # Flash used for speed; financial reasoning needs no Pro
    description="Calculates 15-year ROI and short-term profit margins.",
    instruction=prompt.ECONOMIST_PROMPT,
    tools=[],  # No tools — all calculations are done via LLM reasoning
)