#!/bin/bash

set -o pipefail

BOILERMAKER_ARGS="$@"

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$PWD" ; cd `dirname "$0"` ; echo "$PWD")

cd "$SCRIPT_DIR/.."
source bin/common-include.sh

REPO_LIST=()
BRANCH=master
DEFAULT_REPO_ROOT=$(cd "$SCRIPT_DIR/../.." ; echo "$PWD")
REPO_ROOT="$DEFAULT_REPO_ROOT"
REPO_DECL_FILE="$PWD/repos"
DEFAULT_SKELETON_TYPE=framework
SKELETON_TYPE=$DEFAULT_SKELETON_TYPE

showHelp()
{
	define HELP <<HELP
$SCRIPT_NAME

	Freshens the files in a repo by rebuilding boilerplate files and copying
	the latest versions of static assets.
	
Usage:

	$SCRIPT_NAME --repo <repo-list>
	
Required arguments:

	--repo (-r) <repo-list>
	
		Specifies one or more repos to freshen. When specifying multiple repos
		in the list, spaces are used to separate the names.

Optional arguments:

	--type (-t) <skeleton-type>
	
		Specifies the skeleton type to use for populating the repo.
		
		Currently supported skeletons are:
		
$SKELETON_LIST

		If the skeleton type is not explicitly specified, the value
		"$DEFAULT_SKELETON_TYPE" will be used by default.

	--root <directory>

		Specifies <directory> as the location in which the repo(s) can be
		found. If --root is not specified, the script will use:
	
		$(formatPathForDisplay "$DEFAULT_REPO_ROOT")
	
	--decl <location>

		Specifies the location of the repo declaration file(s) to use.
		
		<location> may be a directory containing multiple repo declaration
		files, or it may be a file containing the declaration for a single
		repo. If <location> is a file, then the <repo-list> passed to the 
		--repo (or -r) argument must contain only one repo.

		A repo declaration is a Mockingbird MBML (*.xml) file containing 
		metadata describing a given repo. By convention, these files have the
		same name as the repo itself. (A declaration file for this repo would
		be named "$( cd "$SCRIPT_DIR/.." ; echo `basename $PWD` ).xml", for example.)
		
		If --decl is not specified, the script will search for an appropriate 
		file as needed within:
		
		$(formatPathForDisplay "$PWD/repos")

	--branch (-b) <branch>
	
		As a safety measure, the script will fail if all repos involved in an
		operation are not on the same branch at the time of execution. 

		By default, the branch is assumed to be master. Using this argument
		overrides that and uses <branch> insead.
		
 	--force (-f)
 	
 		By default, if a destination repo contains a file that would be 
 		overwritten, user confirmation is requested first. Using this flag
 		causes files to be overwritten without confirmation.

Help

	This documentation is displayed when supplying the --help (or -help, -h,
	or -?) argument.

	Note that when this script displays help documentation, all other
	command line arguments are ignored and no other actions are performed.

HELP
	printf "$HELP" | less
}

while [[ $1 ]]; do
	case $1 in
	--repo|-r)
 		while [[ $2 ]]; do
 			case $2 in
 			-*)
 				break
 				;;
 				
 			*)
				REPO_LIST+=($2)
				shift
				;;	
 			esac
 		done
 		;;

	--root)
		if [[ $2 ]]; then
 			REPO_ROOT=$2
 			shift
 		fi
		;;

	--decl)
 		while [[ $2 ]]; do
 			case $2 in
 			-*)
 				break
 				;;
 				
 			*)
				REPO_DECL_FILE="$2"
		 		shift
				;;	
 			esac
 		done
		;;

	--type|-t)
		while [[ $2 ]]; do
 			case $2 in
 			-*)
 				break
 				;;
 				
 			*)
				SKELETON_TYPE="$2"
		 		shift
				;;	
 			esac
 		done
 		;;

	--force|-f)
		FORCE_MODE=1
		;;
	
	--branch|-b)
		if [[ $2 ]]; then
 			BRANCH=$2
 			shift
 		fi
 		;;
	
	--help|-help|-h|-\?)
		SHOW_HELP=1
		;;
	esac
	shift
