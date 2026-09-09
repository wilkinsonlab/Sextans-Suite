#!/usr/bin/env bash

args="$@"
echo "arguments: $args"
if [ $# -lt 1 ]
then
	echo 'Arguments: <yarrrml input file> [RML mapper arguments...]'
	exit 1
fi

# the rules file has to be the first argument
rulesfile=$1
shift

# see if there's a classpath argument
CLASSPATHSTR=''
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]
do
	case $1 in
		-classpath|--class-path|-cp)
			CLASSPATHSTR=":$2"
			shift # past argument
			shift # past value
			;;
		*)
			POSITIONAL_ARGS+=("$1") # save positional arg
			if [[ -n $2 ]]
			then
				POSITIONAL_ARGS+=("$2")
				shift # past argument
			fi
			shift # past argument
	esac
done

MAPPERJAR=$(readlink -f /rmlmapper-java/target/rmlmapper-*all.jar)

# Per-invocation, not a fixed shared name -- two concurrent calls to this
# script (e.g. a real transform and a smoke-test run of a freshly-pulled
# mapping) used to race on the same /tmp/rmlmappingfile.ttl regardless of any
# isolation on the /mnt/data side.
# BusyBox's mktemp (this image's /bin/mktemp) doesn't support a suffix after
# the X's -- a trailing ".ttl" here silently made it fail and return an empty
# path (confirmed live: parser.js and rmlmapper both ran "successfully"
# against that empty path, producing empty output with no error surfaced,
# since the Ruby caller discards this script's own stdout/stderr). The
# mapping file's extension isn't actually load-bearing -- it's always passed
# explicitly via --mappingfile, never inferred -- so just drop it.
MAPPINGFILE=$(mktemp /tmp/rmlmappingfile.XXXXXX)
trap 'rm -f "$MAPPINGFILE"' EXIT

echo "mapper arguments: ${POSITIONAL_ARGS[@]}"
cd /mnt/data
/yarrrml-parser/bin/parser.js -i $rulesfile -o "$MAPPINGFILE" -p && \
java --class-path $MAPPERJAR${CLASSPATHSTR} be.ugent.rml.cli.Main --mappingfile "$MAPPINGFILE" ${POSITIONAL_ARGS[@]}
