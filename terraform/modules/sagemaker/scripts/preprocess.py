"""
SageMaker Processing Job: preprocess.py

Input  : /opt/ml/processing/input/data/  (labeled CSV from DataCollection Lambda)
Output : /opt/ml/processing/output/train/train.csv
         /opt/ml/processing/output/validation/validation.csv

CSV format: label (integer 0-4) in first column, no header.
XGBoost built-in algorithm expects this format.

Input CSV columns (from data_collection_training.py):
  rating_value (0-4 int), + 23 FEATURE_COLS (coastline-relative, already engineered)

Features (23 total, coastline-relative — matches Lambda preprocessing handler):
  Wave  : wave_height, wave_period
  Swell : swell_wave_height, swell_wave_period
  SST   : sea_surface_temperature
  Wind  : wind_speed_10m, wind_gusts_10m
  Dirs  : wave_direction_rel_sin/cos, swell_wave_direction_rel_sin/cos,
          wind_direction_10m_rel_cos
  Derived: wave_power, swell_power, wind_wave_ratio, wave_steepness,
           abs_lat, wind_onshore, wind_cross, gust_onshore,
           wave_shore_power, swell_shore_power, swell_cross_power
"""

import glob
import os

import numpy as np
import pandas as pd

INPUT_DIR = "/opt/ml/processing/input/data"
TRAIN_DIR = "/opt/ml/processing/output/train"
VAL_DIR = "/opt/ml/processing/output/validation"
TRAIN_RATIO = 0.8
RANDOM_SEED = 42

# Must match data_collection_training.py FEATURE_COLS exactly
FEATURE_COLS = [
    "wave_height", "wave_period",
    "swell_wave_height", "swell_wave_period",
    "sea_surface_temperature",
    "wind_speed_10m", "wind_gusts_10m",
    "wave_direction_rel_sin", "wave_direction_rel_cos",
    "swell_wave_direction_rel_sin", "swell_wave_direction_rel_cos",
    "wind_direction_10m_rel_cos",
    "wave_power", "swell_power",
    "wind_wave_ratio", "wave_steepness",
    "abs_lat",
    "wind_onshore", "wind_cross", "gust_onshore",
    "wave_shore_power", "swell_shore_power", "swell_cross_power",
]


def main():
    os.makedirs(TRAIN_DIR, exist_ok=True)
    os.makedirs(VAL_DIR, exist_ok=True)

    # Load labeled CSV(s) — written by data_collection_training Lambda
    files = glob.glob(os.path.join(INPUT_DIR, "**/*.csv"), recursive=True)
    if not files:
        files = glob.glob(os.path.join(INPUT_DIR, "*.csv"))
    if not files:
        raise FileNotFoundError(f"No CSV files found in {INPUT_DIR}")

    print(f"Loading {len(files)} CSV file(s)...")
    df = pd.concat([pd.read_csv(f) for f in files], ignore_index=True)
    print(f"Loaded {len(df):,} rows")

    # Coerce numeric types (CSV values are strings)
    for col in FEATURE_COLS:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    # Target: integer class 0-4
    df["rating_value"] = df["rating_value"].clip(0, 4).round().astype(int)

    # Median imputation for missing feature values
    for col in FEATURE_COLS:
        if col in df.columns:
            median = df[col].median()
            df[col] = df[col].fillna(median)

    # Select features + drop any rows still missing
    cols = ["rating_value"] + FEATURE_COLS
    df = df[cols].dropna()
    print(
        f"After cleaning: {len(df):,} rows | "
        f"class dist: {df['rating_value'].value_counts().sort_index().to_dict()}"
    )

    # Shuffle + split
    df = df.sample(frac=1, random_state=RANDOM_SEED).reset_index(drop=True)
    split = int(len(df) * TRAIN_RATIO)
    train_df = df.iloc[:split]
    val_df = df.iloc[split:]

    print(f"Train: {len(train_df):,} | Validation: {len(val_df):,}")

    train_df.to_csv(os.path.join(TRAIN_DIR, "train.csv"), index=False, header=False)
    val_df.to_csv(os.path.join(VAL_DIR, "validation.csv"), index=False, header=False)
    print("Saved train.csv and validation.csv")


if __name__ == "__main__":
    main()