done

export REPO_ROOT

if [[ $SHOW_HELP == 1 ]]; then
	showHelp
	exit 1
fi

if [[ ${#REPO_LIST[@]} < 1 ]]; then
	exitWithErrorSuggestHelp "Must specify one or more repos to freshen using the --repo (or -r) argument"
fi

if [[ ${#REPO_LIST[@]} > 1 && ! -d "$REPO_DECL_FILE" ]]; then
	exitWithErrorSuggestHelp "When the --decl <location> is a file, only one repo may be specified. This does not appear to be a directory: $REPO_DECL_FILE"
fi

if [[ $FORCE_MODE ]]; then
	CP_ARGS="f"
else
	CP_ARGS="i"
fi

processBoilerplateFile()
{
	pushd "$SCRIPT_DIR" > /dev/null

	executeCommand "./boilermaker.sh $BOILERMAKER_ARGS --type $SKELETON_TYPE --file \"$1\""

	popd > /dev/null
}

COPY_ARGS=""
if [[ $FORCE_MODE ]]; then
	COPY_ARGS="--force $COPY_ARGS"
fi
if [[ ${#REPO_LIST[@]} ]]; then
	COPY_ARGS="--repo ${REPO_LIST[@]} $COPY_ARGS"
fi
if [[ $BRANCH ]]; then
	COPY_ARGS="--branch $BRANCH $COPY_ARGS"
fi
if [[ $REPO_ROOT ]]; then
	COPY_ARGS="--root $REPO_ROOT $COPY_ARGS"
fi

processStandardFile()
{
	pushd "$SCRIPT_DIR" > /dev/null
	
	OUTPUT_FILE=`stripBoilerplateDirectory "$1"`

	./copyToCleanroomRepos.sh "$1" "$OUTPUT_FILE" $COPY_ARGS
	if [[ $? != 0 ]]; then
		exitWithError "Failed to copy $1 to $OUTPUT_FILE"
	fi
	
	popd > /dev/null
}

processSubpath()
{
	for f in $1/*; do
		if [[ -d "$f" ]]; then
			processSubpath "$f"
		elif [[ $(echo "$f" | grep -c "\.boilerplate\$") > 0 ]]; then
			processBoilerplateFile "$f"
		else
			
			processStandardFile "$f"
		fi
	done
}

processSubpath boilerplate/common
processSubpath boilerplate/$SKELETON_TYPE

for r in ${REPO_LIST[@]}; do
	MASTER_XML="$PWD/include/repos.xml"
	REPO_DECL_BASE=`basename $REPO_DECL_FILE`
	if [[ -d "$REPO_DECL_FILE" ]]; then
		REPO_XML="$REPO_DECL_FILE/${r}.xml"
	elif [[ $REPO_DECL_BASE != "${r}.xml" ]]; then
		REPO_XML="$REPO_DECL_FILE/${r}.xml"
	else
		REPO_XML="$REPO_DECL_FILE"
	fi
	XML_DEST="$REPO_ROOT/${r}/BuildControl/."
	if [[ ! -f "$REPO_XML" ]]; then
		echo "error: Didn't find expected $r repo description file: $REPO_XML"
		continue
	fi
	if [[ ! -d "$XML_DEST" ]]; then
		echo "error: Didn't find expected $r repo directory: $XML_DEST"
		continue
	fi
	
	echo "Copying $MASTER_XML to $r/BuildControl"
	executeCommand "cp -${CP_ARGS} \"$MASTER_XML\" \"$XML_DEST\""
	
	echo "Copying $REPO_XML to $r/BuildControl"
	executeCommand "cp -${CP_ARGS} \"$REPO_XML\" \"$XML_DEST\""
done
