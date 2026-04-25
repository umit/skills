# Contributing

Thanks for considering a contribution.

## Adding a new skill

1. Create a folder under `skills/<skill-name>/`.
2. Add a `SKILL.md` with valid frontmatter:
   ```yaml
   ---
   name: skill-name
   description: What it does AND when to use it. Be explicit about trigger contexts (symptom phrases, tool names, related domain terms). Aim for ~100 words; lean toward "pushy" to combat under-triggering.
   ---
   ```
3. Keep `SKILL.md` body under ~500 lines. Move detail into `references/`.
4. Optional folders:
   - `references/` — long-form docs the agent reads on demand. Add a table of contents if a file exceeds 300 lines.
   - `scripts/` — executable helpers with safe defaults; document each in `SKILL.md`.
   - `assets/` — templates, fonts, or files used in skill output.

## Style

- Imperative form in instructions ("Identify the JVM", not "you should identify").
- Explain *why* something matters; avoid arbitrary `MUST`s.
- Don't duplicate when-to-use guidance between description and body — it goes in the description.
- Reference files explicitly from `SKILL.md` with a one-line "when to read".

## Testing

For skills with verifiable outputs, add `evals/evals.json` with 5–10 realistic prompts including trigger-positive and trigger-negative cases. Use [skill-creator](https://skills.sh/anthropics/skills/skill-creator) to run the eval loop.

## Pull requests

- One skill per PR.
- Update `README.md` skills table.
- Verify `npx skills add umit/skills --skill <new-skill>` works locally before submitting.

## License

By contributing you agree your contribution is licensed under the [MIT License](LICENSE).
