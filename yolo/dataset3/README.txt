TESCO price-label dataset — tier labels v1, YOLO-segmentation format
====================================================================
images/{train,valid,test}/  43 photos     labels/{...}/  one .txt per image
Label line: <class_id> x1 y1 x2 y2 ...   (polygon, normalized 0-1)
classes.txt line number = class_id:  0=small 1=medium 2=large 3=price_label(untiered)
The train/valid/test folders ARE the frozen split — do not re-shuffle; the 6 test
images must never be used for training.
