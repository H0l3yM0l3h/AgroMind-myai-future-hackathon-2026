/// Enum representing the 5 sub-agent steps in the AgroMind pipeline.
// Used by the AgentStepper widget to show which pipeline stage is currently
// active, and by _sendMessage in project_screen.dart to animate through
// each step as the analysis progresses.
// The order of values matches the actual pipeline execution order:
// Stage 1 → Stage 2 → Stage 3a/3b (parallel) → Stage 4
enum AgentStep {
  // Stage 1: Fetches GEE elevation and temperature data for the farm location
  landProfiler('Land Profiler', 'Analyzing soil & climate data'),

  // Stage 2: Queries the MTC Timber Knowledge Base via RAG to recommend species
  agronomist('Agronomist', 'Finding compatible crops'),

  // Stage 3a: Calculates setup costs, short-term revenue, and 15-year ROI
  economist('Economist', 'Calculating ROI & financials'),

  // Stage 3b: Computes exact GPS coordinates for every plant in a checkerboard grid
  plotter('Plotter', 'Generating planting grid'),

  // Stage 4: Reads all prior agent outputs and formats the final Markdown business plan
  documentarian('Documentarian', 'Compiling business plan');

  // Display label shown as the step title in the AgentStepper widget
  final String label;

  // Short description shown as the step subtitle below the label
  final String subtitle;

  // Each enum value carries its own label and subtitle for the stepper UI
  const AgentStep(this.label, this.subtitle);
}