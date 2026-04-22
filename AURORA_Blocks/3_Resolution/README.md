# Resolution Layer for O-RAN Anomaly Hypothesis and Action

## Overview

This block defines a multi-agent resolution system that operates after explanation and RCA have produced a candidate anomaly diagnosis.
It combines explanation outputs, raw telemetry, and auxiliary tools to form hypotheses, reason through likely causes, validate them, and recommend or execute actions with the operator in the loop.

## Purpose

- Orchestrate a team of specialized agents to resolve detected anomalies.
- Use explanation and raw telemetry to generate hypotheses and reasoning traces.
- Validate candidate diagnoses before recommending or taking action.
- Keep the operator engaged for human approval and high-value decisions.

## Agent Roles

- Planner Agent
  - Generates hypotheses based on explanation outputs, telemetry, topology, and historical patterns.
  - Proposes investigative directions, affected components, and likely failure modes.

- Reasoning Agent
  - Evaluates hypotheses against causal evidence, telemetry streams, and RCA outputs.
  - Performs structured reasoning to prioritize the most plausible root causes.

- Validator Agent
  - Cross-checks proposed hypotheses against additional raw telemetry and configuration data.
  - Detects contradictions, missing evidence, and false positives.

- Executioner Agent
  - Translates approved hypotheses into concrete resolution steps or remediation suggestions.
  - Coordinates with operator approval before any active intervention.

## Workflow

1. Explanation layer produces a human-readable anomaly summary and candidate root causes.
2. Planner agent ingests the explanation, raw telemetry, and context to generate one or more hypotheses.
3. Reasoning agent ranks hypotheses and connects them with causal evidence.
4. Validator agent checks hypotheses against supplementary data, metrics, and policy rules.
5. Operator reviews the validated hypothesis and accepts, rejects, or refines it.
6. Executioner agent prepares remediation actions, runbooks, or automated tasks for operator confirmation.

## Data Inputs

- Explanation summaries and RCA candidate cause outputs.
- Raw telemetry streams from AURORA sidecars and central collectors.
- Topology and deployment context for CU, DU, gNB, and core components.
- Historical anomaly/failure records and policy constraints.

## Outputs

- Ranked hypotheses with confidence and validation status.
- Recommended next steps or mitigation actions.
- Operator decisions and approval logs.
- Optional automated execution plans for safe interventions.

## Design Considerations

- Operator must remain in the loop for any remediation that affects live RAN behavior.
- Hypothesis generation should stay grounded in actual telemetry and explanation evidence.
- Validation must guard against overconfident or unsupported conclusions.
- The resolution layer should support both advisory mode and controlled automation.

## Next Steps

1. Define the multi-agent interfaces and handoff points.
2. Specify the hypothesis schema and validation criteria.
3. Prototype the planner/reasoning/validator/executioner workflow on representative O-RAN scenarios.
4. Add operator approval gates and audit logging.
5. Evaluate the system with real anomaly cases to tune agent behavior.

## Notes

This block is meant to bridge explanation and actionable resolution through a multi-agent, operator-assisted process. It is not a standalone detection model; it is the decision layer that turns RCA insight into safe, validated action.
