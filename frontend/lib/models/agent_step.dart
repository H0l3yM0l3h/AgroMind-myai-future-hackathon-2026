/// Enum representing the 5 sub-agent steps in the AgroMind pipeline.
enum AgentStep {
  landProfiler('Land Profiler', 'Analyzing soil & climate data'),
  agronomist('Agronomist', 'Finding compatible crops'),
  economist('Economist', 'Calculating ROI & financials'),
  plotter('Plotter', 'Generating planting grid'),
  documentarian('Documentarian', 'Compiling business plan');

  final String label;
  final String subtitle;

  const AgentStep(this.label, this.subtitle);
}
