#!/usr/bin/env python
# encoding: utf-8

#import wordninja
#import editdistance
import argparse
from urllib import parse
import re
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--dataset', default='Wiki10-31K', type=str, help='dataset')
args = parser.parse_args()


# read label text
with open('./{}/mlc2seq/label_vocab.txt'.format(args.dataset), 'r', encoding='utf-8') as fin:
    label_list = [line.strip().split('\t')[1] for line in fin]
#print(len(label_list))

# output label text
with open('./{}/label_text.txt'.format(args.dataset), 'w', encoding='utf-8') as fout:
    for label in label_list:
       # label2 = label.encode('utf-8')
       # sys.stdout.buffer.write(label_enc)
        # replace url character
        # https://stackoverflow.com/questions/8136788/decode-escaped-characters-in-url
        label_v1 = parse.unquote(label)

        # remove some punctuation with whitespace
        label_v2 = re.sub(r"[,.:;\\''/@#?!\[\]&$_*]+", ' ', label_v1).strip()
        if len(label_v2) == 0:
            label_v2 = '<unk>'
        #print(label_v2)
        label_v2 = label_v2 + '\n'
        sys.stdout.buffer.write(label_v2.encode('utf-8'))
        fout.write('{}\n'.format(label_v2))
