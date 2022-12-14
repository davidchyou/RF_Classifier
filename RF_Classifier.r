## This R script reads in a CSV formatted file generated by the user, then, depending on 
## whether or not a trained random forest (RF) is provided, it will either run with the 
## "training mode" (RF not provided or invalid file path), or the "prediction mode".
##
## In the training mode, a leave-half-out cross-validation (LHOCV) is happening at the same time, along with
## the RF training.
##
## The CSV file needs to follow this format:
## Column #1: The ID (should be unique)
## Column #2: The sequence class (or a run of "NA" or whatever for prediction mode).
## Column #3 and onwards: parameters to be used for training and prediction.
##
## Outputs:
## Training mode:
## 1. An RDS file of a R List object, containing the trained RF, the LHOCV ROC-curve of the RF with the AUC, and scores from LHOCV.
## 2. The LHOCV ROC-curve of the RF with the AUC as a CSV file.
## 3. The scores from LHOCV (one column per class) combined with the original data.
##
## Prediction mode:
## 1. Prediction scores (one column per class) generated by the RF (i.e. the RDS file from training mode), combined with the original data.
##
## Additional note:
## In training mode, the script will check that there are at least two classes in the dataset, and there are at least 10 data in each class.
## This ensures the sample size is adequate.
## 
## Usage: 
## Rscript RF_classifier.r [Input csv] [RF RDS path (training mode) | NA (prediction mode)] [Output DIR] [1 (training mode) | 0 (prediction mode)]
##
## Training mode example:
## Rscript RF_classifier.r promoter.csv NA test_PromAnalyser_train 1
##
## Prediction mode example:
## Rscript RF_classifier.r promoter.csv test_PromAnalyser_train/rf_model.rds test_PromAnalyser_predict 0
##       

options(warn=-1)
suppressWarnings(suppressMessages(library("dplyr", quietly = TRUE)))
suppressWarnings(suppressMessages(library("randomForest", quietly = TRUE)))

var_excl_train <- c("ID")
var_excl_predict <- c("ID", "Classification")
var_excl_outdata <- c("ID", "Classification")
expr_all <- "Classification~."

#Compute ROC curve and AUC giving a list of scores (probs) and a binary true-positive flag (true_Y).
getROC_AUC = function(probs, true_Y){
    probsSort <- sort(probs, decreasing = TRUE, index.return = TRUE)
    val <- unlist(probsSort$x)
    idx <- unlist(probsSort$ix)  

    roc_y <- true_Y[idx];
    stack_x <- cumsum(roc_y == 0)/sum(roc_y == 0)
    stack_y <- cumsum(roc_y == 1)/sum(roc_y == 1)    

    auc <- sum((stack_x[2:length(roc_y)]-stack_x[1:length(roc_y)-1])*stack_y[2:length(roc_y)])
    return(list(stack_x=stack_x, stack_y=stack_y, auc=auc))
}

#Compute scores for leave-half-out cross-validation giving a training data-frame (data).
rf_lhocv <- function(data) {
	inds <- 1:(dim(data)[1])
	ind_excl_train <- which(names(data) %in% var_excl_train)
	ind_excl_predict <- which(names(data) %in% var_excl_predict)
	seqid <- as.character(data$ID)
	term_class <- as.character(data$Classification)
	
	term_class_unique <- unique(term_class)
	
	ind_samp <- c()
	for (i in 1:length(term_class_unique)) {
		class <- term_class_unique[i]
		ind_class <- inds[which(term_class == class)]
		n_class <- length(ind_class)
		n_samp <- max(c(1, floor(n_class)/2))
		ind_class_samp <- sample(ind_class, n_samp, replace=FALSE)
		ind_samp <- c(ind_samp, ind_class_samp)
	}
	
	rf1 <- randomForest(formula = as.formula(expr_all), data=data[-ind_samp,-ind_excl_train], ntree=500, importance=TRUE)
	df_prob1 <- as.data.frame(predict(rf1,data[ind_samp, -ind_excl_predict],type="prob"))
	df_prob1 <- cbind(df_prob1, data.frame(ID = as.character(seqid)[ind_samp], Classification = as.character(term_class)[ind_samp]))
	
	rf2 <- randomForest(formula = as.formula(expr_all), data=data[ind_samp,-ind_excl_train], ntree=500, importance=TRUE)
	df_prob2 <- as.data.frame(predict(rf2,data[-ind_samp, -ind_excl_predict],type="prob"))
	df_prob2 <- cbind(df_prob2, data.frame(ID = as.character(seqid)[-ind_samp], Classification = as.character(term_class)[-ind_samp]))
	
	df_prob <- rbind(df_prob1, df_prob2)
	return(df_prob)
}

