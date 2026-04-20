from google.adk.agents.llm_agent import LlmAgent
from google.cloud import discoveryengine

from . import prompt

PROJECT_ID = "aura-487117"
LOCATION = "global"
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
        client = discoveryengine.SearchServiceClient()

        serving_config = (
            f"projects/{PROJECT_ID}"
            f"/locations/{LOCATION}"
            f"/collections/default_collection"
            f"/dataStores/{DATA_STORE_ID}"
            f"/servingConfigs/default_search"
        )

        request = discoveryengine.SearchRequest(
            serving_config=serving_config,
            query=query,
            page_size=3,
            content_search_spec=discoveryengine.SearchRequest.ContentSearchSpec(
                snippet_spec=discoveryengine.SearchRequest.ContentSearchSpec.SnippetSpec(
                    return_snippet=True,
                ),
            ),
        )

        response = client.search(request)

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

        if not snippets:
            combined = "No relevant results found in the MTC Timber Knowledge Base for this query."
            print(f"[RAG] search DONE in {time.time()-t0:.1f}s, {len(combined)} chars returned", flush=True)
            return combined

        combined = "\n\n".join(snippets)
        print(f"[RAG] search DONE in {time.time()-t0:.1f}s, {len(combined)} chars returned", flush=True)
        return combined

    except Exception as e:
        print(f"[RAG] search FAILED in {time.time()-t0:.1f}s: {e}", flush=True)
        return f"Error: {e}"


agronomist_agent = LlmAgent(
    name="Symbiotic_Agronomist_Agent",
    model="gemini-2.5-flash",
    description="Finds compatible timber and short-term intercrops based on soil profiles.",
    instruction=prompt.AGRONOMIST_PROMPT,
    tools=[search_local_agriculture],
)
