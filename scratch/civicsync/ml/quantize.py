"""
CivicSync Post-Training INT8 Quantization Script
Converts saved Keras model to lightweight INT8 TFLite model (<5MB target)
Specification: TRD.pdf §2 (TRD-P1, TRD-P2), RULES.pdf §8.5
"""

import os
import argparse
import numpy as np
import tensorflow as tf

def representative_dataset_gen():
    """Generates synthetic/sample representative images for INT8 calibration."""
    for _ in range(100):
        # 224x224x3 normalized in [-1, 1]
        data = np.random.uniform(-1.0, 1.0, size=(1, 224, 224, 3)).astype(np.float32)
        yield [data]

def quantize_to_int8(saved_model_dir: str, output_tflite_path: str):
    """Convert SavedModel to full INT8 TFLite with integer ops."""
    print(f"Loading SavedModel from: {saved_model_dir}")
    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)

    # Optimization strategy
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.representative_dataset = representative_dataset_gen

    # Ensure integer-only quantization
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.float32  # standard input compatibility
    converter.inference_output_type = tf.float32 # standard output compatibility

    print("Converting and calibrating INT8 weights...")
    tflite_quant_model = converter.convert()

    os.makedirs(os.path.dirname(os.path.abspath(output_tflite_path)), exist_ok=True)
    with open(output_tflite_path, 'wb') as f:
        f.write(tflite_quant_model)

    size_mb = os.path.getsize(output_tflite_path) / (1024 * 1024)
    print(f"Quantization complete! Saved to {output_tflite_path}")
    print(f"Quantized Model Size: {size_mb:.2f} MB (Target: <= 5.00 MB)")
    assert size_mb <= 5.0, f"Model size {size_mb:.2f} MB exceeds 5 MB constraint!"

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Quantize CivicSync Model to INT8 TFLite")
    parser.add_argument('--saved_model_dir', type=str, default="./saved_model")
    parser.add_argument('--output', type=str, default="./civicsync_v1_int8.tflite")
    args = parser.parse_args()

    quantize_to_int8(args.saved_model_dir, args.output)
