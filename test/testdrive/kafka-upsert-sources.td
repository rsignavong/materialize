# Copyright Materialize, Inc. and contributors. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.

# This testdrive file uses the deprecated syntax, but is otherwise identical to upsert-kafka-new.td
#
# This file can be deleted when/if we finish the deprecation and perform the removal of the old syntax.

$ set keyschema={
    "type": "record",
    "name": "Key",
    "fields": [
        {"name": "key", "type": "string"}
    ]
  }

$ set schema={
        "type" : "record",
        "name" : "test",
        "fields" : [
            {"name":"f1", "type":"string"},
            {"name":"f2", "type":"long"}
        ]
    }

$ kafka-create-topic topic=avroavro

$ kafka-ingest format=avro topic=avroavro key-format=avro key-schema=${keyschema} schema=${schema} publish=true
{"key": "fish"} {"f1": "fish", "f2": 1000}
{"key": "bird1"} {"f1":"goose", "f2": 1}
{"key": "birdmore"} {"f1":"geese", "f2": 2}
{"key": "mammal1"} {"f1": "moose", "f2": 1}
{"key": "bird1"}
{"key": "birdmore"} {"f1":"geese", "f2": 56}
{"key": "mammalmore"} {"f1": "moose", "f2": 42}
{"key": "mammal1"}
{"key": "mammalmore"} {"f1":"moose", "f2": 2}

> CREATE MATERIALIZED SOURCE avroavro
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-avroavro-${testdrive.seed}'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE UPSERT

> SELECT * from avroavro
key           f1       f2
---------------------------
fish          fish     1000
birdmore      geese    56
mammalmore    moose    2

$ kafka-create-topic topic=textavro

$ kafka-ingest format=avro topic=textavro key-format=bytes key-terminator=: schema=${schema} publish=true
fish: {"f1": "fish", "f2": 1000}
bìrd1: {"f1":"goose", "f2": 1}
birdmore: {"f1":"geese", "f2": 2}
mammal1: {"f1": "moose", "f2": 1}

> CREATE MATERIALIZED SOURCE bytesavro
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-textavro-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA  '${schema}'
  ENVELOPE UPSERT FORMAT BYTES

$ file-append path=data-schema.json
\${schema}

> CREATE MATERIALIZED SOURCE textavro
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-textavro-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA FILE '${testdrive.temp-dir}/data-schema.json'
  ENVELOPE UPSERT FORMAT TEXT

> select * from bytesavro
key0          f1       f2
---------------------------
fish          fish     1000
b\xc3\xacrd1  goose    1
birdmore      geese    2
mammal1       moose    1

$ kafka-ingest format=avro topic=textavro key-format=bytes key-terminator=: schema=${schema} publish=true
bìrd1:
birdmore: {"f1":"geese", "f2": 56}
mämmalmore: {"f1": "moose", "f2": 42}
mammal1:

> select * from textavro
key0          f1       f2
---------------------------
fish          fish     1000
birdmore      geese    56
mämmalmore    moose    42

$ kafka-create-topic topic=textbytes partitions=1

$ kafka-ingest format=bytes topic=textbytes key-format=bytes key-terminator=:
fish:fish
bìrd1:goose
bírdmore:geese
mammal1:moose
bìrd1:

> CREATE MATERIALIZED SOURCE texttext
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-textbytes-${testdrive.seed}'
    FORMAT TEXT ENVELOPE UPSERT

> CREATE MATERIALIZED SOURCE textbytes
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-textbytes-${testdrive.seed}'
  FORMAT BYTES ENVELOPE UPSERT FORMAT TEXT

> CREATE MATERIALIZED SOURCE bytesbytes
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-textbytes-${testdrive.seed}'
  FORMAT BYTES ENVELOPE UPSERT

> CREATE MATERIALIZED SOURCE bytestext
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-textbytes-${testdrive.seed}'
  FORMAT TEXT ENVELOPE UPSERT FORMAT BYTES

> select * from texttext
key0          text  mz_offset
-----------------------------
fish          fish  1
bírdmore      geese 3
mammal1       moose 4

$ kafka-ingest format=bytes topic=textbytes key-format=bytes key-terminator=:
bírdmore:géese
mammalmore:moose
mammal1:
mammal1:mouse

> select * from textbytes
key0          data             mz_offset
----------------------------------------
fish          fish             1
bírdmore      g\xc3\xa9ese     6
mammal1       mouse            9
mammalmore    moose            7

