#!/bin/bash
# Copyright (C) 2017 Vincent Zvikaramba
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

lock_name="android_build_lock"
lock=

function check_if_build_running {

	lock="/var/lock/${lock_name}"

	exec 200>${lock}

	echoTextBlue "Attempting to acquire lock..."

	# loop if we can't get the lock
	while true; do
		flock -n 200
		if [ $? -eq 0 ]; then
			break
		else
			printf "%c" "."
			sleep 10
		fi
	done

	# set the pid
	pid=$$
	echo ${pid} 1>&200

	echoTextBlue "Lock acquired. PID is ${pid}"
}

function save_build_state {
	# save build state in the event a build terminates and another is enqueued
	if [ "x${BUILD_TARGET}" != "x" ] && [ "x${BUILD_VARIANT}" != "x" ]; then
		BUILD_STATE_FILE=$(mktemp -p ${SAVED_BUILD_JOBS_DIR})
		echoTextBlue "Saving build state..."
		# remove and re-add --description arg to properly enclose in quotes
		args=`echo $@ | sed s'/--description[ a-zA-Z0-9\/\.\-]*\ \-/ -/'g`
		args+=" --restored-state"
		[ -n "$JOB_DESCRIPTION" ] && args+=" --description '$JOB_DESCRIPTION'"

		# saves a file with the exact arguments used to launch the build
		echo $0 $args > ${BUILD_STATE_FILE}
		echoTextBlue "Saved args: \n$args"
	fi
}

function restore_saved_build_state {
	if [ -z "${RESTORED_BUILD_STATE}" ] && [ "x${BUILD_TARGET}" != "x" ] && [ "x${BUILD_VARIANT}" != "x" ]; then
		for state_file in `find ${SAVED_BUILD_JOBS_DIR} -type f`; do
			while [ -f "$state_file" ]; do
				echoText "Starting previously terminated build from saved build state.."

				new_build_exec=$(mktemp)

				# prepare to launch the build
				cp $state_file $new_build_exec
				chmod +x $new_build_exec

				echoTextBlue "Launching terminated build with args:\n $(cat $new_build_exec)"
				$new_build_exec && rm $state_file

				# clean up
			        rm $new_build_exec
			done
		done
	fi
}

function fix_build_xml {
	if [ -n "${RESTORED_BUILD_STATE}" ]; then
		rmt_build_xml=$OUTPUT_DIR/../build.xml
		local_build_xml=${BUILD_TEMP}/build.xml

		echoText "Fixing build file on jenkins to reflect success.."
		rsync -av --append-verify -P -e 'ssh -o StrictHostKeyChecking=no' ${SYNC_HOST}:${rmt_build_xml} ${local_build_xml}

		sed -i s/FAILURE/SUCCESS/g ${local_build_xml}

		rsync_cp ${local_build_xml} ${rmt_build_xml}
	fi
}

function clean_target {
	echoText "Removing saved build state info.."
	rm -f ${BUILD_STATE_FILE}
	rmdir --ignore-fail-on-non-empty ${SAVED_BUILD_JOBS_DIR}

	cd ${ANDROID_BUILD_TOP}/
	if [ "x${CLEAN_TARGET_OUT}" != "x" ] && [ ${CLEAN_TARGET_OUT} -eq 1 ]; then
		echoText "Cleaning build dir..."
		if [ "x$BUILD_TARGET" == "xotapackage" ]; then
			make clean
		fi
	fi
}

function remove_temp_dir {
	#start cleaning up
	echoText "Removing temp dir..."
	rm -rf $BUILD_TEMP
}

function remove_build_lock {
	if [ -z "$BUILD_LOCK_REMOVED" ]; then
		echoText "Removing lock..."
		exec 200>&-
		rm ${lock}
		BUILD_LOCK_REMOVED=1
	fi
}

function exit_on_failure {
	echoTextBlue "Running command: $@"
	$@
	exit_error $?
}


