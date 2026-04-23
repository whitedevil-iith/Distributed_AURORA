# Motivation for Distributed AURORA

## Why this project exists

AURORA is focused on RAN metrics collection, but the distributed nature of O-RAN deployments exposes a key research opportunity: detection and resolution should be split between edge nodes and a central reasoning layer.

The motivation for this distributed approach is twofold:

1. **Edge-side anomaly detection** must stay lightweight and local to CU/DU/gNB to preserve low latency and minimize transport of raw telemetry.
2. **Central analysis, RCA, and explanation** can use richer context, more compute, and cross-node correlation without burdening the critical RAN processing path.

This README explains how we will prove that distributed anomaly management is the right design choice.

## Core hypothesis

Traffic and anomaly behavior are not uniform across deployment environments. In particular, rural and urban RAN traffic patterns differ because of:

- population density,
- building density and propagation environment,
- mobility patterns shaped by roads and transport infrastructure,
- UE distribution and handover dynamics.

These differences motivate a distributed architecture because:

- rural and urban edge nodes will have different telemetry profiles
- we could also explore how different configuration of e2 nodes would lead to different telemetry profiles.
- a single centralized detector cannot optimally serve both edge domains,
- localized CU/DU models are better suited to their deployment-specific conditions,
- central RCA can still unify the results and explain cross-domain failures.

## How we will demonstrate the motivation

### 1. Create rural and urban traffic scenarios in ns-3

- Use ns-3 as the core simulation framework.
- Build two distinct deployment scenarios: one rural, one urban.
- Keep the core RAN stack and AURORA telemetry collection consistent across both, so the difference is in environment and UE behavior.
- Use ns-3's building, propagation, and mobility modules to encode rural/urban differences while keeping the radio protocol and AURORA collection hooks identical.
- Run matched experiments with the same traffic mix and application load but different spatial and mobility characteristics.
- Compare the resulting telemetry distributions to isolate environment-driven behavior differences.

### 2. Model population density explicitly

- Obtain population density data or synthetic distributions for rural and urban areas.
- Use the density model to place UEs in each scenario.
- Validate that urban scenarios have higher UE density, tighter clustering, and more frequent mobility handovers than rural scenarios.

### 3. Add building-aware propagation using OSM data

- Use OpenStreetMap building footprints and environment data to shape the radio propagation model.
- Simulate how urban building density affects signal quality, cell shapes, and handover behavior.
- Compare to rural environments with sparse buildings and simpler line-of-sight conditions.

### 4. Simulate realistic mobility with OSM + SUMO

- Import road networks from OSM into SUMO.
- Generate realistic UE movement along actual streets.
- Use SUMO traces in ns-3 to drive UE mobility, reflecting urban congestion and rural transit patterns.

### 5. Compare telemetry between rural and urban

Collect the same AURORA metrics in both scenarios and compare:

- traffic flow distributions,
- HARQ/CRC patterns,
- FAPI MCS/PRB allocations,
- per-UE MAC/RLC statistics,
- thread-level and application-level metrics.

The goal is to show that the telemetry signature of anomalies and normal operation is meaningfully different between rural and urban deployments.

## What this proves

If rural and urban deployments exhibit distinct metric signatures, then:

- a separate CU/DU anomaly model for each edge domain is justified,
- edge-side detection can be tuned per deployment type,
- central RCA and explanation become critical for comparing and validating edge signals across diverse domains.

## How this ties to the distributed architecture

- **Edge detection**: CU/DU sidecars ingest AURORA telemetry and run online learning models tuned to local conditions.
- **Central RCA**: a synchronized reporting framework collects alerts and aligned data windows from distributed edge agents.
- **Explanation and resolution**: a higher-level reasoning stack turns RCA insights into operator-facing explanations and safe remediation plans.

## Next steps for motivation work

1. Formalize the rural vs urban ns-3 experiment design.
2. Collect baseline traces for each scenario.
3. Build the OSM/SUMO integration pipeline.
4. Run comparison experiments and document the key metric differences.
5. Use the results to justify the distributed CU/DU edge detection and centralized reasoning architecture.

## Notes

This document is intentionally focused on the motivation methodology, not the implementation details. The goal is to prove that a distributed design is needed before committing to the final anomaly detection and RCA architecture.
