

#' Train a MOA classifier/regressor/recommendation engine on a datastream
#'
#' Train a MOA classifier/regressor/recommendation engine on a datastream
#'
#' @param model an object of class \code{MOA_model}, as returned by \code{\link{MOA_classifier}}, 
#' \code{\link{MOA_regressor}}, \code{\link{MOA_recommender}}
#' @param ... other parameters passed on to the methods
#' @return An object of class MOA_trainedmodel which is returned by the methods for the specific model.  
#' See \code{\link{trainMOA.MOA_classifier}}, \code{\link{trainMOA.MOA_regressor}}, \code{\link{trainMOA.MOA_recommender}}
#' @seealso \code{\link{trainMOA.MOA_classifier}}, \code{\link{trainMOA.MOA_regressor}}, \code{\link{trainMOA.MOA_recommender}}
#' @export 
trainMOA <- function(model, ...){
  UseMethod("trainMOA")
} 


#' Train a MOA classifier (e.g. a HoeffdingTree) on a datastream
#'
#' Train a MOA classifier (e.g. a HoeffdingTree) on a datastream
#'
#' @param model an object of class \code{MOA_model}, as returned by \code{\link{MOA_classifier}}, e.g.
#' a \code{\link{HoeffdingTree}}
#' @param formula a symbolic description of the model to be fit.
#' @param data an object of class \code{\link{datastream}} set up e.g. with \code{\link{datastream_file}}, 
#' \code{\link{datastream_dataframe}}, \code{\link{datastream_matrix}}, \code{\link{datastream_ffdf}} or your own datastream.
#' @param subset an optional vector specifying a subset of observations to be used in the fitting process.
#' @param na.action a function which indicates what should happen when the data contain \code{NA}s. 
#' See \code{\link{model.frame}} for details. Defaults to \code{\link{na.exclude}}.
#' @param transFUN a function which is used after obtaining \code{chunksize} number of rows 
#' from the \code{data} datastream before applying \code{\link{model.frame}}. Useful if you want to 
#' change the results \code{get_points} on the datastream 
#' (e.g. for making sure the factor levels are the same in each chunk of processing, some data cleaning, ...). 
#' Defaults to \code{\link{identity}}.
#' @param chunksize the number of rows to obtain from the \code{data} datastream in one chunk of model processing.
#' Defaults to 1000. Can be used to speed up things according to the backbone architecture of
#' the datastream.
#' @param reset logical indicating to reset the \code{MOA_classifier} so that it forgets what it 
#' already has learned. Defaults to TRUE.
#' @param trace logical, indicating to show information on how many datastream chunks are already processed
#' as a \code{message}.
#' @param options a names list of further options. Currently not used.
#' @param ... other arguments, currently not used yet
#' @return An object of class MOA_trainedmodel which is a list with elements
#' \itemize{
#' \item{model: the updated supplied \code{model} object of class \code{MOA_classifier}}
#' \item{call: the matched call}
#' \item{na.action: the value of na.action}
#' \item{terms: the \code{terms} in the model}
#' \item{transFUN: the transFUN argument}
#' }
#' @seealso \code{\link{MOA_classifier}}, \code{\link{datastream_file}}, \code{\link{datastream_dataframe}}, 
#' \code{\link{datastream_matrix}}, \code{\link{datastream_ffdf}}, \code{\link{datastream}},
#' \code{\link{predict.MOA_trainedmodel}}
#' @export 
#' @examples
#' hdt <- HoeffdingTree(numericEstimator = "GaussianNumericAttributeClassObserver")
#' hdt
#' data(iris)
#' iris <- factorise(iris)
#' irisdatastream <- datastream_dataframe(data=iris)
#' irisdatastream$get_points(3)
#' 
#' mymodel <- trainMOA(model = hdt, Species ~ Sepal.Length + Sepal.Width + Petal.Length, 
#'  data = irisdatastream, chunksize = 10)
#' mymodel$model
#' irisdatastream$reset()
#' mymodel <- trainMOA(model = hdt, 
#'  Species ~ Sepal.Length + Sepal.Width + Petal.Length + Petal.Length^2, 
#'  data = irisdatastream, chunksize = 10, reset=TRUE, trace=TRUE)
#' mymodel$model
trainMOA.MOA_classifier <- function(model, formula, data, subset, na.action=na.exclude, transFUN=identity, chunksize=1000, reset=TRUE, 
                     trace=FALSE, options = list(maxruntime = +Inf), ...){
  startat <- Sys.time()
  mc <- match.call()
  mf <- mc[c(1L, match(c("formula", "data", "subset", "na.action"), names(mc), 0L))]
  mf[[1L]] <- as.name("model.frame")
  mf[[3L]] <- as.name("datachunk")
  mf$drop.unused.levels <- FALSE
  setmodelcontext <- function(model, data, response){
    # build the weka instances structure
    atts <- MOAattributes(data=data)
    allinstances <- .jnew("weka.core.Instances", "data", atts$columnattributes, 0L, class.loader=.rJava.class.loader)
    ## Set the response data to predict    
    .jcall(allinstances, "V", "setClass", attribute(atts, response)$attribute)
    ## Prepare for usage
    .jcall(model$moamodel, "V", "setModelContext", .jnew("moa.core.InstancesHeader", allinstances, class.loader=.rJava.class.loader))
    .jcall(model$moamodel, "V", "prepareForUse")
    list(model = model, allinstances = allinstances)
  }
  trainchunk <- function(model, traindata, allinstances){
    ## Levels go from 0-nlevels in MOA, while in R from 1:nlevels
    traindata <- as.train(traindata)
    ## Loop over the data and train
    for(j in 1:nrow(traindata)){
      oneinstance <- .jnew("weka/core/DenseInstance", 1.0, .jarray(as.double(traindata[j, ])), class.loader=.rJava.class.loader)  
      .jcall(oneinstance, "V", "setDataset", allinstances)
      oneinstance <- .jcast(oneinstance, "weka/core/Instance")
      .jcall(model$moamodel, "V", "trainOnInstance", oneinstance)
    }
    model
  }
  if(reset){
    .jcall(model$moamodel, "V", "resetLearning") 
  }  
  terms <- NULL
  i <- 1
  while(!data$isfinished()){
    if(trace){
      message(sprintf("%s Running chunk %s: instances %s:%s", Sys.time(), i, (i*chunksize)-chunksize, i*chunksize))
    }
    ### Get data of chunk and extract the model.frame
    datachunk <- data$get_points(chunksize)
    if(is.null(datachunk)){
      break
    }
    datachunk <- transFUN(datachunk)  
    traindata <- eval(mf)      
    if(i == 1){
      terms <- terms(traindata)
      ### Set up the data structure in MOA (levels, columns, ...)
      ct <- setmodelcontext(model=model, data=traindata, response=all.vars(formula)[1])
      model <- ct$model    
    }
    ### Learn the model
    model <- trainchunk(model = model, traindata = traindata, allinstances = ct$allinstances)  
    i <- i + 1
    
    if("maxruntime" %in% names(options)){
      if(difftime(Sys.time(), startat, units = "secs") > options$maxruntime){
        break
      }
    }
  }
  if(is.null(terms)){
    terms <- terms(formula)
  }
  out <- list()
  out$model <- model
  out$call <- mc
  out$na.action <- attr(mf, "na.action")
  out$terms <- terms
  out$transFUN <- transFUN
  class(out) <- c("MOA_trainedmodel", "MOA_classifier")
  out
} 



