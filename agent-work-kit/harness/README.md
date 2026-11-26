# Local load/fault harness skeleton

This directory is a **skeleton**, not a ready-made benchmark. Copy the pattern and implement the small project-specific
pieces in this git-excluded workspace. Everything must run locally against mocks or throwaway containers; do not call
production/cloud control planes, do not mutate shared dev infrastructure, and never use container prune commands.

## Recommended components

1. **Mock upstream**
   - Implement a local mock of the upstream dependency whose latency and streaming behavior matters.
   - Make response size, chunk count, chunk interval, error rate, and hang behavior configurable through env vars.
   - Record upstream latency separately so gateway/proxy-added latency can be computed as `measured − mock`.

2. **TCP fault proxy**
   - Put a small TCP proxy between the service under test and dependencies such as the database or cache.
   - A mode file should select: `normal`, `latency:<seconds>`, `down` (refuse/close), or `hang` (accept but never answer).
   - Run one proxy per dependency and use task-prefixed ports/names when parallel tasks are active.

3. **Open-loop load generator**
   - Use open-loop arrival times (for example Poisson) rather than closed-loop “one worker waits then retries” load.
   - Include realistic mixes: short/long streaming responses, client cancellation, large bodies, hot and cold keys.
   - Emit CSV/JSONL per request: send time, outcome, status, time to first byte, total duration, bytes, error class.

4. **Sent-vs-recorded reconciliation**
   - Load generation alone is not proof. Count successful accepted requests and compare with the durable records written
     by the system over the **whole run**, including warm-up and delayed admission.
   - Reconcile by status/model/tenant where applicable. Investigate duplicates, missing rows, and out-of-order completion.

5. **Readiness and degradation probes**
   - Poll health/readiness throughout faults. A correct implementation should not make readiness depend on a dependency
     that is intentionally degraded if the design requires process-local readiness.
   - Capture latency percentiles separately for normal, latency, down, and hang windows.

6. **Cleanup**
   - Name containers/processes with the task id. Stop them by exact name or PID when done.
   - Remove throwaway containers with their anonymous volumes where appropriate, but never use broad prune commands.
   - Kill processes by PID file or exact PID; avoid broad pattern kills that can match the operator's own shell.

## Minimum evidence in a task REPORT

- before/after p50/p99 (and preferably mean/max) per scenario;
- sent, accepted, recorded, duplicate, and mismatch counts;
- readiness non-200 count and whether any were real traffic;
- exact commands, container names/ports, dataset size, seed, and commit;
- artifacts preserved under `${WORK_DIR}/<task>/` or a referenced git-excluded harness directory.
