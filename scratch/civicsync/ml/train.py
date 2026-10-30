"""
CivicSync ML Model Training Script
Backbone: MobileNetV2 (ImageNet weights)
Output: 5 classes (pothole, open_drain, broken_road, waterlogging, none_of_these)
Specification: TRD.pdf §6, TOOLING.pdf §4
"""

import os
import argparse
import tensorflow as tf
from tensorflow.keras import layers, models
from dataset import CLASSES, INPUT_SHAPE

def build_model(num_classes: int = len(CLASSES), dropout_rate: float = 0.2) -> tf.keras.Model:
    """Build lightweight classifier with MobileNetV2 backbone."""
    base_model = tf.keras.applications.MobileNetV2(
        input_shape=INPUT_SHAPE,
        include_top=False,
        weights='imagenet'
    )
    base_model.trainable = False  # Freeze for transfer learning phase 1

    inputs = tf.keras.Input(shape=INPUT_SHAPE)
    x = base_model(inputs, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(dropout_rate)(x)
    outputs = layers.Dense(num_classes, activation='softmax', name='hazard_predictions')(x)

    model = tf.keras.Model(inputs, outputs, name='civicsync_mobilenetv2')
    return model, base_model

def fine_tune_model(model: tf.keras.Model, base_model: tf.keras.Model, fine_tune_at: int = 100):
    """Unfreeze top layers of backbone for phase 2 fine-tuning."""
    base_model.trainable = True
    for layer in base_model.layers[:fine_tune_at]:
        layer.trainable = False

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-5),
        loss=tf.keras.losses.CategoricalCrossentropy(label_smoothing=0.05),
        metrics=['accuracy', tf.keras.metrics.Precision(name='precision'), tf.keras.metrics.Recall(name='recall')]
    )

def main():
    parser = argparse.ArgumentParser(description="Train CivicSync Hazard Classifier")
    parser.add_argument('--epochs', type=int, default=15, help="Number of training epochs")
    parser.add_argument('--batch_size', type=int, default=32, help="Batch size")
    parser.add_argument('--output_dir', type=str, default="./saved_model", help="Directory to save model")
    args = parser.parse_args()

    print(f"Building CivicSync model for {len(CLASSES)} hazard classes...")
    model, base_model = build_model()
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )
    model.summary()

    os.makedirs(args.output_dir, exist_ok=True)
    # Save base architecture for quantization pipeline
    model.export(args.output_dir)
    print(f"Model exported successfully to {args.output_dir}")

if __name__ == '__main__':
    main()
