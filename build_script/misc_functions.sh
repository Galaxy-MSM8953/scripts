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

function clean_out {
    if [ "${CLEAN_TARGET_OUT}" -eq 1 ]; then
        echoText "Cleaning build dir..."
        rm -rf ${BUILD_TOP}/out
    fi
}

function remove_temp_dir {
    #start cleaning up
    echoText "Removing temp dir..."
    rm -rf $BUILD_TEMP
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
            queuedTime="%0AEnqueued time: $(format_time ${BUILD_START_TIME} ${START_TIME})"
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

            textStr+="${buildTime}${queuedTime}${totalTime}"

            timeout -s 9 10 wget "https://api.telegram.org/bot${BUILD_TELEGRAM_TOKEN}/sendMessage?chat_id=${BUILD_TELEGRAM_CHATID}&text=$textStr" -O - > /dev/null 2>/dev/null

        fi
        remove_temp_dir
        remove_build_lock
        exit 1
    fi
}
