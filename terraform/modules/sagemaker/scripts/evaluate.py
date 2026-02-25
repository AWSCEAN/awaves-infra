"""
SageMaker Processing Job: evaluate.py

Loads the trained XGBoost model and validation data to compute evaluation metrics
and generate the drift detection baseline distribution.

Input:
  /opt/ml/processing/input/model/  - model.tar.gz from training job
  /opt/ml/processing/input/validation/ - validation.csv (label first, no header)
  /opt/ml/processing/input/code/ - this script

Output:
  /opt/ml/processing/output/evaluation/evaluation.json
    -> read by SageMaker Pipeline ConditionStep (metrics.qwk >= 0.7 -> approve)
  /opt/ml/processing/output/drift/baseline.json
    -> uploaded to s3://awaves-ml-{env}/drift/baseline.json
    -> read by Lambda drift_detection on each inference cycle

evaluation.json format:
  {
    "metrics": {
      "qwk": 0.774,
      "accuracy": 0.683,
      "rmse": 0.821,
      "n_samples": 400000
    },
    "per_class": {"0": {...}, "1": {...}, "2": {...}, "3": {...}, "4": {...}}
  }

baseline.json format:
  { "rating_distribution": [0.05, 0.15, 0.35, 0.30, 0.15] }
  -> proportions of predicted classes [0, 1, 2, 3, 4]
"""

import glob
import json
import math
import os
import tarfile

import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.metrics import accuracy_score, cohen_kappa_score, confusion_matrix

MODEL_DIR = "/opt/ml/processing/input/model"
VAL_DIR = "/opt/ml/processing/input/validation"
EVAL_OUT_DIR = "/opt/ml/processing/output/evaluation"
DRIFT_OUT_DIR = "/opt/ml/processing/output/drift"

N_CLASSES = 5


def _load_model(model_dir):
  tar_files = glob.glob(os.path.join(model_dir, "*.tar.gz"))
  if not tar_files:
    raise FileNotFoundError(f"No model tar.gz in {model_dir}")
  tar_path = tar_files[0]

  extract_dir = "/tmp/model_extracted"
  os.makedirs(extract_dir, exist_ok=True)
  with tarfile.open(tar_path, "r:gz") as tar:
    tar.extractall(extract_dir)

  # XGBoost model file is typically named "xgboost-model"
  model_file = os.path.join(extract_dir, "xgboost-model")
  if not os.path.exists(model_file):
    candidates = glob.glob(os.path.join(extract_dir, "*"))
    model_file = candidates[0] if candidates else None
  if not model_file:
    raise FileNotFoundError(f"No model file found after extracting {tar_path}")

  model = xgb.Booster()
  model.load_model(model_file)
  print(f"Loaded model from {model_file}")
  return model


def _load_validation(val_dir):
  csv_files = glob.glob(os.path.join(val_dir, "*.csv"))
  if not csv_files:
    raise FileNotFoundError(f"No validation CSV in {val_dir}")
  df = pd.concat([pd.read_csv(f, header=None) for f in csv_files], ignore_index=True)
  y = df.iloc[:, 0].astype(int).values
  X = df.iloc[:, 1:].values.astype(float)
  print(f"Validation: {len(y):,} samples | classes: {np.unique(y).tolist()}")
  return X, y


def _qwk(y_true, y_pred, n_classes=N_CLASSES):
  return cohen_kappa_score(y_true, y_pred, weights="quadratic", labels=list(range(n_classes)))


def _rmse(y_true, y_pred):
  return math.sqrt(((y_true - y_pred) ** 2).mean())


def main():
  os.makedirs(EVAL_OUT_DIR, exist_ok=True)
  os.makedirs(DRIFT_OUT_DIR, exist_ok=True)

  model = _load_model(MODEL_DIR)
  X_val, y_true = _load_validation(VAL_DIR)

  dval = xgb.DMatrix(X_val)
  y_pred_raw = model.predict(dval)
  y_pred = y_pred_raw.astype(int)

  # Clip predictions to valid range
  y_pred = np.clip(y_pred, 0, N_CLASSES - 1)

  qwk = _qwk(y_true, y_pred)
  acc = accuracy_score(y_true, y_pred)
  rmse = _rmse(y_true.astype(float), y_pred.astype(float))

  print(f"QWK: {qwk:.4f} | Accuracy: {acc:.4f} | RMSE: {rmse:.4f}")

  # Per-class precision/recall from confusion matrix
  cm = confusion_matrix(y_true, y_pred, labels=list(range(N_CLASSES)))
  per_class = {}
  for i in range(N_CLASSES):
    tp = int(cm[i, i])
    fp = int(cm[:, i].sum() - tp)
    fn = int(cm[i, :].sum() - tp)
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    per_class[str(i)] = {
      "precision": round(precision, 4),
      "recall": round(recall, 4),
      "count": int(cm[i, :].sum()),
    }

  evaluation = {
    "metrics": {
      "qwk": round(qwk, 4),
      "accuracy": round(acc, 4),
      "rmse": round(rmse, 4),
      "n_samples": int(len(y_true)),
    },
    "per_class": per_class,
  }

  eval_path = os.path.join(EVAL_OUT_DIR, "evaluation.json")
  with open(eval_path, "w") as f:
    json.dump(evaluation, f, indent=2)
  print(f"Saved evaluation report to {eval_path}")

  # Drift baseline: distribution of predicted classes
  counts = [int((y_pred == i).sum()) for i in range(N_CLASSES)]
  total = sum(counts) or 1
  baseline = {"rating_distribution": [round(c / total, 6) for c in counts]}

  baseline_path = os.path.join(DRIFT_OUT_DIR, "baseline.json")
  with open(baseline_path, "w") as f:
    json.dump(baseline, f, indent=2)
  print(f"Saved drift baseline to {baseline_path}: {baseline}")


if __name__ == "__main__":
  main()
