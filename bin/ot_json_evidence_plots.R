#!/usr/bin/env Rscript

suppressMessages( library(optparse))

args <- parse_args(OptionParser(option_list= list(
  make_option(
    c("-i", "--input"),
    help="Input tsv file"
  ), 
  make_option(
    c("-l", "--logfoldchange"),
    help="logfoldchange file"
  ), 
  make_option(
    c("-p", "--pvalue"),
    help="pvalues files"
  ),
  make_option(
    c("-o", "--output"),
    help="Where to save the output files"
  )
)))

## check file exist function
check_file_exists <- function( filename ) {
  if( !file.exists( filename ) ) {
    stop( paste(
      "Cannot find:",
      filename
    ) )
  }
}

check_file_exists(args$input)
check_file_exists(args$logfoldchange)
check_file_exists(args$pvalue)

# extract dated file name
file<-gsub("[_].*","",basename(args$input))

## study references
exp_evidence<-noquote(readLines(args$input))
exp_count<-table(exp_evidence)

logfold<-readLines(args$logfoldchange)
pvals<-readLines(args$pvalue)

tiff(filename=paste0(args$output,"/",file,"_pval_lfc.tiff"),width=1000,height=1000,res=150)
par(mfrow = c(2,1))
hist(as.numeric(logfold), breaks=50, main=paste0(file), xlab="Log fold change")
hist(as.numeric(pvals), breaks=50 ,main="", xlab="p-val")
dev.off()

# plot of number of evidences per study
tiff(filename=paste0(args$output,"/",file,"_evidences.tiff"),width=1000,height=1000,res=100)
barplot(exp_count, las=2,  horiz=FALSE, cex.names=0.2, col="blue",ylab="evidences", main=file)
dev.off()

# plot of sudies that have highest number of evidences
tiff(filename=paste0(args$output,"/",file,"_topEvidences.tiff"),width=1000,height=1000,res=100)
par(mar=c(10,12,4,2))
barplot(tail(sort(exp_count,decreasing=FALSE)),las=2, main=paste0("Top_studies_",file),col="cornflowerblue",horiz =TRUE)
dev.off()
