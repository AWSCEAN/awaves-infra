"""
SageMaker Processing Job: preprocess.py

Input  : /opt/ml/processing/input/data/  (parquet training data)
Output : /opt/ml/processing/output/train/train.csv
         /opt/ml/processing/output/validation/validation.csv

CSV format: label (integer 0-4) in first column, no header
XGBoost built-in algorithm expects this format.

Features (26 total):
  Wave  : wave_height, wave_period, wave_direction_sin/cos
  Swell : swell_wave_height, swell_wave_period, swell_wave_direction_sin/cos
  SST   : sea_surface_temperature, ocean_current_velocity, sea_level_height_msl
  Wind  : wind_speed_10m, wind_direction_10m_sin/cos, wind_gusts_10m, temperature_2m
  Derived: wave_power, swell_power, wind_wave_ratio, gust_factor, wave_steepness
  Location: lat, lon, abs_lat
  Time  : hour_sin, hour_cos, day_of_week
"""

import glob
import math
import os

import numpy as np
import pandas as pd

INPUT_DIR = "/opt/ml/processing/input/data"
TRAIN_DIR = "/opt/ml/processing/output/train"
VAL_DIR = "/opt/ml/processing/output/validation"
TRAIN_RATIO = 0.8
RANDOM_SEED = 42


def _cyclical(series, period):
  rad = 2 * math.pi * series / period
  return np.sin(rad), np.cos(rad)


def _engineer(df):
  # Cyclical direction encodings
  df["wave_direction_sin"], df["wave_direction_cos"] = _cyclical(df["wave_direction"], 360)
  df["swell_wave_direction_sin"], df["swell_wave_direction_cos"] = _cyclical(df["swell_wave_direction"], 360)
  df["wind_direction_10m_sin"], df["wind_direction_10m_cos"] = _cyclical(df["wind_direction_10m"], 360)

  # Time features
  df["datetime"] = pd.to_datetime(df["datetime"])
  df["hour_sin"], df["hour_cos"] = _cyclical(df["datetime"].dt.hour, 24)
  df["day_of_week"] = df["datetime"].dt.dayofweek

  # Interaction terms
  df["wave_power"] = df["wave_height"] ** 2 * df["wave_period"]
  df["swell_power"] = df["swell_wave_height"] ** 2 * df["swell_wave_period"]
  df["wind_wave_ratio"] = df["wind_speed_10m"] / (df["wave_height"] + 1e-3)
  df["gust_factor"] = df["wind_gusts_10m"] / (df["wind_speed_10m"] + 1e-3)
  df["wave_steepness"] = df["wave_height"] / (df["wave_period"] ** 2 + 1e-3)

  # Absolute latitude (proxy for hemisphere seasonality)
  df["abs_lat"] = df["lat"].abs()

  return df


FEATURE_COLS = [
  "wave_height", "wave_period", "wave_direction_sin", "wave_direction_cos",
  "swell_wave_height", "swell_wave_period", "swell_wave_direction_sin", "swell_wave_direction_cos",
  "sea_surface_temperature", "ocean_current_velocity", "sea_level_height_msl",
  "wind_speed_10m", "wind_direction_10m_sin", "wind_direction_10m_cos",
  "wind_gusts_10m", "temperature_2m",
  "wave_power", "swell_power", "wind_wave_ratio", "gust_factor", "wave_steepness",
  "lat", "lon", "abs_lat",
  "hour_sin", "hour_cos", "day_of_week",
]


def main():
  os.makedirs(TRAIN_DIR, exist_ok=True)
  os.makedirs(VAL_DIR, exist_ok=True)

  # Load all parquet files in input dir
  files = glob.glob(os.path.join(INPUT_DIR, "**/*.parquet"), recursive=True)
  if not files:
    files = glob.glob(os.path.join(INPUT_DIR, "*.parquet"))
  if not files:
    raise FileNotFoundError(f"No parquet files found in {INPUT_DIR}")

  print(f"Loading {len(files)} parquet file(s)...")
  df = pd.concat([pd.read_parquet(f) for f in files], ignore_index=True)
  print(f"Loaded {len(df):,} rows")

  # Feature engineering
  df = _engineer(df)

  # Target: integer class 0-4
  df["target"] = df["rating_value"].clip(0, 4).round().astype(int)

  # Median imputation for missing values
  for col in FEATURE_COLS:
    if col in df.columns:
      median = df[col].median()
      df[col] = df[col].fillna(median)

  # Select features + drop any rows still missing
  cols = ["target"] + FEATURE_COLS
  df = df[cols].dropna()
  print(f"After cleaning: {len(df):,} rows | class dist: {df['target'].value_counts().sort_index().to_dict()}")

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
