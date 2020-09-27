#!/bin/bash
#Executes the X-Transformer algorithm with all the required steps to produce the .npz file containing the predictions for the given dataset.
#NOTE: this script was developed exclusively for the MESINESP task due to its non-English characteristics.
#
#HOW TO RUN:
# ./run_X-Transformer_mesinesp.sh DATASET_FOLDER_NAME bert-base-multilingual-cased

echo '>>>> BEGIN <<<<'

#set parameters
DATASET=$1
MODEL=$2

ALGO=5
SEED=0

GPUS=0,1,2,3
CPUS=0,1,2,3,4,5,6,7,8,9,10,11,12,13,14

DEPTH=6
TRAIN_BATCH_SIZE=4
EVAL_BATCH_SIZE=4
LOG_INTERVAL=1000
EVAL_INTERVAL=20000
NUM_TRAIN_EPOCHS=4.0
LEARNING_RATE=5e-5
WARMUP_RATE=0.1

#File vectorizer. Converts to libsvm format
echo '>>>> CONVERTING TO LIBSVM <<<<'
taskset -c ${CPUS} python -m datasets.new_preprocess_tfidf -i datasets/${DATASET}

#label embedding and creating feature files
echo '>>>> LABEL EMBEDING AND DATA MATRICES <<<<'
cd datasets
python proc_data.py --dataset ${DATASET}

python label_embedding.py -d ${DATASET} -e pifa
cd ..

# indexer
echo '>>>> INDEXER <<<<'
OUTPUT_DIR=save_models/${DATASET}/pifa-a${ALGO}-s${SEED}
mkdir -p $OUTPUT_DIR/indexer

python -m xbert.indexer \
	-i datasets/${DATASET}/L.pifa.npz \
	-o ${OUTPUT_DIR}/indexer \
	-d ${DEPTH} --algo ${ALGO} --seed ${SEED} --max-iter 20

# preprocess data_bin for neural matcher
echo '>>>> PREPROCESS <<<<'
OUTPUT_DIR=save_models/${DATASET}/pifa-a${ALGO}-s${SEED}
mkdir -p $OUTPUT_DIR/indexer
mkdir -p $OUTPUT_DIR/data-bin-cased

python -m xbert.preprocess \
	-m bert \
	-n bert-base-multilingual-cased \
	-i datasets/${DATASET} \
	-c ${OUTPUT_DIR}/indexer/code.npz \
	-o ${OUTPUT_DIR}/data-bin-cased

# neural matcher
echo '>>>> MATCHER TRAINING <<<<'
OUTPUT_DIR=save_models/${DATASET}/pifa-a${ALGO}-s${SEED}
mkdir -p $OUTPUT_DIR/matcher/$MODEL
 
CUDA_VISIBLE_DEVICES=${GPUS} nohup python -m torch.distributed.launch -m --nproc_per_node 4 -m xbert.matcher.transformer \
	-m bert \
	-n ${MODEL} \
	-i ${OUTPUT_DIR}/data-bin-cased/data_dict.pt \
	-o ${OUTPUT_DIR}/matcher/${MODEL} \
	--do_train \
	--do_eval \
	--per_gpu_eval_batch_size ${TRAIN_BATCH_SIZE} \
	--per_gpu_train_batch_size ${EVAL_BATCH_SIZE} \
	--gradient_accumulation_steps 2 \
	--learning_rate ${LEARNING_RATE} \
	--num_train_epochs ${NUM_TRAIN_EPOCHS} \
	--logging_steps ${LOG_INTERVAL} \
	--save_steps ${EVAL_INTERVAL} \
	--only_topk 20 \
	--overwrite_output_dir \
	> ${DATASET}_${MODEL}_pifa_a${ALGO}-s${SEED}_log
	
# ranker (default: matcher=hierarchical linear)
echo '>>>> RANKER TRAINING <<<<'
OUTPUT_DIR=save_models/${DATASET}/pifa-a${ALGO}-s${SEED}
mkdir -p $OUTPUT_DIR/ranker_$MODEL

taskset -c ${CPUS} python -m xbert.ranker train \
  -x1 datasets/${DATASET}/X.trn.npz \
  -x2 ${OUTPUT_DIR}/matcher/${MODEL}/trn_embeddings.npy \
  -y datasets/${DATASET}/Y.trn.npz \
  -z ${OUTPUT_DIR}/matcher/${MODEL}/C_trn_pred.npz \
  -c ${OUTPUT_DIR}/indexer/code.npz \
  -o ${OUTPUT_DIR}/ranker_${MODEL} -t 0.01 \
  -f 0 -ns 0 --mode ranker

echo '>>>> RANKER PREDICTION <<<<'
taskset -c ${CPUS} python -m xbert.ranker predict \
  -m ${OUTPUT_DIR}/ranker_${MODEL} \
  -o ${OUTPUT_DIR}/ranker_${MODEL}/tst.pred.npz \
  -x1 datasets/${DATASET}/X.tst.npz \
  -x2 ${OUTPUT_DIR}/matcher/${MODEL}/tst_embeddings.npy \
  -y datasets/${DATASET}/Y.tst.npz \
  -z ${OUTPUT_DIR}/matcher/${MODEL}/C_tst_pred.npz -t noop \
  -f 0 -k 20

echo '>>>> END <<<<'