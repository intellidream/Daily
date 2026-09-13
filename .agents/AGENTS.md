# Project Rules

- **Research First**: Research thoroughly before writing code, understanding existing architectures, data models, and contracts.
- **Maintain Stability & Prevent Regressions**: Never break existing functional features. Preserve comments, docstrings, and verified functionality.
- **Ask, Don't Assume**: If requirements, architecture, or designs are ambiguous or unknown, ask the user directly instead of making assumptions.
- **Simulator First, Physical Device Delivery**: Rigorously test work on the iOS simulator (SimulaPhone) first (including mock/edge cases and visual inspection); once verified, build, deploy, and verify live on the physical iPhone ("Schmitz").
- **Documentation**: After implementing features and verifying builds are functional, ALWAYS document the relevant changes in the `Docs/Features` directory.
- **Clean Commits & Push**: Create clean, well-structured git commits with descriptive titles and summaries, and push to remote.
