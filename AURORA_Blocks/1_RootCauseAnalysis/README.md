# Root Cause Analysis for O-RAN Anomalies

## Overview

This block describes the planned root cause analysis (RCA) flow for anomalies detected by the AURORA anomaly detection sidecar.
While anomaly detection is designed to run at the edge, root cause analysis is currently targeted for a more central location because it requires heavier compute and broader context.

## Current Architecture

- Anomaly detection runs in a sidecar on CU/DU/gNB nodes using local telemetry and online learning.
- When an anomaly is detected, the alert and selected context are forwarded to a central RCA service.
- The central RCA service aggregates data from one or more edge nodes, correlates cross-node behavior, and performs causal inference to identify likely failure modes.

## Architecture Diagram

The architecture separates the lightweight edge detection layer from the compute-rich central RCA layer.

```
                +-----------------------------+
                |        Central RCA / SMO     |
                |  - causalnex analysis        |
                |  - cross-node correlation    |
                |  - richer history + context  |
                +-------------+---------------+
                              |
                              | alert + selected context
                              |
+-------------+    +---------v--------+   +----------------+
|    O-RAN    |    |  CU / DU / gNB   |   |    Core / CN   |
|    Radio    |    |  Edge node       |   |    Network     |
|   (O-DU,    |    |  - anomaly sidecar|  |  - network state|
|    O-CU,    |    |  - local telemetry|  |  - broader KPIs |
|    O-RU)    |    +------------------+   +----------------+
+-------------+
```

- Edge sidecar attaches to CU/DU/gNB and performs anomaly detection close to the RAN workload.
- Central RCA sits outside the CU/DU/gNB runtime, typically in a regional or cloud-hosted service that can access core, SMO, and aggregated edge feeds.
- The core (CN) is a supporting context source rather than the direct location of RCA.

## Why Central RCA

- Root cause reasoning often needs richer context than a single edge node can provide.
- More compute-intensive models and graph-based analysis are easier to run in a central location.
- The central service can incorporate longer history, multiple node correlations, and external network state while preserving lightweight edge inference.

## Candidate Method

- The primary method under consideration is `causalnex` for causal graph modeling and explanation.
- `causalnex` supports:
  - constructing causal Bayesian networks from observed metrics,
  - reasoning over interventions and counterfactuals,
  - generating human-readable explanations for causal links.

## RCA Workflow

1. Anomaly alert is emitted by the edge sidecar.
2. Relevant metrics, event timestamps, and feature context are shipped to central RCA.
3. Central RCA chooses a causal model structure and ingests the assembled data.
4. Causal analysis identifies the most plausible root causes and ranks them.
5. RCA outputs a diagnosis summary, confidence indicators, and suggested focus areas for investigation.

## Design Considerations

- Keep the central RCA pipeline decoupled from the edge anomaly detector.
- Preserve the edge as a source of timely detection while the central service provides richer reasoning.
- Limit data shipped from edge to central service to avoid excessive network load.
- Ensure the central service can fall back to simple correlated alerts if causal graph learning is not yet mature.

## Next Steps

1. Define the edge-to-central alert payload and context schema.
2. Prototype a central RCA service using `causalnex` on sample AURORA anomaly scenarios.
3. Evaluate how causal graph outputs map to real O-RAN failure modes.
4. Add fallback/score-based RCA paths while causal models are being validated.
5. Document clear boundaries between edge anomaly detection and central root cause analysis.

## Notes

This block is intentionally scoped to a central, compute-rich RCA stage. The first phase focuses on validating causal inference methods before moving any part of RCA closer to the edge.
