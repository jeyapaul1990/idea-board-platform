# Demo video checklist (Outmarket case study)

Record ~5–8 minutes. Show the repo URL and both live URLs in the description.

## Suggested order

1. **Local** — `docker compose up --build` → http://localhost:8080 → add an idea  
2. **Architecture** — open `docs/architecture.png` / README diagram (two-stage contract)  
3. **GCP live** — http://34.14.209.195/ → add an idea, refresh  
4. **Bad deploy + rollback (AI)** — Actions → **Deploy Health Sentinel** → `demo_bad_deploy=true`  
   - Show UNHEALTHY → `rollout undo` in the log  
   - Confirm the GCP URL works again  
5. **CI/CD path** — Actions → **CI/CD** run: pytest → Trivy → push → `deploy-gcp` → sentinel  
6. **Azure live** — http://4.224.236.191/ → add an idea  
7. **Close** — one sentence: *AI proposes, deterministic systems decide*

## Tips

- Use a large font / zoom IDE for workflow YAML and sentinel JSON  
- If Gemini returns 503, the deterministic summary still counts — call that out  
- Keep clusters up only for recording day (cost)
