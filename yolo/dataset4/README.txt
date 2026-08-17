TESCO price-ticket dataset - tier labels v2, YOLO-segmentation format
===================================================================
Label line: <class_id> x1 y1 x2 y2 ...   (polygon, normalized 0-1)
classes.txt line number = class_id: 0=small 1=medium 2=large 3=price_label(unsure)

The train/valid/test folders ARE the frozen split. The 6 test images come from the
original reference set and must never be used for training - every published metric
depends on that holdout. All team-round photos are in train.

sources.csv records who labeled each photo (original / hasham / jara / jara1 / abdul).
