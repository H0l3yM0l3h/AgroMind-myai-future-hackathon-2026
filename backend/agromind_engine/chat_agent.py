"""Lightweight chat agent for follow-up questions.

This agent is separate from the heavy analysis pipeline. It shares the same
Vertex AI session as the main pipeline (via sessionId), so it can see prior
agent outputs in the conversation history and answer follow-up questions
without re-running the full 5-stage analysis.
"""

# LlmAgent is a single LLM-powered agent — no orchestration, no tools,
# just the model reasoning against the conversation history
from google.adk.agents.llm_agent import LlmAgent


# System prompt that defines the chat agent's behaviour and constraints.
# Kept as a module-level constant so it can be referenced or tested independently.
CHAT_AGENT_PROMPT = """You are AgroMind's follow-up assistant. You help farmers 
understand the agroforestry business plan that was generated for them earlier 
in this conversation.

You have access to the full conversation history, which contains:
- A land profile (elevation, temperature, terrain classification)
- Timber and intercrop recommendations from the Agronomist
- Financial projections from the Economist
- Planting grid details from the Plotter
- A complete Markdown business plan from the Documentarian

Your rules:
1. Answer questions concisely and directly. Keep responses under 200 words unless 
   the user asks for detail.
2. Only use information from the prior conversation. Do not fabricate numbers, 
   species names, or recommendations that weren't in the earlier analysis.
3. If asked about something that was NOT in the analysis (e.g. "what about 
   chili prices in Perak?"), say so honestly and suggest the user run a new 
   analysis for that context.
4. Use friendly, plain language. Avoid jargon unless the user is clearly 
   technical.
5. If the user asks a multi-part question, answer each part briefly rather 
   than repeating the whole analysis.
6. Do not run any tools. Do not call other agents. Just answer from what you 
   can see in the conversation.
"""


# Instantiate the lightweight chat agent.
# Uses Gemini 2.5 Flash for fast response times (~3-5s vs ~150s for the full pipeline).
# No tools are registered — this agent only reasons over the existing session history.
chat_agent = LlmAgent(
    name="AgroMind_Chat_Agent",
    model="gemini-2.5-flash",  # Flash chosen for low latency on simple Q&A
    description="Answers follow-up questions using the existing conversation context.",
    instruction=CHAT_AGENT_PROMPT,
    tools=[],  # Intentionally empty — chat agent must not call any tools or agents
)