# Anomaly Detection for O-RAN

## Overview

This block describes how anomaly detection will be integrated with the AURORA O-RAN testbed.
The goal is to detect unusual behavior in real-time from O-RAN telemetry and packet data collected by AURORA, while keeping processing close to the radio nodes.

## Deployment Concept

- Anomaly detection will run in a sidecar container attached to the CU, DU, or monolithic gNB node.
- CU and DU can each host their own sidecar because they may run in separate pods, hosts, or deployment domains.
- Sidecar deployment keeps data collection and inference local to the radio node, reducing network hops and preserving low-latency monitoring.
- Each sidecar will observe the local telemetry streams and probe data that AURORA collects for its attached RAN component.

## Architecture Diagram

The anomaly detection sidecars are positioned at the edge, co-located with the CU, DU, or monolithic gNB. CU and DU may each have separate sidecars if they are deployed in different pods or hosts. Each sidecar monitors local RAN components and forwards alerts to central services when needed.

```
+-----------------------------+          +---------------------------+
|   O-RAN Radio Domain        |          |      Central Services     |
|                             |          |  (SMO, RCA, analytics)    |
|  +---------+   +---------+  |   alert  |                           |
|  |  O-RU   |---|  O-DU   |--|--------->|    Central RCA / Causal   |
|  +---------+   +---------+  |          |      Analysis Service     |
|           +--------------+  |          +---------------------------+
|           | Sidecar (DU) |  |
|           |  local edge  |  |
|           +--------------+  |
|                    |        |
|                    |        |
|                    |        |
|                    |        |
|                    |        |
|                +---------+  |
|                |  O-CU   |  |
|                +---------+  |
|           +--------------+  |
|           | Sidecar (CU) |  |
|           |  local edge  |  |
|           +--------------+  |
+-----------------------------+
```

- The CU and DU sidecars are separate edge components and may run in different pods or hosts.
- The DU sidecar observes O-DU and O-RU-related telemetry while the CU sidecar observes O-CU metrics.
- Anomaly detection stays near the workload to preserve low latency and reduce transport of raw data.
- Central services may receive alerts, summaries, or selected context for follow-up analysis.

## Data Source

- Use AURORA-collected data from CU/DU/gNB: performance counters, protocol metrics, interface statistics, fronthaul/midhaul quality, and timing metrics.
- Capture both control-plane and user-plane relevant features where available.
- The initial focus is on data that is already available from the AURORA instrumentation pipeline to minimize integration overhead.
- See the project root `README.md` for details on AURORA data collection, thread metrics, and shared-memory ingestion patterns.

## Data Collection Challenge

- A key design decision is whether to synchronize infrastructure/thread-level metrics with application-level RAN metrics for a single unified inference stream, or to keep them separate and perform inference independently.
- Currently AURORA collects these data types separately, so the anomaly detection design must decide whether to align them in time or to use two coordinated detection pipelines.
- This challenge affects feature engineering, model input consistency, and the complexity of the online learning pipeline.

## Learning Strategy

- The model will be online learning enabled, allowing the detector to adapt continuously as network conditions change.
- Use a pretrained model as the starting point, then refine and update it using live O-RAN data from the sidecar.
- The online learning loop should support incremental updates without interrupting the CU/DU service.

## Research Areas

- Model architecture research is required before committing to a final design.
- Candidate architectures include:
  - time-series anomaly detectors (LSTM, GRU, transformer-based sequences)
  - streaming autoencoders / variational autoencoders
  - graph-based models if topology-aware features are important
  - hybrid models that combine rule-based thresholds with learned anomaly scores
- Evaluate the trade-offs between model complexity, inference latency, and adaptability for edge-side deployment.

## Design Requirements

- Low-latency inference suitable for CU/DU-side execution
- Ability to start from a pretrained model and adapt online in production
- Strong support for concept drift and changing traffic conditions
- Explainability for anomaly alerts where practical
- Lightweight resource usage so the sidecar does not compete with RAN real-time workloads

## Next Steps

1. Research suitable anomaly detection model families for O-RAN telemetry.
2. Define the exact feature set AURORA can provide from the CU/DU/gNB side.
3. Prototype a sidecar container architecture for data ingestion, inference, and online updates.
4. Select a pretrained model baseline and validate it on AURORA-collected data.
5. Implement a safe update mechanism so the sidecar can refine the model continuously in the field.

## Notes

This block is intentionally architecture-focused: the first phase is research and prototyping, not production deployment. The emphasis is on a practical online learning design that starts from a pretrained model and evolves with live O-RAN traffic.
