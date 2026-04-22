# Explanation Layer for O-RAN Anomaly Analysis

## Overview

This block defines how anomaly explanations follow root cause analysis in the AURORA workflow.
After an anomaly is detected and its likely root cause is computed, the explanation layer turns the technical signals into human-readable insights and recommended next actions.

## Purpose

- Translate RCA output into concise, actionable explanations for operators.
- Expose the most important evidence behind a detected anomaly.
- Combine root cause signals with context such as affected nodes, impacted services, and confidence levels.
- Help operations teams understand what changed, why it matters, and where to look next.

## Inputs

The explanation layer receives:
- anomaly alert metadata from edge detection sidecars
- candidate root causes from the central RCA service
- causal graph features, event timestamps, and supporting metrics
- service and topology context from CU/DU/gNB and core components

## Expected Output

An explanation should include:
- a short summary of the anomaly and the most likely cause
- the affected O-RAN component(s) and deployment domain(s)
- the key metrics or events that drove the diagnosis
- confidence or score information
- recommended investigation steps or mitigation hints

## Design Considerations

- Keep explanations concise and avoid overwhelming operators with raw telemetry.
- Preserve traceability back to the RCA model so analysts can validate the conclusion.
- Support both automated output for dashboards and human-readable text for incident reports.
- Allow the explanation layer to present multiple hypotheses when RCA confidence is low.

## Workflow

1. Edge sidecar detects an anomaly and emits an alert.
2. Central RCA consumes alert context and performs causal analysis.
3. RCA returns ranked root causes, supporting evidence, and confidence scores.
4. The explanation layer generates the final anomaly explanation.

## Next Steps

1. Define a standard explanation schema for anomaly summaries.
2. Map RCA outputs from `causalnex` or other engines into that schema.
3. Prototype example explanations for common O-RAN failure modes.
4. Validate explanation usefulness with operators or domain experts.

## Notes

The explanation block is intended to close the loop from anomaly detection to human understanding. It is not a separate detection stage, but rather the interpretive layer that makes RCA results actionable.
