# Python Insights Service

This service reads new Firestore `30min_avg` documents, classifies them with the trained ML model, and writes insight records into:

- `users/{uid}/insights/{autoId}`

## 1) Install

```bash
cd python_insights_service
pip install -r requirements.txt
```

## 2) Firebase credentials

Create/download a Firebase service account key JSON, then set:

- `GOOGLE_APPLICATION_CREDENTIALS` = full path to JSON key
- `FIREBASE_PROJECT_ID` = your firebase project id

Optional:

- `POLL_INTERVAL_SECONDS` (default: 8)

## 3) Run

```bash
python insights_service.py
```

## Notes

- Insights are ML-based by default using `models/severity_rf.joblib`.
- The model was trained from the provided health dataset fields: `bpm`, `spo2`, `temp`, `activity`, `sleep_mode`.
- Each written insight stores `infer_source`, for example `ml(0.94)`, showing model confidence.
- Rule fallback is disabled by default. Set `ALLOW_RULE_FALLBACK=true` only if you intentionally want the service to keep running without ML.

## ML training (for project report / book, not shown in the Flutter app)

Uses the public dataset from your spec
([health_data.csv](https://github.com/Ridge-m/health-data/blob/main/health_data.csv)).
Trains a Random Forest on `bpm`, `spo2`, `temp`, `activity`, `sleep_mode` predicting `severity_label`.

```bash
pip install -r requirements.txt
python train_health_ml.py
```

Outputs under `ml_book_outputs/` (default):

- `classification_report.txt` — precision / recall / F1
- `confusion_matrix_normalized.png`
- `metrics_per_class.png`
- `feature_importance_rf.png`

Trained bundle (for optional live inference): `models/severity_rf.joblib`.

### ML model used by `insights_service.py`

- Set `ML_MODEL_PATH` to the joblib path, or place the file at `python_insights_service/models/severity_rf.joblib`.
- If no model is found, the service stops instead of silently producing rule-based insights.
