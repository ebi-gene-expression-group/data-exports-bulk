#!/usr/bin/env Rscript

# Author: Suhaib Mohammed

suppressMessages( library(RUVSeq) )
suppressMessages( library(funr) )

script_path<-funr::get_script_path()

## loading generic functions 
source(paste(script_path,"generic_functions.R",sep="/"))

# Get commandline arguments.
args <- commandArgs( TRUE )

if( length( args ) != 3 ) {
  stop( "\nUsage:\n\tscript.R <output_path> <study_type1> <study_type2>\n\n" )
}

# Get the transcripts expression filename from the arguments.
study_type1 <- args[ 1 ]
study_type2 <- args[ 2 ]
output_path <- args[ 3 ]

##load expressioinSet objects 
load(paste(output_path,study_type1, paste0("set.RUVg_", study_type1, ".Rdata"), sep="/"))
norm.1<-normCounts(set.RUVg)
rm(set.RUVg)

load(paste(output_path,study_type2, paste0("set.RUVg_", study_type2, ".Rdata"), sep="/"))
norm.2<-normCounts(set.RUVg)

## meging two matrices (a,b) of different dimensions. 
## order ensemble-ids from matrix a is maintained, 
## and new ensemble-ids from b are concatenated below
## this function also transforms "NA" -> 0
## more info in generic_funcitons.R
all.norm<-mergeX(norm.1, norm.2)

x<-sapply(strsplit(colnames(all.norm), split="_"),"[",3)
names <- colnames(all.norm)

# experiment detailed expression values
expNames <- t(as.data.frame(sapply(names, function(x) strsplit(x, "_"))))
expNormData <- all.norm
colnames(expNormData) <- paste(expNames[,1], expNames[,3], sep="_")

# summarisation (aggregation) of expression values by median across tissue/cell types
expData <-expNormData
tissue.names<-sapply(strsplit(colnames(expData),split="_"),"[",2)
colnames(expData) <- tissue.names
expData <- t(apply(expData, 1, function(x) tapply(x, colnames(expData), median)))

png(file = paste(output_path,"heatmap.png",sep="/"), width = 2000, height = 2000, res=180)
plot_heatmap(expData, name="normalised")
dev.off()

png(file = paste(output_path, paste0("Distribution_Summary_NormCounts_all_",study_type1,"_",study_type2,".png"), sep="/"), width = 700, height = 700, res=100)
hist(log(expData),freq=FALSE, col="cornflowerblue", breaks =30, xlab="log normalised counts", main = "")
dev.off()

write.table(expData, file=paste(output_path,paste0("exp_summary_NormCounts_genes_all_",study_type1,"_",study_type2,".txt"), sep="/"),quote=FALSE, col.names=NA, sep="\t")

