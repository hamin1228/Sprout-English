from __future__ import annotations

from datetime import datetime
from typing import Any, Dict

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from app.config_loader import settings
from app.metrics import metrics_store

router = APIRouter()


@router.get("/")
async def root():
    return {
        "app": getattr(settings, "APP_NAME", "english_ai"),
        "version": getattr(settings, "VERSION", "0.1.0"),
    }


@router.get("/healthz")
def healthz():
    return {"ok": True, "time": datetime.utcnow().isoformat() + "Z"}


@router.get("/metrics/json")
async def metrics_json() -> Dict[str, Any]:
    snap = await metrics_store.snapshot()
    return {"window_sec": metrics_store.window_sec, "endpoints": snap}


@router.get("/metrics/alerts")
async def metrics_alerts() -> Dict[str, Any]:
    alerts = await metrics_store.evaluate_slo()
    return {"alert_count": len(alerts), "alerts": alerts}


@router.get("/metrics/dashboard", response_class=HTMLResponse)
async def metrics_dashboard() -> HTMLResponse:
    snap = await metrics_store.snapshot()
    rows_html = ""
    for key, m in snap.items():
        rows_html += f"""        <tr>
          <td>{key}</td>
          <td>{m["count"]}</td>
          <td>{m["errors"]}</td>
          <td>{m["p95_ms"]:.1f} ms</td>
          <td>{m["error_rate"] * 100.0:.2f}%</td>
        </tr>
        """
    html = f"""    <html>
      <head>
        <title>english_ai Metrics Dashboard</title>
        <meta http-equiv="refresh" content="5" />
        <style>
          body {{ font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 20px; }}
          table {{ border-collapse: collapse; width: 100%; }}
          th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
          th {{ background-color: #f2f2f2; }}
          tr:nth-child(even){{background-color: #fafafa;}}
        </style>
      </head>
      <body>
        <h1>english_ai Metrics Dashboard</h1>
        <p>Window: {metrics_store.window_sec} sec</p>
        <table>
          <thead>
            <tr><th>Endpoint</th><th>Count</th><th>Errors</th><th>P95 Latency</th><th>Error Rate</th></tr>
          </thead>
          <tbody>{rows_html}</tbody>
        </table>
      </body>
    </html>"""
    return HTMLResponse(content=html)
