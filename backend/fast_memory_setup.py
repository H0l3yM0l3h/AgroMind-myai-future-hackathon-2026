import vertexai

# 1. Initialize the modern client
client = vertexai.Client(
    project="aura-487117", 
    location="us-central1"
)

print("Provisioning empty Agent Engine for Memory Bank...")

# 2. Create the engine WITHOUT an agent configuration
# This bypasses the staging bucket upload entirely!
agent_engine = client.agent_engines.create()

# 3. Print your ID
engine_id = agent_engine.name.split('/')[-1]
print(f"\n✅ SUCCESS! Your Agent Engine ID is: {engine_id}")