function exit_error {
	if [ "x$1" != "x0" ]; then
		echoText "Error encountered, aborting..."
		if [ "x$SILENT" != "x1" ]; then
			END_TIME=$( date +%s )
			buildTime="%0A%0ABuild time: $(format_time ${END_TIME} ${BUILD_START_TIME})"
			totalTime="%0ATotal time: $(format_time ${END_TIME} ${START_TIME})"

			if [ "x$JOB_DESCRIPTION" != "x" ]; then
				textStr="$JOB_DESCRIPTION, build %23${JOB_BUILD_NUMBER}"
			else
				textStr="${distroTxt} ${ver} ${BUILD_TARGET} for the ${DEVICE_NAME}"
			fi

			textStr+=" aborted."

			textStr+="%0A%0AThis build was running on ${USER}@${HOSTNAME}."

			if [ "x${JOB_URL}" != "x" ]; then
				textStr+="%0A%0AYou can see the build log at:"
				textStr+="%0A${JOB_URL}/console"
			fi

			textStr+="${buildTime}${totalTime}"

			if [ "x$PRINT_VIA_PROXY" != "x" ] && [ "x$SYNC_HOST" != "x" ]; then
				timeout -s 9 20 ssh $SYNC_HOST wget \'"https://api.telegram.org/bot${BUILD_TELEGRAM_TOKEN}/sendMessage?chat_id=${BUILD_TELEGRAM_CHATID}&text=$textStr"\' -O - > /dev/null 2>/dev/null
			else

				timeout -s 9 10 wget "https://api.telegram.org/bot${BUILD_TELEGRAM_TOKEN}/sendMessage?chat_id=${BUILD_TELEGRAM_CHATID}&text=$textStr" -O - > /dev/null 2>/dev/null
			fi
		fi
		remove_temp_dir
		remove_build_lock
		exit 1
	fi
}

# PRINTS A FORMATTED HEADER TO POINT OUT WHAT IS BEING DONE TO THE USER
function echoText() {
    echoTextRed "$@"
}

function echoTextRed() {
    echo -e ${RED}
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e "==  ${@}  =="
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e ${RESTORE}
}

function echoTextBlue() {
    echo -e ${BLUE}
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e "==  ${@}  =="
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e ${RESTORE}
}

function echoTextGreen() {
    echo -e ${GREEN}
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e "==  ${@}  =="
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e ${RESTORE}
}

function echoTextBold() {
    echo -e ${BOLD}
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e "==  ${@}  =="
    echo -e "====$( for i in $( seq 1 `echo $@ | wc -c | sed s/[0-9]../100/g` ); do echo -e "=\c"; done )===="
    echo -e ${RESTORE}
}

# FORMATS THE TIME
function format_time() {
    MINS=$(((${1}-${2})/60))
    SECS=$(((${1}-${2})%60))
    if [[ ${MINS} -ge 60 ]]; then
        HOURS=$((${MINS}/60))
        MINS=$((${MINS}%60))
    fi

    if [[ ${HOURS} -eq 1 ]]; then
        TIME_STRING+="1 hour, "
    elif [[ ${HOURS} -ge 2 ]]; then
        TIME_STRING+="${HOURS} hours, "
    fi

    if [[ ${MINS} -eq 1 ]]; then
        TIME_STRING+="1 minute"
    else
        TIME_STRING+="${MINS} minutes"
    fi

    if [[ ${SECS} -eq 1 && -n ${HOURS} ]]; then
        TIME_STRING+=", and 1 second"
    elif [[ ${SECS} -eq 1 && -z ${HOURS} ]]; then
        TIME_STRING+=" and 1 second"
    elif [[ ${SECS} -ne 1 && -n ${HOURS} ]]; then
        TIME_STRING+=", and ${SECS} seconds"
    elif [[ ${SECS} -ne 1 && -z ${HOURS} ]]; then
        TIME_STRING+=" and ${SECS} seconds"
    fi

    echo ${TIME_STRING}
}

# CREATES A NEW LINE IN TERMINAL
function newLine() {
    echo -e ""
}

# PRINTS AN ERROR IN BOLD RED
function reportError() {
    RED="\033[01;31m"
    RESTORE="\033[0m"

    echo -e ""
    echo -e ${RED}"${1}"${RESTORE}
    if [[ -z ${2} ]]; then
        echo -e ""
    fi
}

