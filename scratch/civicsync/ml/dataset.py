"""
CivicSync ML Pipeline - Dataset Ingestion & Augmentation
Specifications: TRD.pdf §6 (TRD-A1 to TRD-A4), TOOLING.pdf §4
"""

import os
from typing import List, Tuple, Generator

CLASSES = [
    'pothole',
    'open_drain',
    'broken_road',
    'waterlogging',
    'none_of_these'
]

CLASS_TO_IDX = {cls_name: idx for idx, cls_name in enumerate(CLASSES)}
IDX_TO_CLASS = {idx: cls_name for idx, cls_name in enumerate(CLASSES)}
INPUT_SHAPE = (224, 224, 3)

def preprocess_image(image_path: str, target_size: Tuple[int, int] = (224, 224)):
    """Read image, resize to target dimensions, and normalize to [-1, 1] for MobileNetV2."""
    import cv2
    import numpy as np

    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Failed to load image at {image_path}")
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    resized = cv2.resize(img_rgb, target_size, interpolation=cv2.INTER_AREA)
    normalized = (resized.astype(np.float32) / 127.5) - 1.0
    return normalized

def create_representative_dataset_generator(samples: List[str]):
    """Generator for TFLite post-training full INT8 quantization calibration."""
    import numpy as np
    for sample_path in samples[:150]:
        try:
            img = preprocess_image(sample_path)
            yield [np.expand_dims(img, axis=0)]
        except Exception:
            continue

