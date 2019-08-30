#!/bin/bash

set -e

CONCURRENCY=${CONCURRENCY:-6}
NUM_MASTER_NODES=${NUM_MASTER_NODES:-3}
NUM_DATA_NODES=${NUM_DATA_NODES:-3}

WORDS_FILE="$(dirname $0)/words_alpha.txt"
NUM_LINES="$(wc -l $WORDS_FILE | awk '{print $1}')"

function wait_for_green_cluster() {
  waited="false"
  while ! curl -s -X GET "localhost:9201/_cluster/health?wait_for_status=green" > /dev/null; do
    if [[ "$waited" == "false" ]]; then
      echo -n "waiting for cluster to be ready"
      waited="true"
    else
      echo -n "."
    fi
    sleep 1
  done

  if [[ "$waited" == "true" ]]; then
    echo " done"
  fi
}

function shuffle() {
  SEED="$@"
  shuf --random-source=<(yes "$SEED") $WORDS_FILE
}

function create_index() {
  curl -sS -X PUT http://localhost:9201/example \
  -H 'Content-Type: application/json' \
  -d '
    {
      "settings" : {
          "index" : {
              "number_of_shards" : 3,
              "number_of_replicas" : 2
          }
      }
    }
  '
}

export NUM_LINES
export CONCURRENCY
export NUM_DATA_NODES
export NUM_MASTER_NODES

function load_index() {
  paste -d , \
    <(seq $NUM_LINES) \
    <(shuffle banana) \
    <(shuffle chocolate) \
    <(shuffle pudding) |
  tr -d '\r' |
  parallel --gnu -C , -j $CONCURRENCY -k $'
    data=\'{"id": {1}, "field1": "{2}", "field2": "{2} {3}", "field3": "{2} {3} {4}"}\'
    progress="{1}/'${NUM_LINES}$' ($(({1} * 100 / '${NUM_LINES}$'))%)"
    port=$(( {1} % '${NUM_DATA_NODES} + ${NUM_MASTER_NODES} + 9200 $'))
    echo "$progress" "->" "$data"
    echo -n "$progress" "<-"\ ;
    curl -sS -X PUT http://localhost:${port}/example/test/{1} \
    -H \'Content-Type: application/json\' \
    -d "$data";
    echo
  '
}

wait_for_green_cluster

create_index

load_index
