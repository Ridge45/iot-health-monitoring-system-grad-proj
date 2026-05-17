import os
import time
from datetime import datetime, timezone

import firebase_admin
from firebase_admin import credentials, db


def env_required(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def get_1min_bucket(ts_ms: int) -> int:
    """Round timestamp down to nearest 1-minute bucket."""
    ts_sec = ts_ms // 1000
    bucket_sec = (ts_sec // 60) * 60
    return bucket_sec * 1000


def activity_to_int(activity: str) -> int:
    """Convert activity string to numeric level."""
    levels = {
        "stationary": 0,
        "low": 1,
        "moderate": 2,
        "high": 3,
    }
    return levels.get(activity.lower(), 0)


def run() -> None:
    service_account_path = env_required("GOOGLE_APPLICATION_CREDENTIALS")
    project_id = env_required("FIREBASE_PROJECT_ID")

    if not firebase_admin._apps:
        cred = credentials.Certificate(service_account_path)
        firebase_admin.initialize_app(
            cred,
            {
                "projectId": project_id,
                "databaseURL": f"https://{project_id}-default-rtdb.europe-west1.firebasedatabase.app",
            },
        )

    print("Aggregation service (RTDB) started. Processing raw health data...")

    processed_buckets = {} # uid -> last_ts
    poll_seconds = int(os.getenv("POLL_INTERVAL_SECONDS", "8"))

    while True:
        try:
            # Get all live data from RTDB
            live_ref = db.reference("live")
            live_data = live_ref.get()
            
            if not live_data:
                time.sleep(poll_seconds)
                continue

            now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
            date_key = datetime.now(timezone.utc).strftime("%Y-%m-%d")

            for uid, user_data in live_data.items():
                if not isinstance(user_data, dict):
                    continue

                # Extract metrics
                bpm = float(user_data.get("bpm", 0))
                spo2 = float(user_data.get("spo2", 0))
                temp = float(user_data.get("temp", 0))
                activity_str = user_data.get("activity", "Stationary")
                activity = activity_to_int(activity_str)
                sleep_mode = bool(user_data.get("sleepMode", False))
                ts = int(user_data.get("ts", now_ms))

                if ts < 1000000000000: ts *= 1000

                # Get 1-min bucket key (HHmmss)
                bucket_ms = get_1min_bucket(ts)
                bucket_key = datetime.fromtimestamp(
                    bucket_ms / 1000, tz=timezone.utc
                ).strftime("%H%M%S")

                bucket_path = f"aggregates/{uid}/{date_key}/{bucket_key}"
                # Avoid re-processing the exact same reading
                if uid not in processed_buckets:
                    processed_buckets[uid] = 0
                
                if ts <= processed_buckets[uid]:
                    continue
                
                processed_buckets[uid] = ts

                # Check existing in RTDB
                ref = db.reference(bucket_path)
                existing = ref.get()

                if existing:
                    count = existing.get("count", 1) + 1
                    # Running average
                    new_bpm = ((existing.get("bpm", 0) * (count - 1) + bpm) / count)
                    new_spo2 = ((existing.get("spo2", 0) * (count - 1) + spo2) / count)
                    new_temp = ((existing.get("temp", 0) * (count - 1) + temp) / count)
                    new_activity = max(existing.get("activity", 0), activity)

                    ref.update({
                        "bpm": new_bpm,
                        "spo2": new_spo2,
                        "temp": new_temp,
                        "activity": new_activity,
                        "sleepMode": sleep_mode,
                        "count": count,
                        "updated_at": now_ms,
                    })
                else:
                    ref.set({
                        "bpm": bpm,
                        "spo2": spo2,
                        "temp": temp,
                        "activity": activity,
                        "sleepMode": sleep_mode,
                        "count": 1,
                        "timestamp": bucket_ms,
                        "created_at": now_ms,
                    })
                    print(f"[{uid}] New bucket: {date_key}/{bucket_key}")

                # The ts-based check above handles deduplication per-run.

        except Exception as exc:
            print(f"Error in aggregation loop: {exc}")

        time.sleep(poll_seconds)


if __name__ == "__main__":
    run()

