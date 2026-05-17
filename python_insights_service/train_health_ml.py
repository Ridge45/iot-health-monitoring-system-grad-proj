"""
Train a severity classifier on the GitHub health dataset.

Outputs for project documentation (not shipped to mobile users):
  - classification report (text)
  - confusion matrix heatmap
  - per-class precision/recall/F1 bars
  - RF feature importance

Also saves a joblib bundle for insights_service optional inference.
"""

from __future__ import annotations

import argparse
import io
import os
import urllib.request

import joblib
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402
import seaborn as sns  # noqa: E402
from sklearn.compose import ColumnTransformer  # noqa: E402
from sklearn.ensemble import RandomForestClassifier  # noqa: E402
from sklearn.metrics import (  # noqa: E402
    accuracy_score,
    classification_report,
    confusion_matrix,
)
from sklearn.model_selection import train_test_split  # noqa: E402
from sklearn.pipeline import Pipeline  # noqa: E402
from sklearn.preprocessing import StandardScaler  # noqa: E402

DEFAULT_DATA_URL = (
    "https://raw.githubusercontent.com/Ridge-m/health-data/main/health_data.csv"
)
FEATURE_COLS = ["bpm", "spo2", "temp", "activity", "sleep_mode"]
TARGET_COL = "severity_label"


def load_csv(path_or_url: str) -> pd.DataFrame:
    if path_or_url.startswith("http://") or path_or_url.startswith("https://"):
        with urllib.request.urlopen(path_or_url, timeout=60) as resp:
            raw = resp.read()
        df = pd.read_csv(io.BytesIO(raw))
    else:
        df = pd.read_csv(path_or_url)
    df.columns = df.columns.str.strip()
    for c in [TARGET_COL] + FEATURE_COLS:
        if c not in df.columns:
            raise ValueError(f"Missing column {c}. Found: {list(df.columns)}")
    df = df.dropna(subset=FEATURE_COLS + [TARGET_COL])
    df[TARGET_COL] = df[TARGET_COL].astype(str).str.strip().str.lower()
    return df


def plot_confusion(cm: pd.DataFrame, out_path: str) -> None:
    plt.figure(figsize=(8, 6))
    sns.heatmap(cm, annot=True, fmt=".3f", cmap="Blues", vmin=0, vmax=1)
    plt.title("Normalized confusion matrix (severity_label)")
    plt.ylabel("True")
    plt.xlabel("Predicted")
    plt.tight_layout()
    plt.savefig(out_path, dpi=150)
    plt.close()


def plot_metric_bars(report_dict: dict, labels: list, out_path: str) -> None:
    precision = []
    recall = []
    f1 = []
    for lbl in labels:
        block = report_dict.get(lbl, {})
        precision.append(block.get("precision", 0.0))
        recall.append(block.get("recall", 0.0))
        f1.append(block.get("f1-score", 0.0))
    x = range(len(labels))
    width = 0.25
    plt.figure(figsize=(10, 6))
    plt.bar([i - width for i in x], precision, width, label="Precision")
    plt.bar(x, recall, width, label="Recall")
    plt.bar([i + width for i in x], f1, width, label="F1")
    plt.xticks(list(x), labels, rotation=20)
    plt.ylim(0, 1.05)
    plt.legend()
    plt.title("Per-class metrics (test set)")
    plt.tight_layout()
    plt.savefig(out_path, dpi=150)
    plt.close()


def plot_feature_importance(importances: dict, out_path: str) -> None:
    names = list(importances.keys())
    vals = list(importances.values())
    plt.figure(figsize=(8, 5))
    sns.barplot(x=vals, y=names)
    plt.title("Random forest feature importance")
    plt.tight_layout()
    plt.savefig(out_path, dpi=150)
    plt.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Train health severity model from CSV")
    parser.add_argument(
        "--data",
        default=os.getenv("DATASET_URL", DEFAULT_DATA_URL),
        help="Local CSV path or URL",
    )
    parser.add_argument(
        "--output-dir",
        default=os.getenv("ML_BOOK_OUTPUT_DIR", "ml_book_outputs"),
        help="Folder for report + PNG figures",
    )
    parser.add_argument(
        "--model-out",
        default=os.getenv(
            "ML_MODEL_OUT", os.path.join("models", "severity_rf.joblib")
        ),
        help="Path for saved joblib bundle",
    )
    parser.add_argument("--test-size", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--max-depth", type=int, default=12)
    parser.add_argument("--n-estimators", type=int, default=200)
    args = parser.parse_args()

    out_dir = os.path.abspath(args.output_dir)
    os.makedirs(out_dir, exist_ok=True)
    model_dir = os.path.dirname(os.path.abspath(args.model_out))
    if model_dir:
        os.makedirs(model_dir, exist_ok=True)

    print("Loading data...")
    df = load_csv(args.data)
    classes = sorted(df[TARGET_COL].unique().tolist())

    X = df[FEATURE_COLS]
    y = df[TARGET_COL]

    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=args.test_size,
        random_state=args.seed,
        stratify=y,
    )

    preprocess = ColumnTransformer(
        transformers=[("scale", StandardScaler(), FEATURE_COLS)],
        remainder="drop",
    )
    clf = RandomForestClassifier(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        random_state=args.seed,
        class_weight="balanced",
        n_jobs=-1,
    )
    pipe = Pipeline([("preprocess", preprocess), ("clf", clf)])
    print("Training RandomForest...")
    pipe.fit(X_train, y_train)
    y_pred = pipe.predict(X_test)
    acc = accuracy_score(y_test, y_pred)
    report = classification_report(
        y_test, y_pred, labels=classes, digits=4, zero_division=0
    )

    cm = confusion_matrix(y_test, y_pred, labels=classes)
    cm_norm = cm.astype(float) / cm.sum(axis=1, keepdims=True).clip(min=1e-12)

    report_txt_path = os.path.join(out_dir, "classification_report.txt")
    with open(report_txt_path, "w", encoding="utf-8") as f:
        f.write("Health severity classifier — train/test evaluation\n")
        f.write(f"Rows: {len(df)}  Train: {len(X_train)}  Test: {len(X_test)}\n")
        f.write(f"Accuracy: {acc:.4f}\n\n")
        f.write(report)
        f.write("\n\nConfusion matrix (counts):\n")
        f.write(pd.DataFrame(cm, index=classes, columns=classes).to_string())
        f.write("\n")

    print(report)
    print(f"\nAccuracy: {acc:.4f}")
    print(f"Wrote {report_txt_path}")

    cm_df = pd.DataFrame(cm_norm, index=classes, columns=classes)
    plot_confusion(cm_df, os.path.join(out_dir, "confusion_matrix_normalized.png"))
    report_dict = classification_report(
        y_test,
        y_pred,
        labels=classes,
        output_dict=True,
        zero_division=0,
    )
    plot_metric_bars(
        report_dict,
        classes,
        os.path.join(out_dir, "metrics_per_class.png"),
    )

    rf = pipe.named_steps["clf"]
    imps = dict(zip(FEATURE_COLS, rf.feature_importances_))
    plot_feature_importance(
        imps, os.path.join(out_dir, "feature_importance_rf.png")
    )

    bundle = {
        "pipeline": pipe,
        "feature_cols": FEATURE_COLS,
        "target_col": TARGET_COL,
        "classes": classes,
        "accuracy_test": float(acc),
    }
    joblib.dump(bundle, args.model_out)
    print(f"Saved model bundle: {args.model_out}")
    print(f"Figures in: {out_dir}")


if __name__ == "__main__":
    main()