$ kafka-ingest format=bytes topic=textbytes key-format=bytes key-terminator=:
mammalmore:herd

> select * from bytesbytes
key0             data             mz_offset
----------------------------------------
fish             fish             1
b\xc3\xadrdmore  g\xc3\xa9ese     6
mammal1          mouse            9
mammalmore       herd             10

$ kafka-ingest format=bytes topic=textbytes key-format=bytes key-terminator=:
bìrd1:
fish:

> select * from bytestext
key0             text             mz_offset
----------------------------------------
b\xc3\xadrdmore  géese            6
mammal1          mouse            9
mammalmore       herd             10

$ file-append path=test.proto
syntax = "proto3";

message Test {
    string f = 1;
}

$ protobuf-compile-descriptors inputs=test.proto output=test.pb

$ kafka-create-topic topic=textproto partitions=1

> CREATE MATERIALIZED SOURCE textproto
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-textproto-${testdrive.seed}'
  FORMAT PROTOBUF MESSAGE '.Test' USING SCHEMA FILE '${testdrive.temp-dir}/test.pb'
  ENVELOPE UPSERT FORMAT TEXT

> CREATE MATERIALIZED SOURCE bytesproto
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-textproto-${testdrive.seed}'
  FORMAT PROTOBUF MESSAGE '.Test' USING SCHEMA FILE '${testdrive.temp-dir}/test.pb'
  ENVELOPE UPSERT FORMAT BYTES

$ kafka-ingest topic=textproto
  format=protobuf descriptor-file=test.pb message=Test
  key-format=bytes key-terminator=:
fish:{"f": "one"}
bìrd1:{"f": "two"}
birdmore: {}

> SELECT * FROM bytesproto
fish         one 1
b\xc3\xacrd1 two 2
birdmore     "" 3

> SELECT * FROM textproto
fish      one  1
bìrd1     two  2
birdmore  ""   3

$ kafka-ingest topic=textproto
  format=protobuf descriptor-file=test.pb message=Test
  key-format=bytes key-terminator=:
mammal1: {"f": "three"}
bìrd1:
birdmore: {"f": "four"}
mämmalmore: {"f": "five"}
bìrd1: {"f": "six"}
mammal1:
mammalmore: {"f": "seven"}

> SELECT * FROM bytesproto
fish              one    1
birdmore          four   6
m\xc3\xa4mmalmore five   7
b\xc3\xacrd1      six    8
mammalmore        seven  10

> SELECT * FROM textproto
fish        one    1
birdmore    four   6
mämmalmore  five   7
bìrd1       six    8
mammalmore  seven  10

$ kafka-create-topic topic=nullkey partitions=1

# A null key should result in an error decoding that row but not a panic
$ kafka-ingest format=bytes topic=nullkey key-format=bytes key-terminator=:
bird1:goose
:geese
mammal1:moose
bird1:
birdmore:geese
mammalmore:moose
mammal1:

> CREATE MATERIALIZED SOURCE nullkey
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-nullkey-${testdrive.seed}'
  FORMAT TEXT ENVELOPE UPSERT FORMAT TEXT

> select * from nullkey
key0          text  mz_offset
-----------------------------
birdmore      geese 5
mammalmore    moose 6

$ kafka-create-topic topic=realtimeavroavro partitions=1

# test multi-field avro key
$ set keyschema2={
    "type": "record",
    "name": "Key2",
    "fields": [
        {"name": "f3", "type": ["null", "string"]},
        {"name": "f1", "type": ["null", "string"]}
    ]
  }

$ kafka-ingest format=avro topic=realtimeavroavro key-format=avro key-schema=${keyschema2} schema=${schema} publish=true
{"f3": {"string": "fire"}, "f1": {"string": "yang"}} {"f1": "dog", "f2": 42}
{"f3": null, "f1": {"string": "yin"}} {"f1": "sheep", "f2": 53}
{"f3": {"string": "water"}, "f1": null} {"f1":"plesiosaur", "f2": 224}
{"f3": {"string": "earth"}, "f1": {"string": "dao"}} {"f1": "turtle", "f2": 34}
{"f3": null, "f1": {"string": "yin"}} {"f1": "sheep", "f2": 54}
{"f3": {"string": "earth"}, "f1": {"string": "dao"}} {"f1": "snake", "f2": 68}
{"f3": {"string": "water"}, "f1": null} {"f1": "crocodile", "f2": 7}
{"f3": {"string": "earth"}, "f1":{"string": "dao"}}

