# RF_Classifier

**What it does**

This R script reads in a CSV formatted file generated by the user, then, depending on whether or not a trained random forest (RF) is provided, it will either run with the "training mode" (RF not provided or invalid file path), or the "prediction mode". In the training mode, a leave-half-out cross-validation (LHOCV) is happening at the same time, along with the RF training.

The CSV file needs to follow this format:
-Column #1: The ID (should be unique)
-Column #2: The sequence class (or a run of "NA" or whatever for prediction mode).
-Column #3 and onwards: parameters to be used for training and prediction.