#' Train a MOA regressor (e.g. a FIMTDD) on a datastream
#'
#' Train a MOA regressor (e.g. a FIMTDD) on a datastream
#'
#' @param model an object of class \code{MOA_model}, as returned by \code{\link{MOA_regressor}}, e.g.
#' a \code{\link{FIMTDD}}
#' @param formula a symbolic description of the model to be fit.
#' @param data an object of class \code{\link{datastream}} set up e.g. with \code{\link{datastream_file}}, 
#' \code{\link{datastream_dataframe}}, \code{\link{datastream_matrix}}, \code{\link{datastream_ffdf}} or your own datastream.
#' @param subset an optional vector specifying a subset of observations to be used in the fitting process.
#' @param na.action a function which indicates what should happen when the data contain \code{NA}s. 
#' See \code{\link{model.frame}} for details. Defaults to \code{\link{na.exclude}}.
#' @param transFUN a function which is used after obtaining \code{chunksize} number of rows 
#' from the \code{data} datastream before applying \code{\link{model.frame}}. Useful if you want to 
#' change the results \code{get_points} on the datastream 
#' (e.g. for making sure the factor levels are the same in each chunk of processing, some data cleaning, ...). 
#' Defaults to \code{\link{identity}}.
#' @param chunksize the number of rows to obtain from the \code{data} datastream in one chunk of model processing.
#' Defaults to 1000. Can be used to speed up things according to the backbone architecture of
#' the datastream.
#' @param reset logical indicating to reset the \code{MOA_regressor} so that it forgets what it 
#' already has learned. Defaults to TRUE.
#' @param trace logical, indicating to show information on how many datastream chunks are already processed
#' as a \code{message}.
#' @param options a names list of further options. Currently not used.
#' @param ... other arguments, currently not used yet
#' @return An object of class MOA_trainedmodel which is a list with elements
#' \itemize{
#' \item{model: the updated supplied \code{model} object of class \code{MOA_regressor}}
#' \item{call: the matched call}
#' \item{na.action: the value of na.action}
#' \item{terms: the \code{terms} in the model}
#' \item{transFUN: the transFUN argument}
#' }
#' @seealso \code{\link{MOA_regressor}}, \code{\link{datastream_file}}, \code{\link{datastream_dataframe}}, 
#' \code{\link{datastream_matrix}}, \code{\link{datastream_ffdf}}, \code{\link{datastream}},
#' \code{\link{predict.MOA_trainedmodel}}
#' @export 
#' @examples
#' mymodel <- MOA_regressor(model = "FIMTDD")
#' mymodel
#' data(iris)
#' iris <- factorise(iris)
#' irisdatastream <- datastream_dataframe(data=iris)
#' irisdatastream$get_points(3)
#' ## Train the model
#' mytrainedmodel <- trainMOA(model = mymodel, 
#'  Sepal.Length ~ Petal.Length + Species, data = irisdatastream)
#' mytrainedmodel$model
#' irisdatastream$reset()
#' mytrainedmodel <- trainMOA(model = mytrainedmodel$model, 
#'  Sepal.Length ~ Petal.Length + Species, data = irisdatastream, 
#'  chunksize = 10, reset=FALSE, trace=TRUE)
#' mytrainedmodel$model 
trainMOA.MOA_regressor <- function(model, formula, data, subset, na.action=na.exclude, transFUN=identity, chunksize=1000, reset=TRUE, 
                                   trace=FALSE, options = list(maxruntime = +Inf), ...){
  startat <- Sys.time()
  mc <- match.call()
  mf <- mc[c(1L, match(c("formula", "data", "subset", "na.action"), names(mc), 0L))]
  mf[[1L]] <- as.name("model.frame")
  mf[[3L]] <- as.name("datachunk")
  mf$drop.unused.levels <- FALSE
  setmodelcontext <- function(model, data, response){
    # build the weka instances structure
    atts <- MOAattributes(data=data)
    allinstances <- .jnew("weka.core.Instances", "data", atts$columnattributes, 0L, class.loader=.rJava.class.loader)
    ## Set the response data to predict    
    .jcall(allinstances, "V", "setClass", attribute(atts, response)$attribute)
    ## Prepare for usage
    .jcall(model$moamodel, "V", "setModelContext", .jnew("moa.core.InstancesHeader", allinstances, class.loader=.rJava.class.loader))
    .jcall(model$moamodel, "V", "prepareForUse")
    list(model = model, allinstances = allinstances)
  }
  trainchunk <- function(model, traindata, allinstances){
    ## Levels go from 0-nlevels in MOA, while in R from 1:nlevels
    traindata <- as.train(traindata)
    ## Loop over the data and train
    for(j in 1:nrow(traindata)){
      oneinstance <- .jnew("weka/core/DenseInstance", 1.0, .jarray(as.double(traindata[j, ])), class.loader=.rJava.class.loader)  
      .jcall(oneinstance, "V", "setDataset", allinstances)
      oneinstance <- .jcast(oneinstance, "weka/core/Instance")
      .jcall(model$moamodel, "V", "trainOnInstance", oneinstance)
    }
    model
  }
  if(reset){
    .jcall(model$moamodel, "V", "resetLearning") 
  }  
  terms <- NULL
  i <- 1
  while(!data$isfinished()){
    if(trace){
      message(sprintf("%s Running chunk %s: instances %s:%s", Sys.time(), i, (i*chunksize)-chunksize, i*chunksize))
    }
    ### Get data of chunk and extract the model.frame
    datachunk <- data$get_points(chunksize)
    if(is.null(datachunk)){
      break
    }
    datachunk <- transFUN(datachunk)  
    traindata <- eval(mf)      
    if(i == 1){
      terms <- terms(traindata)
      ### Set up the data structure in MOA (levels, columns, ...)
      ct <- setmodelcontext(model=model, data=traindata, response=all.vars(formula)[1])
      model <- ct$model    
    }
    ### Learn the model
    model <- trainchunk(model = model, traindata = traindata, allinstances = ct$allinstances)  
    i <- i + 1
    
    if("maxruntime" %in% names(options)){
      if(difftime(Sys.time(), startat, units = "secs") > options$maxruntime){
        break
      }
    }
  }
  if(is.null(terms)){
    terms <- terms(formula)
  }
  out <- list()
  out$model <- model
  out$call <- mc
  out$na.action <- attr(mf, "na.action")
  out$terms <- terms
  out$transFUN <- transFUN
  class(out) <- c("MOA_trainedmodel", "MOA_regressor")
  out
}