> CREATE SOURCE realtimeavroavro (f3, f4, f1, f2)
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-realtimeavroavro-${testdrive.seed}'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE UPSERT FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'

> CREATE MATERIALIZED VIEW realtimeavroavro_view as SELECT * from realtimeavroavro;

> select f3, f4, f1, f2 from realtimeavroavro_view
f3        f4      f1             f2
-----------------------------------
fire      yang    dog            42
<null>    yin     sheep          54
water     <null>  crocodile      7

# Ensure that Upsert sources work with `start_offset`
> CREATE MATERIALIZED SOURCE realtimeavroavro_ff
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-realtimeavroavro-${testdrive.seed}'
  WITH (start_offset=1)
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE UPSERT FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'

> SELECT * FROM realtimeavroavro_ff
f3        f1        f1           f2
-----------------------------------
<null>    yin       sheep        54
water     <null>    crocodile    7

# ensure that having deletion on a key that never existed does not break anything
$ kafka-ingest format=avro topic=realtimeavroavro key-format=avro key-schema=${keyschema2} schema=${schema} publish=true
{"f3": {"string": "fire"}, "f1": {"string": "yin"}}
{"f3": {"string": "air"}, "f1":{"string": "qi"}} {"f1": "pigeon", "f2": 10}
{"f3": {"string": "air"}, "f1":{"string": "qi"}} {"f1": "owl", "f2": 15}
{"f3": {"string": "earth"}, "f1": {"string": "dao"}} {"f1": "rhinoceros", "f2": 211}
{"f3": {"string": "air"}, "f1":{"string": "qi"}} {"f1": "chicken", "f2": 47}
{"f3": null, "f1":{"string": "yin"}}
{"f3": null, "f1":{"string": "yin"}} {"f1":"dog", "f2": 243}
{"f3": {"string": "water"}, "f1": null}

> select * from realtimeavroavro_view
f3         f4          f1             f2
-----------------------------------------
fire       yang        dog            42
air        qi          chicken        47
<null>     yin         dog            243
earth      dao         rhinoceros     211

$ kafka-create-topic topic=realtimefilteravro

$ set keyschema3={
    "type": "record",
    "name": "Key3",
    "fields": [
        {"name": "k1", "type": ["null", "string"]},
        {"name": "k2", "type": ["null", "long"]}
    ]
  }

$ set schema2={
    "type": "record",
    "name": "test2",
    "fields": [
        {"name": "f1", "type": ["null", "string"]},
        {"name": "f2", "type": ["null", "long"]}
    ]
  }

$ kafka-ingest format=avro topic=realtimefilteravro key-format=avro key-schema=${keyschema3} schema=${schema2} publish=true
{"k1": null, "k2": {"long": 2}} {"f1": {"string": "date"}, "f2": {"long": 5}}
{"k1": {"string": "épicerie"}, "k2": {"long": 10}} {"f1": {"string": "melon"}, "f2": {"long": 2}}
{"k1": {"string": "boucherie"}, "k2": {"long": 5}} {"f1": {"string": "apple"}, "f2": {"long": 7}}
{"k1": {"string": "boulangerie"}, "k2": null} {"f1":{"string": "date"}, "f2": {"long": 10}}
{"k1": {"string": "épicerie"}, "k2": {"long": 10}} {"f1": {"string": "pear"}, "f2": {"long": 2}}
{"k1": null, "k2": {"long": 2}} {"f1": {"string": "date"}, "f2": null}
{"k1": {"string": "boulangerie"}, "k2": null} {"f1":null, "f2": {"long": 10}}
{"k1": {"string": "boucherie"}, "k2": {"long": 5}} {"f1": {"string": "apple"}, "f2": {"long": 3}}

> CREATE SOURCE realtimefilteravro
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC
  'testdrive-realtimefilteravro-${testdrive.seed}'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE UPSERT FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'

# filter on key only
> CREATE MATERIALIZED VIEW filterforkey AS
  SELECT f1 FROM realtimefilteravro WHERE k1='épicerie';

> SELECT * from filterforkey
f1
----
pear

# filter on value only
> CREATE MATERIALIZED VIEW filterforvalue AS
  SELECT f2 FROM realtimefilteravro WHERE f1='date';

> SELECT * from filterforvalue
f2
-------
<null>

