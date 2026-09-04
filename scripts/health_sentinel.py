#!/usr/bin/env python3
"""
Deployment Health Sentinel — post-deploy watchdog.

Deterministic first: pod Ready ratio, restart counts, optional /readyz.
On failure: kubectl rollout undo, then optional LLM incident summary.
Without GEMINI_API_KEY / OPENAI_API_KEY the LLM step is skipped (graceful degrade).

Usage:
  python scripts/health_sentinel.py --namespace idea-board-demo --deployment backend
  python scripts/health_sentinel.py --namespace idea-board-demo --deployment backend --undo
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass
class SentinelReport:
    verdict: str  # HEALTHY | UNHEALTHY
    reasons: list[str] = field(default_factory=list)
    ready_replicas: int = 0
    desired_replicas: int = 0
    restart_total: int = 0
    pod_phases: dict[str, str] = field(default_factory=dict)
    readyz_ok: bool | None = None
    rolled_back: bool = False
    summary: str = ""
    llm_used: bool = False
    checked_at: str = ""


def run(cmd: list[str], timeout: int = 60) -> tuple[int, str, str]:
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    return proc.returncode, proc.stdout, proc.stderr


def kubectl_json(args: list[str]) -> Any:
    code, out, err = run(["kubectl", *args, "-o", "json"])
    if code != 0:
        raise RuntimeError(f"kubectl {' '.join(args)} failed: {err.strip() or out}")
    return json.loads(out)


def collect(namespace: str, deployment: str) -> dict[str, Any]:
    deploy = kubectl_json(["get", "deployment", deployment, "-n", namespace])
    pods = kubectl_json(
        ["get", "pods", "-n", namespace, "-l", f"app={deployment}"]
    )
    status = deploy.get("status", {})
    spec = deploy.get("spec", {})
    desired = int(spec.get("replicas") or 0)
    ready = int(status.get("readyReplicas") or 0)
    unavailable = int(status.get("unavailableReplicas") or 0)

    phases: dict[str, str] = {}
    restarts = 0
    pods_ready = 0
    pods_total = 0
    not_ready_pods: list[str] = []
    for item in pods.get("items", []):
        # Skip pods already terminating so a stuck delete doesn't false-alarm forever.
        if item.get("metadata", {}).get("deletionTimestamp"):
            continue
        pods_total += 1
        name = item["metadata"]["name"]
        phase = item.get("status", {}).get("phase", "Unknown")
        phases[name] = phase
        container_ready = True
        for cs in item.get("status", {}).get("containerStatuses") or []:
            restarts += int(cs.get("restartCount") or 0)
            if not cs.get("ready", False):
                container_ready = False
        # No containerStatuses yet → not ready
        if not (item.get("status", {}).get("containerStatuses") or []):
            container_ready = False
        if phase == "Running" and container_ready:
            pods_ready += 1
        else:
            not_ready_pods.append(name)

    logs = ""
    code, out, err = run(
        [
            "kubectl",
            "logs",
            "-n",
            namespace,
            "-l",
            f"app={deployment}",
            "--tail=40",
            "--prefix=true",
        ],
        timeout=45,
    )
    logs = out if code == 0 else (err or out)

    return {
        "desired": desired,
        "ready": ready,
        "unavailable": unavailable,
        "pods_total": pods_total,
        "pods_ready": pods_ready,
        "not_ready_pods": not_ready_pods,
        "restarts": restarts,
        "phases": phases,
        "logs": logs,
        "deploy_conditions": status.get("conditions") or [],
    }


def check_readyz(namespace: str, deployment: str, timeout: int = 8) -> bool | None:
    """Exec /readyz in every non-terminating pod. False if any returns non-200."""
    pods = kubectl_json(
        ["get", "pods", "-n", namespace, "-l", f"app={deployment}"]
    )
    names = []
    for item in pods.get("items", []):
        if item.get("metadata", {}).get("deletionTimestamp"):
            continue
        names.append(item["metadata"]["name"])
    if not names:
        return None

    any_ok = False
    any_fail = False
    for pod in names:
        code, body, err = run(
            [
                "kubectl",
                "exec",
                "-n",
                namespace,
                pod,
                "--",
                "python",
                "-c",
                (
                    "import urllib.request,urllib.error\n"
                    "try:\n"
                    "  r=urllib.request.urlopen('http://127.0.0.1:8000/readyz', timeout=5)\n"
                    "  print(r.status)\n"
                    "except urllib.error.HTTPError as e:\n"
                    "  print(e.code)\n"
                    "except Exception as e:\n"
                    "  print('ERR', type(e).__name__)\n"
                ),
            ],
            timeout=timeout + 10,
        )
        text = (body or err).strip()
        if code == 0 and text.startswith("200"):
            any_ok = True
        else:
            any_fail = True
    if any_fail:
        return False
    if any_ok:
        return True
    return False


def decide(
    snapshot: dict[str, Any],
    *,
    readyz_ok: bool | None,
    max_restarts: int,
) -> tuple[str, list[str]]:
    reasons: list[str] = []
    desired = snapshot["desired"]
    ready = snapshot["ready"]
    restarts = snapshot["restarts"]
    pods_total = snapshot.get("pods_total", 0)
    pods_ready = snapshot.get("pods_ready", 0)
    unavailable = snapshot.get("unavailable", 0)
    not_ready_pods = snapshot.get("not_ready_pods") or []

    if desired == 0:
        reasons.append("deployment desired replicas is 0")
    elif ready < desired:
        reasons.append(f"ready replicas {ready}/{desired} below desired")

    # Catch rolling-update stall: old Ready pod + new NotReady pod still shows 1/1 ready.
    if pods_total > 0 and pods_ready < pods_total:
        reasons.append(
            f"pod Ready count {pods_ready}/{pods_total} "
            f"(not ready: {', '.join(not_ready_pods) or 'unknown'})"
        )
    if unavailable > 0:
        reasons.append(f"unavailableReplicas={unavailable}")

    if restarts > max_restarts:
        reasons.append(f"restart count {restarts} exceeds max {max_restarts}")

    crashy = [n for n, p in snapshot["phases"].items() if p in ("Failed", "Unknown")]
    if crashy:
        reasons.append(f"unhealthy pod phases: {', '.join(crashy)}")

    if readyz_ok is False:
        reasons.append("/readyz not healthy on at least one pod (503 or unreachable)")

    return ("UNHEALTHY" if reasons else "HEALTHY"), reasons


def rollout_undo(namespace: str, deployment: str) -> None:
    code, out, err = run(
        ["kubectl", "rollout", "undo", f"deployment/{deployment}", "-n", namespace]
    )
    if code != 0:
        raise RuntimeError(f"rollout undo failed: {err or out}")
    code, out, err = run(
        [
            "kubectl",
            "rollout",
            "status",
            f"deployment/{deployment}",
            "-n",
            namespace,
            "--timeout=180s",
        ],
        timeout=200,
    )
    if code != 0:
        raise RuntimeError(f"rollout status after undo failed: {err or out}")


def llm_summary(report: SentinelReport, logs: str) -> str | None:
    """Optional Gemini (preferred) or OpenAI summary. Returns None if no key / failure."""
    prompt = (
        "You are an incident responder. Write a short (max 120 words) human-readable "
        "incident summary for a Kubernetes deploy. Include: what failed, evidence, "
        "and what automated action was taken. No shell commands. No speculation beyond evidence.\n\n"
        f"Verdict: {report.verdict}\n"
        f"Reasons: {report.reasons}\n"
        f"Ready: {report.ready_replicas}/{report.desired_replicas}\n"
        f"Restarts: {report.restart_total}\n"
        f"Phases: {report.pod_phases}\n"
        f"Readyz OK: {report.readyz_ok}\n"
        f"Rolled back: {report.rolled_back}\n"
        f"Recent logs (truncated):\n{logs[-2500:]}\n"
    )

    gemini_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if gemini_key:
        # Header auth; try flash-latest then lite alias (capacity / availability).
        models = ("gemini-flash-latest", "gemini-flash-lite-latest")
        body = json.dumps(
            {"contents": [{"parts": [{"text": prompt}]}]}
        ).encode()
        last_exc: Exception | None = None
        for model in models:
            url = (
                "https://generativelanguage.googleapis.com/v1beta/models/"
                f"{model}:generateContent"
            )
            req = urllib.request.Request(
                url,
                data=body,
                headers={
                    "Content-Type": "application/json",
                    "X-goog-api-key": gemini_key,
                },
                method="POST",
            )
            try:
                with urllib.request.urlopen(req, timeout=45) as resp:
                    data = json.loads(resp.read().decode())
                return data["candidates"][0]["content"]["parts"][0]["text"].strip()
            except (urllib.error.HTTPError, urllib.error.URLError, KeyError, IndexError, TimeoutError) as exc:
                last_exc = exc
                continue
        print(f"::warning::LLM summary skipped (Gemini): {last_exc}", file=sys.stderr)
        return None

    openai_key = os.getenv("OPENAI_API_KEY")
    if openai_key:
        body = json.dumps(
            {
                "model": "gpt-4o-mini",
                "messages": [
                    {"role": "system", "content": "Concise Kubernetes incident writer."},
                    {"role": "user", "content": prompt},
                ],
                "max_tokens": 220,
            }
        ).encode()
        req = urllib.request.Request(
            "https://api.openai.com/v1/chat/completions",
            data=body,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {openai_key}",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode())
            return data["choices"][0]["message"]["content"].strip()
        except (urllib.error.URLError, KeyError, IndexError, TimeoutError) as exc:
            print(f"::warning::LLM summary skipped (OpenAI): {exc}", file=sys.stderr)
            return None

    print("::notice::No GEMINI_API_KEY/OPENAI_API_KEY — using deterministic summary only")
    return None


def deterministic_summary(report: SentinelReport) -> str:
    if report.verdict == "HEALTHY":
        return (
            f"Deployment healthy at {report.checked_at}: "
            f"{report.ready_replicas}/{report.desired_replicas} ready, "
            f"{report.restart_total} restarts."
        )
    action = "Automatic rollout undo was executed." if report.rolled_back else "No undo requested."
    return (
        f"Deployment UNHEALTHY at {report.checked_at}. "
        f"Reasons: {'; '.join(report.reasons)}. {action}"
    )


def write_github_summary(report: SentinelReport) -> None:
    path = os.getenv("GITHUB_STEP_SUMMARY")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as fh:
        fh.write("## Deployment Health Sentinel\n\n")
        fh.write(f"**Verdict:** `{report.verdict}`\n\n")
        if report.reasons:
            fh.write("**Reasons:**\n")
            for r in report.reasons:
                fh.write(f"- {r}\n")
            fh.write("\n")
        fh.write(f"**Rolled back:** {report.rolled_back}\n\n")
        fh.write(f"**LLM used:** {report.llm_used}\n\n")
        fh.write(f"**Summary:** {report.summary}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Deployment Health Sentinel")
    parser.add_argument("--namespace", default="idea-board-demo")
    parser.add_argument("--deployment", default="backend")
    parser.add_argument("--wait-seconds", type=int, default=90)
    parser.add_argument("--interval", type=int, default=10)
    parser.add_argument("--max-restarts", type=int, default=3)
    parser.add_argument(
        "--undo",
        action="store_true",
        help="If UNHEALTHY, run kubectl rollout undo",
    )
    parser.add_argument(
        "--skip-readyz",
        action="store_true",
        help="Do not exec /readyz inside the pod",
    )
    args = parser.parse_args()

    deadline = time.time() + args.wait_seconds
    snapshot: dict[str, Any] = {}
    readyz_ok: bool | None = None
    verdict = "UNHEALTHY"
    reasons = ["no observations collected"]

    while True:
        snapshot = collect(args.namespace, args.deployment)
        readyz_ok = None if args.skip_readyz else check_readyz(args.namespace, args.deployment)
        verdict, reasons = decide(
            snapshot, readyz_ok=readyz_ok, max_restarts=args.max_restarts
        )
        print(
            f"[sentinel] ready={snapshot['ready']}/{snapshot['desired']} "
            f"restarts={snapshot['restarts']} readyz={readyz_ok} verdict={verdict}"
        )
        if verdict == "HEALTHY":
            break
        if time.time() >= deadline:
            break
        time.sleep(args.interval)

    report = SentinelReport(
        verdict=verdict,
        reasons=reasons,
        ready_replicas=snapshot.get("ready", 0),
        desired_replicas=snapshot.get("desired", 0),
        restart_total=snapshot.get("restarts", 0),
        pod_phases=snapshot.get("phases", {}),
        readyz_ok=readyz_ok,
        checked_at=datetime.now(timezone.utc).isoformat(),
    )

    if report.verdict == "UNHEALTHY" and args.undo:
        print("[sentinel] UNHEALTHY — executing kubectl rollout undo")
        rollout_undo(args.namespace, args.deployment)
        report.rolled_back = True

    llm_text = llm_summary(report, snapshot.get("logs", ""))
    if llm_text:
        report.summary = llm_text
        report.llm_used = True
    else:
        report.summary = deterministic_summary(report)

    print(json.dumps(asdict(report), indent=2))
    write_github_summary(report)

    # Exit 0 after successful undo so the demo workflow is green; exit 1 if still bad and no undo.
    if report.verdict == "HEALTHY":
        return 0
    if report.rolled_back:
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
