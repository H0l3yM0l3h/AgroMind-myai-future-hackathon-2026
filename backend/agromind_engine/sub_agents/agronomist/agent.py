# LlmAgent is the base class for a single LLM-powered agent with tools
from google.adk.agents.llm_agent import LlmAgent

# Discovery Engine client for querying the Vertex AI Search data store
from google.cloud import discoveryengine

from . import prompt  # Agronomist system prompt defined in prompt.py

# GCP project and Vertex AI Search configuration for the MTC Timber Knowledge Base
# DATA_STORE_ID points to the pre-ingested Malaysian timber species dataset
PROJECT_ID = "aura-487117"
LOCATION = "global"  # Vertex AI Search data stores are always in the global location
DATA_STORE_ID = "agromind-sovereign-data_1776315921942"


def search_local_agriculture(query: str) -> str:
    """Searches the MTC Timber Knowledge Base for information on Malaysian
    commercial timber species, their physical properties, climate suitability,
    and agroforestry practices.

    Args:
        query: The search query string (e.g., "lowland tropical timber species
               suitable for 27°C average temperature").

    Returns:
        A formatted string containing relevant snippets from the knowledge base,
        or an error/no-results message.
    """
    import time
    t0 = time.time()
    print(f"[RAG] search({query!r}) START", flush=True)
    try:
        # Initialise the Vertex AI Search client for this request
        client = discoveryengine.SearchServiceClient()

        # Build the fully-qualified serving config path required by the API
        serving_config = (
            f"projects/{PROJECT_ID}"
            f"/locations/{LOCATION}"
            f"/collections/default_collection"
            f"/dataStores/{DATA_STORE_ID}"
            f"/servingConfigs/default_search"
        )

        # Configure the search request to return top 3 results with snippets
        # Snippets are short extracted passages — sufficient for RAG context
        request = discoveryengine.SearchRequest(
            serving_config=serving_config,
            query=query,
            page_size=3,  # Limit to top 3 results to keep context concise
            content_search_spec=discoveryengine.SearchRequest.ContentSearchSpec(
                snippet_spec=discoveryengine.SearchRequest.ContentSearchSpec.SnippetSpec(
                    return_snippet=True,
                ),
            ),
        )

        response = client.search(request)

        # Extract snippet text from each search result
        snippets = []
        for i, result in enumerate(response.results, start=1):
            snippet_text = ""
            # Extract snippet from the search result document
            if result.document and result.document.derived_struct_data:
                derived = result.document.derived_struct_data
                # Snippets are typically nested under 'snippets' in derived_struct_data
                if "snippets" in derived:
                    for snippet in derived["snippets"]:
                        if "snippet" in snippet:
                            snippet_text += snippet["snippet"]
            if snippet_text:
                snippets.append(f"[Result {i}]: {snippet_text.strip()}")

        # Return a clear no-results message so the LLM knows to rely on
        # its own knowledge rather than waiting for more RAG results
        if not snippets:
            combined = "No relevant results found in the MTC Timber Knowledge Base for this query."
            print(f"[RAG] search DONE in {time.time()-t0:.1f}s, {len(combined)} chars returned", flush=True)
            return combined

        # Join all snippets into a single string for the LLM to reason over
        combined = "\n\n".join(snippets)
        print(f"[RAG] search DONE in {time.time()-t0:.1f}s, {len(combined)} chars returned", flush=True)
        return combined

    except Exception as e:
        print(f"[RAG] search FAILED in {time.time()-t0:.1f}s: {e}", flush=True)
        # Return error as string so the LLM can handle it gracefully
        # rather than crashing the pipeline
        return f"Error: {e}"


# Instantiate the Agronomist agent.
# This is Stage 2 of the pipeline — it receives the Land Profile Summary from
# Stage 1 and calls search_local_agriculture EXACTLY TWICE (per prompt rules)
# to find matching timber species and intercrop pairings from the knowledge base.
# Uses Gemini 2.5 Flash for RAG-based reasoning over the retrieved snippets.
agronomist_agent = LlmAgent(
    name="Symbiotic_Agronomist_Agent",
    model="gemini-2.5-flash",  # Flash is sufficient for RAG-grounded recommendations
    description="Finds compatible timber and short-term intercrops based on soil profiles.",
    instruction=prompt.AGRONOMIST_PROMPT,
    tools=[search_local_agriculture],  # RAG tool — queries the MTC Timber Knowledge Base
)