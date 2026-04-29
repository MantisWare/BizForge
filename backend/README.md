# Canopy Backend

> Elixir/Phoenix API server powering the Canopy workspace protocol.

## Quick Start

```bash
mix setup          # Install deps, create DB, run migrations, seed data
mix phx.server     # Start the server on http://127.0.0.1:9089
```

Or from the project root:

```bash
just backend       # Start Phoenix backend only
just stop-backend  # Stop it
just logs backend  # Tail logs
```

## Configuration

Database credentials are in `config/dev.exs`. The default username is `symac` — update it to match your local PostgreSQL role if different.

## Key Modules

| Module | Purpose |
|--------|---------|
| `Canopy.Heartbeat` | 9-step agent execution cycle |
| `Canopy.BudgetEnforcer` | ETS-based budget enforcement |
| `Canopy.Governance.Gate` | Approval gate plug |
| `Canopy.Dispatch.Router` | Content-based adapter routing |
| `Canopy.Sessions.Compactor` | Session summarization & handoff |
| `Canopy.Workflows.Engine` | DAG workflow execution |

## Tests

```bash
mix test                           # Run all tests
mix test test/canopy/my_test.exs   # Run a specific test file
mix test --failed                  # Re-run failed tests
```

## Useful Aliases

```bash
mix setup         # deps.get + ecto.create + ecto.migrate + seeds
mix ecto.reset    # Drop + setup (fresh database)
mix precommit     # compile --warnings-as-errors + format + test
```
