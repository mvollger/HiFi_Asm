import os
import numpy as np
import pandas as pd
import json
import random
import tempfile

#
# setup the env for each execution
# this allows you to specify a file that contains all the modules you want to have loaded
# for your pipeline.
# the file should be called modules.cfg and should exist in the same locaiton as the snakemake file
#
SNAKEMAKE_DIR = os.path.dirname(workflow.snakefile)
shell.executable("/bin/bash")
shell.prefix("source %s/env.cfg; set -eo pipefail; " % SNAKEMAKE_DIR)

#
# A little complicated to find the temp dir
# temp dir is a place programs can put temp files. 
# You will never have to change or think about anything here
#
SSD_TMP_DIR = "/data/scratch/ssd"
if "TMPDIR" in os.environ:
    TMPDIR = os.environ['TMPDIR']
elif "TMPDIR" in config:
    TMPDIR = config['TMPDIR']
elif os.path.exists(SSD_TMP_DIR):
    TMPDIR = SSD_TMP_DIR
else:
    TMPDIR = tempfile.gettempdir()


configfile: "aln.yaml"

THREADS=4
if("threads" in config):
	THREADS = config["threads"]


SAMPLES = list(config.keys())
if("threads" in SAMPLES): SAMPLES.remove("threads")
print("Samples: ", SAMPLES, file=sys.stderr) 

# samples that have BACs
REF_SMS = []
FOFN_SMS = []
READ_SMS = {}
CMD_SMS = []
for SM in SAMPLES:
	if("ref" in config[SM]):
		REF_SMS.append(SM)
	if("fofn" in config[SM] ):
		FOFN_SMS.append(SM)
		READ_SMS[SM] = [line.strip() for line in open(config[SM]["fofn"]).readlines()]

print("FOFNs: ", FOFN_SMS, file=sys.stderr)

def get_cmd(wildcards):
	SM = str(wildcards.SM)
	if("cmd" in config[SM]):	
		return(config[SM]["cmd"])
	return("minimap2 -t 8 --secondary=no -a --eqx -x map-pb -m 1000")

def get_flag(wildcards):
	SM = str(wildcards.SM)
	if("flag" in config[SM]):	
		return(config[SM]["flag"])
	return("2308")

def get_read(wildcards):
	SM = str(wildcards.SM)
	ID = int(str(wildcards.ID))
	return(READ_SMS[SM][ID])

def get_ref(wildcards):
	SM = str(wildcards.SM)
	return(config[SM]["ref"])

def get_bams(wildcards):
	SM = str(wildcards.SM)
	IDS = list(range(len(READ_SMS[SM])))
	bams = expand("temp/" + SM + "_{ID}.bam", ID=IDS)
	return(bams)

wildcard_constraints:
	ID="\d+"

localrules: all

rule all:
	input:
		bam = expand("results/{SM}.bam", SM=SAMPLES),
		bai = expand("results/{SM}.bam.bai", SM=SAMPLES),

rule align:
	input:
		ref=get_ref,
		reads=get_read,
	output:
		bam=temp("temp/{SM}_{ID}.bam"),
	params:
		cmd = get_cmd,
		flag = get_flag,
	log:
		o = "logs/align_{SM}_{ID}.o",
		e = "logs/align_{SM}_{ID}.e"
	benchmark:
		"logs/align_{SM}_{ID}.b"
	resources:
		mem = 8,
		smem = 4
	threads: THREADS
	shell:"""
SAM_TMP="{TMPDIR}/temp_{wildcards.SM}_{wildcards.ID}"
rm -f $SAM_TMP*
{params.cmd} \
	{input.ref} {input.reads} | samtools view -F {params.flag} -u - | samtools sort -T $SAM_TMP -m {resources.smem}G -@ {threads} - > {output.bam}
"""


rule merge:
	input:
		bams = get_bams, 
	output:
		bam="results/{SM}.bam",
	log:
		o = "logs/merge_{SM}.o",
		e = "logs/merge_{SM}.e"
	benchmark:
		"logs/merge_{SM}.b"
	resources:
		mem = 1
	threads: min(12, 2*THREADS)
	shell:"""
samtools merge -@ {threads} {output.bam} {input.bams}
"""


rule index:
	input:
		bam="results/{SM}.bam",
	output:
		bai="results/{SM}.bam.bai",
	log:
		o = "logs/index_{SM}.o",
		e = "logs/index_{SM}.e"
	benchmark:
		"logs/index_{SM}.b"
	resources:
		mem = 16
	threads: 1
	shell:"""
samtools index {input.bam}
"""



