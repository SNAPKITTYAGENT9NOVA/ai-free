# Tablekeeper — PHANTOM GRID Software Factory Submission

> **Event**: WeAreDevelopers x BAND Hackathon (Dark Factory Edition)  
> **Track**: `tablekeeper` (Restaurant Reservation System)  
> **Team**: PHANTOM GRID (Jack Hu + AI Autonomous Fleet)  

---

## Overview

This repository contains the complete autonomous software factory outputs for the `tablekeeper` track, constructed in full compliance with the official Participant Guide.

### Repository Layout

- `FACTORY.md`: Comprehensive description of the software factory design, seat roles, cost/time trade-offs, and failure recovery mechanisms.
- `mandates/`: Generic mandate definitions for each seat in the factory:
  - `architect.md`: Architecture planning and task delegation.
  - `coder.md`: Implementation and modular coding.
  - `reviewer.md`: Independent test execution and quality verification.
- `room.json`: Complete, unedited session log downloaded from Band Desktop demonstrating reciprocal multi-agent collaboration.
- `stage-1/`: Complete, self-contained, containerized HTTP service fulfilling Stage 1 requirements (API conformance, idempotency, atomic moves, export/import).

## Running Stage 1

Refer to `stage-1/RUN.md` for instructions on building and starting the service container.
