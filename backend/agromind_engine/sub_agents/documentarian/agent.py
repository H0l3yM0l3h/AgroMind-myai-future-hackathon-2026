from google.adk.agents.llm_agent import LlmAgent

from . import prompt

documentarian_agent = LlmAgent(
    name="Documentarian_Agent",
    model="gemini-2.5-flash",
    description="Generates formal Agroforestry Business Plan documents.",
    instruction=prompt.DOCUMENTARIAN_PROMPT,
    tools=[],
)
