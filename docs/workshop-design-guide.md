# Workshop Design Guide

How to design, build, and run workshops using the Cognition-Partner-Workshops infrastructure.

## Concepts

| Concept | Definition | Location |
|---------|-----------|----------|
| **Module** | Atomic challenge task — a single hands-on exercise with prompts, target outcomes, and repo references | `workshop-metadata/modules/` |
| **Workshop** | Reusable template composing modules into a structured lab sequence with timing and track guidance | `workshop-metadata/workshops/` |
| **Event** | Point-in-time instance of a workshop for a specific date, location, and audience | `workshop-metadata/events/` |

Modules are the reusable atoms. Workshops compose modules. Events instantiate workshops.

## Creating a New Module

1. Create a markdown file in the appropriate `workshop-metadata/modules/<category>/` directory
2. Follow the 4-step format:
   - **Step 1: Paste into Devin** — copy-pasteable prompt
   - **Step 2: Research with Ask Devin** — exploratory prompts
   - **Step 3: Read the DeepWiki** — optional architecture exploration
   - **Step 4: Review & Give Feedback** — PR review workflow
3. Add cross-references in `workshop-metadata/catalog/repos.md` for any repos the challenge uses
4. Update the category `README.md` with the new challenge entry
5. Update `workshop-metadata/modules/README.md` navigation index
6. If the module needs facilitator-specific notes (MCP setup, presales positioning, timing guides), create a sibling file in `operator/docs/module-facilitator-notes/<category>/`

## Creating a New Workshop

1. Create a new directory under `workshop-metadata/workshops/` with a descriptive slug (e.g., `workshops/cloud-native-transformation/`)
2. Add a `README.md` following the structure of any existing workshop
3. Define labs using the 4-step format
4. List required modules and repos
5. Add timing guidelines for different duration variants
6. Include a "Getting the Most from This Workshop" section for attendees
7. Include a "Repos Required" checklist for facilitators to verify setup

## Creating an Event from a Workshop

1. Copy `operator/templates/event-readme.md` into `workshop-metadata/events/active/YYYY-MM-DD-<event-id>/README.md`
2. Reference the workshop(s) this event is based on (from `workshops/`)
3. Edit to fill in event details and any overrides
4. Specify which repos need to be set up on Devin's machine
5. Note any runtime resources that need to be provisioned (see [runtime-resources.md](runtime-resources.md))

### Event Naming Convention

Event directories use the pattern **`YYYY-MM-DD-<event-id>`** where:
- `YYYY-MM-DD` is the event date (or `YYYY-MM` if only the month is known)
- `<event-id>` is a short slug describing the event (city, audience, or topic)

Examples: `2026-06-15-new-york`, `2026-07-10-virtual-security`, `2026-08-dc-platform`

### Active vs. Archive

| Directory | Contents | When to Use |
|-----------|----------|-------------|
| `events/active/` | Upcoming or currently running events | Event has not yet occurred |
| `events/archive/` | Past events | Event date has passed |

After an event ends, move its directory from `active/` to `archive/`.

## Time Budget Guidelines

| Workshop Duration | Recommended Challenges | Notes |
|------------------|----------------------|-------|
| 2 hours | 2-3 challenges | Pick from one category |
| Half day (4 hours) | 4-6 challenges | Mix 2 categories |
| Full day (8 hours) | 8-12 challenges | Mix 3+ categories, include advanced |
| Multi-day | All challenges | Full curriculum |

## Audience-Based Recommendations

| Audience | Recommended Categories | Entry Point |
|----------|----------------------|-------------|
| Developers | Feature Dev + Migration | Application Development modules |
| QA Engineers | Quality + Bug Fixing | Testing & QA modules |
| DevOps/Platform | DevOps + Security | DevOps-CICD modules |
| Security Engineers | Security + DevOps | Security modules |
| Architects | Migration + DevOps | Architecture Design modules |
| Mixed/General | Broad tour across categories | A1 (warm-up) then mix |
| Executive | Quick wins with visible output | Short impactful labs |
| Mainframe/COBOL | Migration focused | COBOL System Understanding → COBOL to Java |

## Workshop Format Variations

### Lightning (1 hour)
- Facilitator-driven
- Show 2-3 challenges live
- Participants watch, then try one challenge in the remaining time
- Best for: executive audiences, first introductions

### Hands-on Half Day (4 hours)
- 15 min intro → 4-5 challenges → 15 min closing
- Mix categories: start easy, build up, finish with participant choice
- Best for: technical teams, first workshops

### Full Day Deep Dive (8 hours)
- Morning: structured labs (guided)
- Afternoon: open exploration (participant choice)
- Include breaks, lunch, and discussion sessions
- Best for: dedicated enablement, teams adopting Devin

### Multi-Session Series
- Weekly 2-hour sessions over 4 weeks
- Each session covers one category
- Participants build on previous sessions
- Best for: ongoing enablement programs

## Pacing Tips

- Each lab is designed so participants kick off the Devin session in the first 5 minutes, then use Ask Devin / DeepWiki while waiting
- When transitioning to the next lab, participants should start the new session immediately — they can review earlier PRs during any downtime
- Encourage overlapping sessions: kick off Lab N+1 while reviewing Lab N. This mirrors real enterprise usage
- Keep transitions tight — 2 minutes max between labs in short workshops

## Cross-References

| Resource | Location |
|----------|----------|
| Facilitator day-of guide | [docs/facilitator-guide.md](facilitator-guide.md) |
| Quality checklist for content | [docs/quality-checklist.md](quality-checklist.md) |
| Repo naming convention | [docs/repo-naming-convention.md](repo-naming-convention.md) |
| Runtime provisioning | [docs/runtime-resources.md](runtime-resources.md) |
| General themes / narratives | [docs/general-themes/](general-themes/) |
| Module facilitator notes | [docs/module-facilitator-notes/](module-facilitator-notes/) |
| Event facilitator notes | [docs/event-facilitator-notes/](event-facilitator-notes/) |
| Event config template | [templates/event-readme.md](../templates/event-readme.md) |
| Workshop provisioning scripts | [scripts/](../scripts/) |
| API reference | [docs/api-reference-cheatsheet.md](api-reference-cheatsheet.md) |
| Attendee-facing lab content | [workshop-metadata repo](https://github.com/Cognition-Partner-Workshops/workshop-metadata) |