# filter with a predicate containing key + value
> CREATE MATERIALIZED VIEW filterforkeyvalue AS
  SELECT f1, f2 FROM realtimefilteravro WHERE k2+f2=12;

> SELECT * from filterforkeyvalue
f1   f2
-------
pear 2

# filter on both a predicate containing a key and a predicate containing a value
> CREATE MATERIALIZED VIEW keyfiltervaluefilter AS
  SELECT k1, k2 FROM realtimefilteravro WHERE k2 > 5 AND f2 < 5

> SELECT * from keyfiltervaluefilter
k1       k2
-----------
épicerie 10

# add records that match the filter
# make sure that rows that differ on unneeded key columns are treated as separate
$ kafka-ingest format=avro topic=realtimefilteravro key-format=avro key-schema=${keyschema3} schema=${schema2} publish=true
{"k1": {"string": "librairie"}, "k2": {"long": 10}} {"f1":null, "f2": {"long": 2}}
{"k1": null, "k2": null} {"f1": {"string": "date"}, "f2": {"long": 5}}
{"k1": {"string": "épicerie"}, "k2": {"long": 6}} {"f1": {"string": "pear"}, "f2": null}
{"k1": {"string": "bureau"}, "k2": {"long": 6}} {"f1": {"string": "grape"}, "f2": {"long": 7}}

> SELECT * from filterforkey
f1
----
pear
pear

> SELECT * from filterforvalue
f2
-------
<null>
5

> SELECT * from filterforkeyvalue
f1     f2
---------
pear   2
<null> 2

> SELECT * from keyfiltervaluefilter
k1        k2
-----------
épicerie  10
librairie 10

# update records so that they don't match the filter
$ kafka-ingest format=avro topic=realtimefilteravro key-format=avro key-schema=${keyschema3} schema=${schema2} publish=true
{"k1": {"string": "librairie"}, "k2": {"long": 10}} {"f1":null, "f2": {"long": 6}}
{"k1": null, "k2": null} {"f1": {"string": "grape"}, "f2": {"long": 5}}

> SELECT * from filterforvalue
f2
-------
<null>

> SELECT * from filterforkeyvalue
f1     f2
---------
pear   2

> SELECT * from keyfiltervaluefilter
k1        k2
-----------
épicerie  10

# update records so that they do match the filter
$ kafka-ingest format=avro topic=realtimefilteravro key-format=avro key-schema=${keyschema3} schema=${schema2} publish=true
{"k1": {"string": "librairie"}, "k2": {"long": 10}} {"f1":{"string": "melon"}, "f2": {"long": 2}}
{"k1": null, "k2": null} {"f1": {"string": "date"}, "f2": {"long": 12}}

> SELECT * from filterforvalue
f2
-------
<null>
12

> SELECT * from filterforkeyvalue
f1     f2
---------
pear   2
melon  2

> SELECT * from keyfiltervaluefilter
k1        k2
-----------
épicerie  10
librairie 10

# delete records
$ kafka-ingest format=avro topic=realtimefilteravro key-format=avro key-schema=${keyschema3} schema=${schema2} publish=true
{"k1": {"string": "boucherie"}, "k2": {"long": 5}}
{"k1": {"string": "épicerie"}, "k2": {"long": 10}}
{"k1": {"string": "boulangerie"}, "k2": null}
{"k1": null, "k2": {"long": 2}}

> SELECT * from filterforkey
f1
----
pear

> SELECT * from filterforvalue
f2
-------
12

> SELECT * from filterforkeyvalue
f1     f2
---------
melon  2

> SELECT * from keyfiltervaluefilter
k1        k2
-----------
librairie 10

# Declare a key constraint (PRIMARY KEY NOT ENFORCED)

$ set schema={
    "type": "record",
    "name": "row",
    "fields": [
      {"name": "a", "type": "long"},
      {"name": "b", "type": "long"}
    ]
  }

$ kafka-create-topic topic=input-pkne-flat

$ kafka-ingest format=avro topic=input-pkne-flat schema=${schema}
{"a": 1, "b": 11}
{"a": 2, "b": 22}
{"a": 3, "b": 33}

> CREATE MATERIALIZED SOURCE input_pkne_flat_a (PRIMARY KEY (a) NOT ENFORCED)
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-input-pkne-flat-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}' ENVELOPE NONE

> CREATE MATERIALIZED SOURCE input_pkne_flat_b (PRIMARY KEY (b) NOT ENFORCED)
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-input-pkne-flat-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}' ENVELOPE NONE

