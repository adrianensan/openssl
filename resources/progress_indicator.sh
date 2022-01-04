#!/bin/false

OUTPUT="/dev/null"

function progress_cancel {
  if [ "${OUTPUT}" == "/dev/tty" ]; then
    printf "\nCancelled\n"
    return
  fi
  kill $!
  wait $! &>/dev/null
  printf "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b~~~[CANCEL]~~~     \n"
  trap - EXIT
  exit
}

function progress_show {
  if [ "${OUTPUT}" == "/dev/tty" ]; then
    printf "...\n"
    return
  fi

  trap progress_cancel EXIT
  printf "${1} -- "

  function progress_show_blocking {
    CHARACTERS="     '^*#@!?<>.,~-&+=_/1234567890qwertyuiopasdfghjklzxcvbnm"
    CURRENT_STRING="      "
    counter=5

    printf "            "
    while true; do
      old_string="$CURRENT_STRING"
      CURRENT_STRING=""
      for i in {0..5}; do
        chance=$(($RANDOM % 100))
        if [ $chance -lt 20 ]; then
          index=$(($RANDOM % 55))
          CURRENT_STRING="${CURRENT_STRING}${CHARACTERS:$index:1}"
        else
          CURRENT_STRING="${CURRENT_STRING}${old_string:$i:1}"
        fi
      done

      counter=$(($((counter + 1)) % 10))  
      start_char="---"
      end_char="---"
      if [ $counter -lt 1 ]; then
        start_char="--<"
        end_char=">--"
      elif [ $counter -lt 2 ]; then
        start_char="-<<"
        end_char=">>-"
      elif [ $counter -lt 3 ]; then
        start_char="<<<"
        end_char=">>>"
      elif [ $counter -lt 4 ]; then
        start_char="<<-"
        end_char="->>"
      elif [ $counter -lt 5 ]; then
        start_char="<--"
        end_char="-->"
      fi

      printf "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b$start_char[$CURRENT_STRING]$end_char "
      sleep 0.075
    done
  }

  progress_show_blocking &
}

function progress_end { exit_status=$1
  if [ -z "${exit_status}" ]; then
    exit_status=$?
  fi
  if [[ "${OUTPUT}" == "/dev/tty" ]]; then
    if [[ "${exit_status}" != "0" ]]; then
      exit -1
    fi
    return
  fi
  kill $!
  wait $! &>/dev/null
  trap - EXIT
  if [[ "${exit_status}" == "0" ]]; then
    printf "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b~~~[--OK--]~~~     \n"
  else
    printf "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b~~~[-FAIL-]~~~     \n"
    exit -1
  fi
}