import os
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

try:
    import joblib
except ImportError:
    joblib = None

import firebase_admin
from firebase_admin import credentials, db


def env_required(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def severity_rank(severity: str) -> int:
    ranks = {"info": 0, "caution": 1, "warning": 2, "danger": 3}
    return ranks.get(severity, 0)


def pick_worst(items: List[Dict]) -> Dict:
    if not items:
        return {}
    worst = items[0]
    for item in items[1:]:
        if severity_rank(item["severity"]) > severity_rank(worst["severity"]):
            worst = item
    return worst


def rule_engine(payload: Dict) -> Dict:
    bpm = float(payload.get("bpm", 0))
    spo2 = float(payload.get("spo2", 0))
    temp = float(payload.get("temp", 0))
    activity = int(payload.get("activity", 0))
    sleep_mode = bool(payload.get("sleepMode", False))

    findings: List[Dict] = []

    # Combined rules
    if bpm > 100 and spo2 < 95 and activity == 0:
        findings.append({
            "type": "combined", "sensor": "cardio+oxygen+activity", "severity": "danger",
            "message": "High HR with low SpO2 at rest. Seek urgent medical advice."
        })
    if temp >= 38.0 and bpm > 100 and activity <= 1:
        findings.append({
            "type": "combined", "sensor": "temp+cardio", "severity": "warning",
            "message": "Fever with elevated heart rate while resting."
        })
    if sleep_mode and spo2 < 94:
        findings.append({
            "type": "sleep", "sensor": "spo2", "severity": "warning",
            "message": "Low SpO2 during sleep. Possible sleep breathing issue."
        })

    # Single-sensor rules
    if bpm < 50 or bpm > 120:
        findings.append({"type": "vitals", "sensor": "bpm", "severity": "danger", "message": "Heart rate is in a dangerous range."})
    elif 50 <= bpm <= 59 or 101 <= bpm <= 120:
        findings.append({"type": "vitals", "sensor": "bpm", "severity": "warning", "message": "Heart rate is outside normal range."})

    if spo2 < 92:
        findings.append({"type": "vitals", "sensor": "spo2", "severity": "danger", "message": "Blood oxygen is critically low."})
    elif 92 <= spo2 <= 94:
        findings.append({"type": "vitals", "sensor": "spo2", "severity": "warning", "message": "Blood oxygen slightly low."})

    if temp > 38.0 or temp < 35.5:
        findings.append({"type": "vitals", "sensor": "temp", "severity": "danger", "message": "Body temperature is in dangerous range."})

    if not findings:
        findings.append({"type": "status", "sensor": "all", "severity": "info", "message": "Vitals are within expected range."})

    return pick_worst(findings)


def ml_messages() -> Dict[str, str]:
    return {
        "info": "Model: vitals look consistent with a low-risk pattern.",
        "caution": "Model: mildly concerning pattern detected; keep monitoring.",
        "warning": "Model: notable risk pattern detected; rest and reassess vitals.",
        "danger": "Model: high-risk pattern detected; seek urgent medical evaluation.",
    }


def predict_with_ml(bundle: Dict[str, Any], payload: Dict) -> Tuple[Dict, float]:
    import pandas as pd
    pipe = bundle["pipeline"]
    feature_cols = list(bundle["feature_cols"])
    row = pd.DataFrame([{
        "bpm": float(payload["bpm"]),
        "spo2": float(payload["spo2"]),
        "temp": float(payload["temp"]),
        "activity": int(payload["activity"]),
        "sleep_mode": 1 if payload.get("sleepMode") else 0,
    }], columns=feature_cols)
    proba = pipe.predict_proba(row)[0]
    clf = pipe.named_steps["clf"]
    class_order = list(clf.classes_)
    idx = max(range(len(proba)), key=lambda i: proba[i])
    label = class_order[idx]
    conf = float(proba[idx])
    msgs = ml_messages()
    return {
        "type": "ml", "sensor": "classifier", "severity": str(label).lower(),
        "message": msgs.get(str(label).lower(), "Model severity classification.")
    }, conf


def choose_insight(ml_bundle: Optional[Dict[str, Any]], payload: Dict) -> Tuple[Dict, str]:
    if ml_bundle is not None and joblib is not None:
        try:
            ml_out, conf = predict_with_ml(ml_bundle, payload)
            if conf >= 0.7: return ml_out, f"ml({conf:.2f})"
            return rule_engine(payload), f"rules_fallback({conf:.2f})"
        except Exception as exc:
            print(f"ML failed: {exc}")
    return rule_engine(payload), "rules"


def load_ml_bundle() -> Optional[Dict[str, Any]]:
    path = os.getenv("ML_MODEL_PATH", "").strip()
    if not path:
        path = os.path.join(os.path.dirname(__file__), "models", "severity_rf.joblib")
    if not os.path.isfile(path) or joblib is None: return None
    try:
        b = joblib.load(path)
        print(f"Loaded ML bundle: {path}")
        return b
    except Exception as exc:
        print(f"ML load failed: {exc}")
        return None


def cleanup_old_data(now_ms: int) -> None:
    """Delete insights and aggregates older than 24 hours to preserve history."""
    cutoff_ms = now_ms - (24 * 60 * 60 * 1000)
    
    # Cleanup Insights
    insights_ref = db.reference("insights")
    insights_data = insights_ref.get()
    if insights_data:
        for uid, dates in insights_data.items():
            if not isinstance(dates, dict): continue
            for date_key, items in dates.items():
                if not isinstance(items, dict): continue
                for push_id, val in items.items():
                    ts = val.get("timestamp", 0)
                    if ts < cutoff_ms:
                        db.reference(f"insights/{uid}/{date_key}/{push_id}").delete()

    # Cleanup Aggregates
    agg_ref = db.reference("aggregates")
    agg_data = agg_ref.get()
    if agg_data:
        for uid, dates in agg_data.items():
            if not isinstance(dates, dict): continue
            for date_key, buckets in dates.items():
                if not isinstance(buckets, dict): continue
                for bucket_key, val in buckets.items():
                    ts = val.get("timestamp", 0)
                    if ts < cutoff_ms:
                        db.reference(f"aggregates/{uid}/{date_key}/{bucket_key}").delete()


def run() -> None:
    service_account_path = env_required("GOOGLE_APPLICATION_CREDENTIALS")
    project_id = env_required("FIREBASE_PROJECT_ID")
    ml_bundle = load_ml_bundle()

    if not firebase_admin._apps:
        cred = credentials.Certificate(service_account_path)
        firebase_admin.initialize_app(cred, {
            "projectId": project_id,
            "databaseURL": f"https://{project_id}-default-rtdb.europe-west1.firebasedatabase.app"
        })

    print("Insights service (RTDB) started. 1-min intervals with 10-min cleanup.")
    processed = set()
    poll_seconds = int(os.getenv("POLL_INTERVAL_SECONDS", "8"))

    while True:
        try:
            now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
            
            # Run Cleanup Cycle
            cleanup_old_data(now_ms)

            # Get all user aggregates
            agg_ref = db.reference("aggregates")
            agg_data = agg_ref.get()
            
            if not agg_data:
                time.sleep(poll_seconds)
                continue

            for uid, dates in agg_data.items():
                if not isinstance(dates, dict): continue
                
                for date_key, buckets in dates.items():
                    if not isinstance(buckets, dict): continue
                    
                    for bucket_key, data in buckets.items():
                        key = f"{uid}:{date_key}:{bucket_key}"
                        if key in processed: continue
                        
                        # Check if already processed in DB (to survive restarts)
                        if data.get("processed_for_insight"):
                            processed.add(key)
                            continue

                        payload = {
                            "bpm": float(data.get("bpm", 0)),
                            "spo2": float(data.get("spo2", 0)),
                            "temp": float(data.get("temp", 0)),
                            "activity": int(data.get("activity", 0)),
                            "sleepMode": bool(data.get("sleepMode", False)),
                        }
                        insight, infer_source = choose_insight(ml_bundle, payload)
                        
                        insight_doc = {
                            "type": insight["type"],
                            "sensor": insight["sensor"],
                            "message": insight["message"],
                            "severity": insight["severity"],
                            "timestamp": now_ms,
                            "source_bucket": bucket_key,
                            "infer_source": infer_source,
                        }

                        # Save insight to RTDB
                        db.reference(f"insights/{uid}/{date_key}").push(insight_doc)
                        
                        # Mark bucket as processed in DB
                        db.reference(f"aggregates/{uid}/{date_key}/{bucket_key}").update({
                            "processed_for_insight": True
                        })
                        
                        processed.add(key)
                        print(f"[{uid}] Insight generated: {insight['severity']}")

        except Exception as exc:
            print(f"Error in insights loop: {exc}")

        time.sleep(poll_seconds)


if __name__ == "__main__":
    run()
