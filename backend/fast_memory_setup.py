# fast_memory_setup.py
# One-time utility script to provision an empty Vertex AI Agent Engine resource
# that serves as the Memory Bank for AgroMind's long-term memory.
#
# Run this script ONCE to create the Agent Engine, then copy the printed ID
# into AGENT_ENGINE_ID in main.py. The engine does not need to be re-created
# between deployments — it persists in Vertex AI until manually deleted.
#
# Usage: python fast_memory_setup.py
# Requires: gcloud auth application-default login with aura-487117 project access

import vertexai

# 1. Initialize the modern client
# Connects to the Vertex AI project and region where the Agent Engine will live
client = vertexai.Client(
    project="aura-487117",
    location="us-central1"  # Agent Engine is hosted in us-central1
)

print("Provisioning empty Agent Engine for Memory Bank...")

# 2. Create the engine WITHOUT an agent configuration
# This bypasses the staging bucket upload entirely!
# An empty engine is all that is needed — AdkApp binds to it via
# GOOGLE_CLOUD_AGENT_ENGINE_ID at runtime to manage sessions and memory
agent_engine = client.agent_engines.create()

# 3. Print your ID
# Extract the numeric ID from the full resource name
# (e.g. "projects/123/locations/us-central1/reasoningEngines/456" → "456")
engine_id = agent_engine.name.split('/')[-1]
print(f"\n✅ SUCCESS! Your Agent Engine ID is: {engine_id}")