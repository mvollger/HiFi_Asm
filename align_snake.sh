#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/env.cfg



#
# snakemake paramenters
#
snakefile=$DIR/align.smk
jobNum=250
waitTime=60 # this really needs to be 60 on our cluster :(
retry=0 # numer of times to retry the pipeline if it failes
# I allow a retry becuase sometimes even the really long waittime is not enough,
# and the files are actaully there

#
# QSUB parameters, these are only the defualts, they can be changed with params.sge_opts
# Allow snakemake to make directories, I think it slows things down when I done with "waitTime"
#
logDir=logs
mkdir -p $logDir

#
# run snakemake
#
snakemake -p \
        -s $snakefile \
        --drmaa " -P eichlerlab \
                -q eichler-short.q \
                -l h_rt=24:00:00  \
                -l mfree={resources.mem}G \
				-pe serial {threads} \
                -V -cwd \
				-e {log.e} -o {log.o} \
                -S /bin/bash" \
        --jobs $jobNum \
        --latency-wait $waitTime \
        --restart-times $retry  \
         $@

# generate report 
#snakemake -s $snakefile --report racon_report.html

