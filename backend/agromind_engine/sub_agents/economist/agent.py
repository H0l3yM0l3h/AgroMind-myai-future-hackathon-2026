from google.adk.agents.llm_agent import LlmAgent

from . import prompt

economist_agent = LlmAgent(
    name="Agro_Economic_Agent",
    model="gemini-2.5-flash",
    description="Calculates 15-year ROI and short-term profit margins.",
    instruction=prompt.ECONOMIST_PROMPT,
    tools=[],
)