#' Train a MOA recommender (e.g. a BRISMFPredictor) on a datastream
#'
#' Train a MOA recommender (e.g. a BRISMFPredictor) on a datastream
#'
#' @param model an object of class \code{MOA_model}, as returned by \code{\link{MOA_recommender}}, e.g.
#' a \code{\link{BRISMFPredictor}}
#' @param formula a symbolic description of the model to be fit. This should be of the form rating ~ userid + itemid, in that sequence.
#' These should be columns in the \code{data}, where userid and itemid are integers and rating is numeric.
#' @param data an object of class \code{\link{datastream}} set up e.g. with \code{\link{datastream_file}}, 
#' \code{\link{datastream_dataframe}}, \code{\link{datastream_matrix}}, \code{\link{datastream_ffdf}} or your own datastream.
#' @param subset an optional vector specifying a subset of observations to be used in the fitting process.
#' @param na.action a function which indicates what should happen when the data contain \code{NA}s. 
#' See \code{\link{model.frame}} for details. Defaults to \code{\link{na.exclude}}.
#' @param transFUN a function which is used after obtaining \code{chunksize} number of rows 
#' from the \code{data} datastream before applying \code{\link{model.frame}}. Useful if you want to 
#' change the results \code{get_points} on the datastream 
#' (e.g. for making sure the factor levels are the same in each chunk of processing, some data cleaning, ...). 
#' Defaults to \code{\link{identity}}.
#' @param chunksize the number of rows to obtain from the \code{data} datastream in one chunk of model processing.
#' Defaults to 1000. Can be used to speed up things according to the backbone architecture of
#' the datastream.
#' @param trace logical, indicating to show information on how many datastream chunks are already processed
#' as a \code{message}.
#' @param options a names list of further options. Currently not used.
#' @param ... other arguments, currently not used yet
#' @return An object of class MOA_trainedmodel which is a list with elements
#' \itemize{
#' \item{model: the updated supplied \code{model} object of class \code{MOA_recommender}}
#' \item{call: the matched call}
#' \item{na.action: the value of na.action}
#' \item{terms: the \code{terms} in the model}
#' \item{transFUN: the transFUN argument}
#' }
#' @seealso \code{\link{MOA_recommender}}, \code{\link{datastream_file}}, \code{\link{datastream_dataframe}}, 
#' \code{\link{datastream_matrix}}, \code{\link{datastream_ffdf}}, \code{\link{datastream}},
#' \code{\link{predict.MOA_trainedmodel}}
#' @export 
#' @examples
#' require(recommenderlab)
#' data(MovieLense)
#' x <- getData.frame(MovieLense)
#' x$itemid <- as.integer(as.factor(x$item))
#' x$userid <- as.integer(as.factor(x$user))
#' x$rating <- as.numeric(x$rating)
#' x <- head(x, 5000)
#' 
#' movielensestream <- datastream_dataframe(data=x)
#' movielensestream$get_points(3)
#' 
#' ctrl <- MOAoptions(model = "BRISMFPredictor", features = 10)
#' brism <- BRISMFPredictor(control=ctrl)
#' mymodel <- trainMOA(model = brism, rating ~ userid + itemid, 
#'  data = movielensestream, chunksize = 1000, trace=TRUE)
#' summary(mymodel$model)
trainMOA.MOA_recommender <- function(model, formula, data, subset, na.action=na.exclude, transFUN=identity, chunksize=1000, 
                                    trace=FALSE, options = list(maxruntime = +Inf), ...){
  startat <- Sys.time()
  mc <- match.call()
  mf <- mc[c(1L, match(c("formula", "data", "subset", "na.action"), names(mc), 0L))]
  mf[[1L]] <- as.name("model.frame")
  mf[[3L]] <- as.name("datachunk")
  mf$drop.unused.levels <- FALSE
  setratings <- function(modeldata, traindata){
    stopifnot(is.numeric(traindata[, 1]))
    stopifnot(is.integer(traindata[, 2]))
    stopifnot(is.integer(traindata[, 3]))
    
    setRating <- function(object, user, item, value){
      invisible(sapply(seq_along(user), FUN=function(i){
        .jcall(object, "V", "setRating", user[i], item[i], value[i])    
      }))
      invisible(object)
    }
    setRating(object = modeldata, user = traindata[, 2], item = traindata[, 3], value = traindata[, 1])
  }  
  .jcall(model$moamodel, "V", "prepareForUse")
  terms <- NULL
  i <- 1
  mdata <- model$moamodel$getData()
  while(!data$isfinished()){
    if(trace){
      message(sprintf("%s Running chunk %s: instances %s:%s", Sys.time(), i, (i*chunksize)-chunksize, i*chunksize))
    }
    ### Get data of chunk and extract the model.frame
    datachunk <- data$get_points(chunksize)
    if(is.null(datachunk)){
      break
    }
    datachunk <- transFUN(datachunk)  
    traindata <- eval(mf)      
    if(i == 1){
      terms <- terms(traindata)      
    }
    ### Learn the model
    setratings(modeldata = mdata, traindata = traindata)  
    i <- i + 1
    
    if("maxruntime" %in% names(options)){
      if(difftime(Sys.time(), startat, units = "secs") > options$maxruntime){
        break
      }
    }
  }
  if(is.null(terms)){
    terms <- terms(formula)
  }
  out <- list()
  out$model <- model
  out$call <- mc
  out$na.action <- attr(mf, "na.action")
  out$terms <- terms
  out$transFUN <- transFUN
  class(out) <- c("MOA_trainedmodel", "MOA_recommender")
  out
} 


