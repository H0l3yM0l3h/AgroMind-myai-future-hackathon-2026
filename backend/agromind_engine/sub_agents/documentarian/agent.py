# LlmAgent is the base class for a single LLM-powered agent with tools
from google.adk.agents.llm_agent import LlmAgent

from . import prompt  # Documentarian system prompt defined in prompt.py

# Instantiate the Documentarian agent.
# This is Stage 4 (final stage) of the pipeline — it runs after the Economist
# and Plotter have both completed. It reads all prior agent outputs from shared
# session state and formats them into a professional Markdown business plan.
# Pure text generation — no tools or external API calls needed.
documentarian_agent = LlmAgent(
    name="Documentarian_Agent",
    model="gemini-2.5-flash",  # Flash used for speed; output is formatting, not reasoning
    description="Generates formal Agroforestry Business Plan documents.",
    instruction=prompt.DOCUMENTARIAN_PROMPT,
    tools=[],  # No tools — reads from session state and writes the final report
)