> CREATE MATERIALIZED SOURCE input_pkne_flat_ab (PRIMARY KEY (a, b) NOT ENFORCED)
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-input-pkne-flat-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}' ENVELOPE NONE

> CREATE SINK input_pkne_flat_a_sink FROM input_pkne_flat_a
  INTO KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'input-pkne-flat-a-sink'
  KEY (a)
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}' ENVELOPE UPSERT

> CREATE SINK input_pkne_flat_b_sink FROM input_pkne_flat_b
  INTO KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'input-pkne-flat-b-sink'
  KEY (b)
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}' ENVELOPE UPSERT

> CREATE SINK input_pkne_flat_ab_sink FROM input_pkne_flat_ab
  INTO KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'input-pkne-flat-ab-sink'
  KEY (a, b)
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}' ENVELOPE UPSERT

$ kafka-verify format=avro sink=materialize.public.input_pkne_flat_a_sink sort-messages=true
{"a": 1} {"a": 1, "b": 11}
{"a": 2} {"a": 2, "b": 22}
{"a": 3} {"a": 3, "b": 33}

$ kafka-verify format=avro sink=materialize.public.input_pkne_flat_b_sink sort-messages=true
{"b": 11} {"a": 1, "b": 11}
{"b": 22} {"a": 2, "b": 22}
{"b": 33} {"a": 3, "b": 33}

$ kafka-verify format=avro sink=materialize.public.input_pkne_flat_ab_sink sort-messages=true
{"a": 1, "b": 11} {"a": 1, "b": 11}
{"a": 2, "b": 22} {"a": 2, "b": 22}
{"a": 3, "b": 33} {"a": 3, "b": 33}

$ set keyschema={
    "type": "record",
    "name": "Key",
    "fields": [
        {"name": "key1", "type": "string"},
        {"name": "key2", "type": "long"}
    ]
  }

$ kafka-create-topic topic=input-pkne-key

$ kafka-ingest topic=input-pkne-key key-format=avro key-schema=${keyschema} format=avro schema=${schema}
{"key1": "a", "key2": 1} {"a": 1, "b": 11}
{"key1": "b", "key2": 2} {"a": 2, "b": 22}
{"key1": "c", "key2": 3} {"a": 3, "b": 33}

> CREATE MATERIALIZED SOURCE input_pkne_key (PRIMARY KEY (key1) NOT ENFORCED)
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-input-pkne-key-${testdrive.seed}'
  WITH (ignore_source_keys=true)
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE UPSERT FORMAT AVRO USING SCHEMA '${keyschema}'

> CREATE SINK input_pkne_key_sink FROM input_pkne_key
  INTO KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'input-pkne-key-sink'
  KEY (key1)
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}' ENVELOPE UPSERT

$ kafka-verify format=avro sink=materialize.public.input_pkne_key_sink sort-messages=true
{"key1": "a"} {"key1": "a", "key2": 1, "a": 1, "b": 11}
{"key1": "b"} {"key1": "b", "key2": 2, "a": 2, "b": 22}
{"key1": "c"} {"key1": "c", "key2": 3, "a": 3, "b": 33}

! CREATE MATERIALIZED SOURCE avroavro (PRIMARY KEY (f1) NOT ENFORCED)
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-avroavro-${testdrive.seed}'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE UPSERT
contains:Key constraint (f1) conflicts with existing key (key)

! CREATE MATERIALIZED SOURCE avroavro (PRIMARY KEY (unknown) NOT ENFORCED)
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-avroavro-${testdrive.seed}'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
  ENVELOPE UPSERT
contains:No such column in source key constraint: unknown

! CREATE MATERIALIZED SOURCE avroavro (PRIMARY KEY (f1, f1) NOT ENFORCED)
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-avroavro-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}' ENVELOPE NONE
contains:Repeated column name in source key constraint: f1

$ set ambiguous-schema={
        "type" : "record",
        "name" : "test",
        "fields" : [
            {"name":"f1", "type":"string"},
            {"name":"f2", "type":"long"},
            {"name":"f1", "type":"long"}
        ]
    }

! CREATE MATERIALIZED SOURCE input_pkne (f1, f2, f1, PRIMARY KEY (f1) NOT ENFORCED)
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-avroavro-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${ambiguous-schema}' ENVELOPE NONE
contains:Ambiguous column in source key constraint: f1