#' Predict using a MOA classifier, MOA regressor or MOA recommender on a new dataset
#'
#' Predict using a MOA classifier, MOA regressor or MOA recommender on a new dataset. \\
#' Make sure the new dataset has the same structure
#' and the same levels as \code{get_points} returns on the datastream which was used in \code{trainMOA}
#'
#' @param object an object of class \code{MOA_trainedmodel}, as returned by \code{\link{trainMOA}}
#' @param newdata a data.frame with the same structure and the same levels as used in \code{trainMOA} for MOA classifier, MOA regressor,
#' a data.frame with at least the user/item columns which were used in \code{\link{trainMOA}} when training
#' the MOA recommendation engine
#' @param type a character string, either 'response' or 'votes'
#' @param transFUN a function which is used on \code{newdata} 
#' before applying \code{\link{model.frame}}. 
#' Useful if you want to change the results \code{get_points} on the datastream 
#' (e.g. for making sure the factor levels are the same in each chunk of processing, some data cleaning, ...). 
#' Defaults to \code{transFUN} available in \code{object}.
#' @param na.action passed on to model.frame when constructing the model.matrix from \code{newdata}. Defaults to \code{na.fail}.
#' @param ... other arguments, currently not used yet
#' @return A matrix of votes or a vector with the predicted class for MOA classifier or MOA regressor.
#' A 
#' @export 
#' @S3method predict MOA_trainedmodel
#' @seealso \code{\link{trainMOA}}
#' @examples
#' ## Hoeffdingtree
#' hdt <- HoeffdingTree(numericEstimator = "GaussianNumericAttributeClassObserver")
#' data(iris)
#' ## Make a training set
#' iris <- factorise(iris)
#' traintest <- list()
#' traintest$trainidx <- sample(nrow(iris), size=nrow(iris)/2)
#' traintest$trainingset <- iris[traintest$trainidx, ]
#' traintest$testset <- iris[-traintest$trainidx, ]
#' irisdatastream <- datastream_dataframe(data=traintest$trainingset)
#' ## Train the model
#' hdtreetrained <- trainMOA(model = hdt, 
#'  Species ~ Sepal.Length + Sepal.Width + Petal.Length + Petal.Width, 
#'  data = irisdatastream)
#' 
#' ## Score the model on the holdoutset
#' scores <- predict(hdtreetrained, 
#'    newdata=traintest$testset[, c("Sepal.Length","Sepal.Width","Petal.Length","Petal.Width")], 
#'    type="response")
#' str(scores)
#' table(scores, traintest$testset$Species)
#' scores <- predict(hdtreetrained, newdata=traintest$testset, type="votes")
#' head(scores)
#' 
#' ## Prediction based on recommendation engine
#' require(recommenderlab)
#' data(MovieLense)
#' x <- getData.frame(MovieLense)
#' x$itemid <- as.integer(as.factor(x$item))
#' x$userid <- as.integer(as.factor(x$user))
#' x$rating <- as.numeric(x$rating)
#' x <- head(x, 2000)
#' 
#' movielensestream <- datastream_dataframe(data=x)
#' movielensestream$get_points(3)
#' 
#' ctrl <- MOAoptions(model = "BRISMFPredictor", features = 10)
#' brism <- BRISMFPredictor(control=ctrl)
#' mymodel <- trainMOA(model = brism, rating ~ userid + itemid, 
#'  data = movielensestream, chunksize = 1000, trace=TRUE)
#' 
#' overview <- summary(mymodel$model)
#' str(overview)
#' predict(mymodel, head(x, 10), type = "response")
#' 
#' x <- expand.grid(userid=overview$users[1:10], itemid=overview$items)
#' predict(mymodel, x, type = "response")
predict.MOA_trainedmodel <- function(object, newdata, type="response", transFUN=object$transFUN, na.action = na.fail, ...){ 
  if(inherits(object, "MOA_recommender")){
    ## Apply transFUN and model.frame
    newdata <- transFUN(newdata)
    Terms <- delete.response(object$terms)
    newdata <- model.frame(Terms, newdata, na.action = na.action)
    newdata$rating <- apply(newdata, MARGIN=1, FUN=function(x){
      .jcall(object$model$moamodel, returnSig = "D", "predictRating", x[1], x[2])
    })
    return(newdata)
  }else{
    modelready <- TRUE
    try(modelready <- .jcall(object$model$moamodel, "Z", "trainingHasStarted"), silent=TRUE)
    if(!modelready){
      stop("Model is not trained yet")
    }
    ## Apply transFUN and model.frame
    newdata <- transFUN(newdata)
    Terms <- delete.response(object$terms)
    newdata <- model.frame(Terms, newdata, na.action = na.action)
    
    object <- object$model
    columnnames <- fields(object)
    if(inherits(object, "MOA_classifier")){
      newdata[[columnnames$response]] <- factor(NA, levels = columnnames$responselevels) ## Needs the response data to create DenseInstance but this is unknown  
    }else if(inherits(object, "MOA_regressor")){
      newdata[[columnnames$response]] <- as.numeric(NA) ## Needs the response data to create DenseInstance but this is unknown  
    }
    
    newdata <- as.train(newdata[, columnnames$attribute.names, drop = FALSE])
    
    atts <- MOAattributes(data=newdata)
    allinstances <- .jnew("weka.core.Instances", "data", atts$columnattributes, 0L, class.loader=.rJava.class.loader)
    .jcall(allinstances, "V", "setClass", attribute(atts, columnnames$response)$attribute)
    
    if(inherits(object, "MOA_classifier")){
      scores <- matrix(nrow = nrow(newdata), ncol = length(columnnames$responselevels))
    }else if(inherits(object, "MOA_regressor")){
      scores <- matrix(nrow = nrow(newdata), ncol = 1)
    }  
    for(j in 1:nrow(newdata)){
      oneinstance <- .jnew("weka/core/DenseInstance", 1.0, .jarray(as.double(newdata[j, ])), class.loader=.rJava.class.loader)  
      .jcall(oneinstance, "V", "setDataset", allinstances)
      oneinstance <- .jcast(oneinstance, "weka/core/Instance")
      if(inherits(object, "MOA_classifier")){
        onescore <- object$moamodel$getVotesForInstance(oneinstance)
        nrofclasses <- length(columnnames$responselevels)
        if(length(onescore) < nrofclasses){
          ## Fix for https://groups.google.com/forum/#!topic/moa-users/xkDG6p15FIM
          onescore <- c(onescore, rep(0L, nrofclasses - length(onescore)))
        }
        scores[j, ] <- onescore
      }else if(inherits(object, "MOA_regressor")){
        scores[j, ] <- object$moamodel$getVotesForInstance(oneinstance)
      }        
    }
    if(inherits(object, "MOA_classifier")){
      if(type == "votes"){
        colnames(scores) <- columnnames$responselevels
        return(scores)
      }else if(type == "response"){
        scores <- apply(scores, MARGIN=1, which.max) 
        scores <- sapply(scores, FUN=function(x) columnnames$responselevels[x])
        return(scores)
      }  
    }else if(inherits(object, "MOA_regressor")){
      return(scores[, 1])
    }  
  }   
}

