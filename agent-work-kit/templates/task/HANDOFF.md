# HANDOFF — <task>

## Branch and dependencies

- Branch: `<branch>` @ `<commit>`; base: `<base>`.
- Depends on / overlaps with: <other task branches or "none">.
- Services to redeploy with `--build`: <service list or "none">.
- Jobs/migrations to run: <migration job or "none">.

## Config/env changes

List every key as `service: KEY=value (default, why)`:

- `<service>: KEY=value (default <value>; why <reason>)`
- `<service>: KEY=value (default <value>; why <reason>)`

Layer to apply each key through: <deploy schema / `.local` values file / secret store>. Remember that `.local` values
normally take precedence over rendered deploy config. Agents must not edit protected values files directly.

## Migrations

- Order: `<migration>` after `<current head>`.
- Lock behavior: <lock_timeout, retries, concurrency, hot-table impact>.
- Numbering/re-chain note: <reserved range or "whoever merges second renumbers/re-chains">.
- Init/schema sync: <files updated or not applicable>.

## Dev verification recipe

1. <step>
2. <step>
3. <expected observation, metrics/log/query where useful>

## Rollback

1. <image/config rollback step>
2. <migration downgrade or forward-fix note>
3. <data/backfill reversal if applicable>

## Notes for deployer

- <feature flags, rollout order, operational warnings>