#Compute ROC curve and AUC from scores in the leave-half-out cross-validation output (roc_data), for a particular class (class_name).
#This function is a wrapper of the "getROC_AUC" function. 
roc_data_one_class <- function(roc_data, class_name) {
	true_values <- ifelse(roc_data$Classification==class_name,1,0)
	aList <- getROC_AUC(roc_data[[class_name]], true_values)
	
	xx <- unlist(aList$stack_x) #perf@x.values[[1]]
	yy <- unlist(aList$stack_y) #perf@y.values[[1]]
	auc <- unlist(aList$auc) #aperf@y.values[[1]]
	
	lbl <- paste(as.character(class_name), " (AUC=", round(auc,4), ")", sep = "")
	lblrep <- rep(lbl, length(xx))
	
	df <- data.frame(FPR = xx, TPR = yy, LBL = lblrep)
	return(df)
}

#Train a random forest giving a training data-frame (data), and then do leave-half-out cross-validations for all classes involved.
#This function calls "rf_lhocv" and "roc_data_one_class" for leave-half-out cross-validations.
#The output is a list object, including the random forest object, the leave-half-out cross-validation ROC curves as a data-frame with AUCs, and the original data with prediction scores included. 
rf_train <- function(data) {
	pdata <- data
	ind_excl_train <- which(names(pdata) %in% var_excl_train)
	rf <- randomForest(formula = as.formula(expr_all), data=pdata[,-ind_excl_train], ntree=500, importance=TRUE)
	
	prediction_for_roc_curve <- rf_lhocv(pdata)

	classes <- levels(pdata$Classification)
	roc_data <- do.call(rbind, lapply(classes, FUN=function(x){roc_data_one_class(prediction_for_roc_curve,x)})) 
	
	prediction_for_roc_curve <- as.data.frame(prediction_for_roc_curve)
	names(prediction_for_roc_curve) <- c(as.character(levels(pdata$Classification)), "ID", "Classification")
	
	return(list(model=rf, roc=roc_data, validation=prediction_for_roc_curve))
}

#Do a random forest prediction giving a prediction data set (data_in) and a random forest model object (model_in)
rf_predict <- function(data_in, model_in) {
	pdata <- data_in
	rf <- model_in
	
	ind_excl_predict <- which(names(pdata) %in% var_excl_predict)
	ind_excl_outdata <- which(names(pdata) %in% var_excl_outdata)
	pred <- predict(rf, pdata[,-ind_excl_predict],type="prob")
	pred <- as.data.frame(pred)
	names(pred) <- paste("Prob_", names(pred), sep = "")
	
	dfout <- cbind(data.frame(ID = pdata[,1]), pred, pdata[,-ind_excl_outdata])
	
	return(dfout)
}

args <- commandArgs(trailingOnly = TRUE)
raw_data_path <- args[1]
model_in <- args[2]
outdir <- args[3]
train <- as.numeric(args[4])

system(paste("rm -rf", outdir))
system(paste("mkdir", outdir))
model_out <- paste(outdir, "/rf_model.rds", sep="")
roc_data_out <- paste(outdir, "/roc_curve.csv", sep="")
validation_data_out_combined <- paste(outdir, "/validation_data.csv", sep="")
predict_data_out_combined <- paste(outdir, "/prediction_data.csv", sep="")

df <- read.csv(raw_data_path)
names(df)[c(1,2)] <- c("ID", "Classification")

df_class <- as.data.frame(table(as.character(df$Classification)))
n_class <- dim(df_class)[1]
min_data_per_class <- 1
df$Classification <- as.factor(df$Classification)

if (dim(df_class)[2] > 1) {
	min_data_per_class <- min(as.numeric(df_class[,2]))
}

rf_model <- list()
df_combined_validation <- data.frame()
df_pred_combined <- data.frame()

if (train > 0 && n_class <= 10 && n_class > 1 && min_data_per_class >= 5) {
	obj <- rf_train(df)
	df_combined_validation <- merge(obj$validation, df, by = c("ID", "Classification"))
	names(df_combined_validation) <- gsub("\\W", "_", names(df_combined_validation))
	saveRDS(obj, model_out)
	write.csv(obj$roc, roc_data_out, row.names=FALSE)
	write.csv(df_combined_validation, validation_data_out_combined, row.names=FALSE)
} else {
	if (file.exists(model_in)) {
		obj <- readRDS(model_in)
		n_classes <- length(obj$model$classes)
		df_pred <- rf_predict(df, obj$model)
		df_pred_combined <- merge(df_pred[,seq(1,n_classes+1)], df, by = c("ID"))
		names(df_pred_combined) <- gsub("\\W", "_", names(df_pred_combined))
		write.csv(df_pred_combined, predict_data_out_combined, row.names=FALSE)
	}
}
