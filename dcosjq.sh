#!/usr/bin/env bash
# set -o errexit
set -o pipefail
# set -o nounset

#####
# JQ pre-flight checks
#####
# Check for jq
if [[ -z $(command -v jq) ]]; then
  echo "ERROR: 'jq' not found. Please install jq and add it to your PATH to continue."
  exit 1
fi

#####
# Format all JSON files within the work dir and sub dirs to be more human readable
#####
formatJSON () {
  if [[ -n $JSON_FILES ]]; then
    echo "Formatting JSON..."
    find "${JSON_DIR}" -name '*.json' -exec sh -c '
    cat <<< "$(jq '.' < $1 2> /dev/null)" > $1
    ' sh {} \;
    echo "Formatting complete."
  else
    echo "Error: No JSON files found within this directory and its subdirectories."
  fi
}

case "${1,,}" in
  "format" )
    JSON_FILES="$(find . -type f -name '*.json')"
    JSON_DIR="$(pwd)"
    formatJSON
    exit 0
    ;;
esac

#####
# Extract
#####
# Set the full path to where you would like to have bundle and ticket files and folders created.
USER_TICKETS_DIR="${HOME}/Documents/logs/tickets"

# USER_TICKETS_DIR must be set to a valid path for any 'extract' commands to function properly
extractBundle ()  {
  if [[ -n $1 ]]; then
    read -r -p "Ticket number: " TICKET_NUM
    TICKET_DIR="${USER_TICKETS_DIR}/${TICKET_NUM}"
    mkdir -p "${TICKET_DIR}"
    BUNDLE_DIR="${USER_TICKETS_DIR}/${TICKET_NUM}/${1%%.zip}"
    echo "Extracting bundle to ${BUNDLE_DIR}..."
    unzip -q -d "${BUNDLE_DIR}" "${1}"
    echo "Decompressing all bundle files..."
    find "${BUNDLE_DIR}" -type f -name '*.gz' -exec gunzip -q "{}" \;
    JSON_FILES="$(find "${BUNDLE_DIR}" -type f -name '*.json')"
    JSON_DIR="${BUNDLE_DIR}"
    formatJSON
    # Move the compressed log bundle to the 'storage' directory; Comment the next 3 lines out to not move the original file.
    mkdir -p "${TICKET_DIR}/storage"
    echo "Moving original bundle file to ${TICKET_DIR}/storage/${1}"
    mv "${1}" "${TICKET_DIR}/storage/${1}"
    echo "Finished extracting bundle to ${BUNDLE_DIR}"
    exit 0
  else
    echo "Please specify a compressed DC/OS diagnostic bundle file to extract."
    exit 1
  fi
}

case ${1,,} in
  "extract" )
    extractBundle "${2}"
    ;;
esac

#####
# Set target
#####
if [[ $(pwd) != *"bundle"* ]]; then
  if [[ ! -z $DCOSJQ_MASTER_STATE ]]; then
    # TARGET_TYPE="file"
    MESOS_MASTER_STATE=$(cat $DCOSJQ_MASTER_STATE)
  elif [[ ! -z $(dcos cluster list | grep -i "$(dcos config show core.dcos_url)" | grep -vi 'unavailable') ]]; then
    # TARGET_TYPE="cluster"
    MESOS_MASTER_STATE=$(curl -k -s -H "Authorization: token=$(dcos config show core.dcos_acs_token)" "$(dcos config show core.dcos_url)/mesos/state")
  else
    echo "ERROR: Not connected to any DC/OS clusters and DCOSJQ_MASTER_STATE is unset."
    exit 1
  fi
elif [[ $(pwd) == *"bundle"* ]]; then
  if [[ -z $(ls -- *master 2> /dev/null) ]]; then
    echo "ERROR: Unable to find a directory containing the name 'master'. Please ensure that the folder containing the master state files and logs is a name contains the string 'master'."
    exit 1
  else
    for i in *master*/5050*registrar*1*_registry.json; do
      if [[ -n $(jq '.master.info.hostname' "${i}" | grep -vi 'null\|\[\|\]' | cut -d '"' -f 2) ]]; then
        # Set the Mesos leader hostname
        MESOS_LEADER_HOSTNAME="$(jq '.master.info.hostname' "${i}" | grep -vi 'null\|\[\|\]' | cut -d '"' -f 2 | uniq)"
        # Check if somehow we're seeing multiple leading masters
        if [[ -n $(echo "${MESOS_LEADER_HOSTNAME}" | awk '{print $2}') ]]; then
          echo -e "ERROR: Detected multiple entries for the leading Mesos master. Please address these issues. The hostnames found were:\n${MESOS_LEADER_HOSTNAME}"
          exit
        fi
        # Set the Mesos leader dir based on HOSTNAME_master format
        MESOS_LEADER_DIR="$(pwd)/${MESOS_LEADER_HOSTNAME}_master"
        MESOS_MASTER_STATE=$(cat ${MESOS_LEADER_DIR}/5050-master_state.json)
        MESOS_STATE_SUMMARY="${MESOS_LEADER_DIR}/5050-master_state-summary.json"
        # Verify the Mesos leader dir exists
        if [[ ! -d "${MESOS_LEADER_DIR}" ]]; then
          echo "ERROR: Couldn't find a the leading Mesos master directory within this directory. Expected path: ${MESOS_LEADER_DIR}"
          exit 1
        fi
      fi
    done
  fi
fi

#####
# Exhibitor
#####
printExhibitorLeader () {
  jq -r '"Exhibitor Leader: \(.[] | select(.isLeader == true) | .hostname)"' "${MESOS_LEADER_DIR}/"*"-exhibitor_exhibitor_v1_cluster_status.json"
}

printExhibitorStatus () {
  (echo -e "HOSTNAME LEADER DESCRIPTION CODE"
  jq -r '"\(.[] | (.hostname) + " " + (.isLeader | tostring) + " " + (.description) + " " + (.code | tostring))"' "${MESOS_LEADER_DIR}/"*"-exhibitor_exhibitor_v1_cluster_status.json") | column -t
}

case ${1,,} in
  "exhibitor")
    case ${2,,} in
      "status" )
        printExhibitorStatus
        ;;
      "leader" )
        printExhibitorLeader
        ;;
    esac
    ;;
esac

#####
# Mesos
#####
printMesosLeader () {
  echo "Mesos Leader: ${MESOS_LEADER_HOSTNAME}"
}

printMesosFlags() {
  jq '.flags' "${MESOS_LEADER_DIR}/5050-master_flags.json"
}

case "${1,,}" in
  "mesos" )
    case "${2,,}" in
      "leader" )
        printMesosLeader
        ;;
      "flags" )
        printMesosFlags
        ;;
    esac
    ;;
esac

#####
# Cluster
#####
printClusterInfo () {
  jq -r '.' "${MESOS_LEADER_DIR}/opt/mesosphere/etc/expanded.config.json"
}

printClusterResources () {
  (echo -e "AGENT_ID IP RESOURCE TOTAL UNRESERVED RESERVED USED"
  echo $MESOS_MASTER_STATE | jq -r '"\(.slaves[] | (.id) + " " + (.hostname) + " CPU "+ (.resources.cpus | tostring) + " " + (.unreserved_resources.cpus | tostring) + " " + (.resources.cpus - .unreserved_resources.cpus | tostring | .[:5]) + " " + (.used_resources.cpus | tostring) + "\n - - MEM "+ (.resources.mem | tostring) + " " + (.unreserved_resources.mem | tostring) + " " + (.resources.mem - .unreserved_resources.mem | tostring) + " " + (.used_resources.mem | tostring) + "\n - - DISK "+ (.resources.disk | tostring) + " " + (.unreserved_resources.disk | tostring) + " " + (.resources.disk - .unreserved_resources.disk | tostring) + " " + (.used_resources.disk | tostring) + "\n - - GPU "+ (.resources.gpus | tostring) + " " + (.unreserved_resources.gpus | tostring) + " " + (.resources.gpus - .unreserved_resources.gpus | tostring) + " " + (.used_resources.gpus | tostring))"') | column -t
}

case "${1,,}" in
  "cluster" )
    case "${2,,}" in
      "resources" )
        printClusterResources
        ;;
      "info" )
        printClusterInfo
        ;;
    esac
    ;;
esac

#####
# Framework
# TODO:
#     - Fix framework summary function
#####
printFrameworkList () {
  # echo "+ echo -e \"ID NAME\n\$(jq -r '.frameworks[] | \"\(.id + \" \" + .name)\"' ${MESOS_MASTER_STATE} | sort -k 2)\" | column -t"
  (echo -e "ID NAME"
  echo $MESOS_MASTER_STATE | jq -r '.frameworks[] | "\(.id + " " + .name)"' | sort -k 2) | column -t
}

# Need to do something crafty with this... Perhaps just print similar output to the summary but more readable...
printFrameworkIDSummary () {
  jq '.frameworks[] | select(.id == "'"${FRAMEWORK_ID}"'")' "${MESOS_STATE_SUMMARY}"
}

printFrameworkIDAgents () {
  (echo -e "HOSTNAME SLAVE_ID ACTIVE"
  echo $MESOS_MASTER_STATE | jq -r '(.frameworks[] | select(.id == "'"${FRAMEWORK_ID}"'").tasks[].slave_id) as $SLAVEIDS | .slaves[] | select(.id | contains($SLAVEIDS)) | "\((.hostname) + " " + (.id) + " " + (.active | tostring))"' | sort -u) | column -t
}

printFrameworkIDTasks () {
  (echo -e "ID STATE TIMESTAMP SLAVE_ID"
  echo $MESOS_MASTER_STATE | jq -r '"\(.frameworks[].tasks[] | select(.framework_id == "'"${FRAMEWORK_ID}"'") | (.id) + " " + (.statuses[-1] | (.state) + " " + (.timestamp | todate)) + " " + (.slave_id))"' | sort -k 1) | column -t
}

printFrameworkIDTasksAll () {
  (echo -e "ID CURRENT_STATE STATES TIMESTAMP SLAVE_ID"
  echo $MESOS_MASTER_STATE | jq -r '"\(.frameworks[].tasks[] | select(.framework_id == "'"${FRAMEWORK_ID}"'") | (.id) + " " + (.state) + " " + (.statuses[] | (.state) + " " + (.timestamp | todate)) + " " + (.slave_id))"' | sort -k 1) | column -t
}

printFrameworkIDTaskIDSummary () {
  echo $MESOS_MASTER_STATE | jq '.frameworks[].tasks[] | select(.framework_id == "'"${FRAMEWORK_ID}"'") | select(.id == "'"${FRAMEWORK_TASK_ID}"'")'
}

printFrameworkIDRoles () {
  (echo -e "ROLE_NAME"
  echo $MESOS_MASTER_STATE | jq -r '"\(.frameworks[] | select(.id == "'"${FRAMEWORK_ID}"'") | (.role) + "\n" + (.tasks[].role))"' | sort -u) | column -t
}

printFrameworkCommandUsage () {
  echo -e "DCOSJQ Framework Usage:"
  (echo -e "framework list - Prints framework id and name of each framework"
  echo -e "framework <framework-id> - Prints a summary of the specified framework"
  echo -e "framework <framework-id> agents - Prints the slave-ids associated with the framework"
  echo -e "framework <framework-id> tasks - Prints the id, name, role, slave id, and state of each task associated with the framework"
  echo -e "framework <framework-id> roles - Prints the roles associated with the framework") | sed 's/^/     /g'
}

case "${1,,}" in
  "framework" )
    # Beware of case sensitivity here :)
    case "${2}" in
      "" )
        printFrameworkCommandUsage
        ;;
      "list" )
        printFrameworkList
        ;;
      "$(echo $MESOS_MASTER_STATE | jq -r '"\(.frameworks[] | select(.id == "'"${2}"'") | .id)"')" )
        FRAMEWORK_ID=$2
        case "${3,,}" in
          "" )
            printFrameworkIDSummary
            ;;
          "agents" )
            printFrameworkIDAgents
            ;;
          "tasks" )
            FRAMEWORK_TASK_ID=$4
            case "${4}" in
              "" )
                printFrameworkIDTasks
                ;;
              "--all" )
                printFrameworkIDTasksAll
                ;;
              "$(echo $MESOS_MASTER_STATE | jq -r '"\(.frameworks[].tasks[] | select(.framework_id == "'"${FRAMEWORK_ID}"'") | select(.id == "'"${FRAMEWORK_TASK_ID}"'").id)"')" )
                printFrameworkIDTaskIDSummary
                ;;
              * )
                printFrameworkIDTasks
                ;;
            esac
            ;;
          "roles" )
            printFrameworkIDRoles
            ;;
          * )
            printFrameworkIDSummary
            ;;
        esac
        ;;
      * )
        printFrameworkCommandUsage
        ;;
    esac
    ;;
esac

#####
# Marathon
# TODO:
# - Queue
# - Pull info from 8080/8443-metrics.json? e.g., errors
#####

printMarathonLeader () {
  jq -r '"Marathon Leader: \(.leader)"' "${MESOS_LEADER_DIR}/8"*"v2_leader.json"
}

printMarathonInfo () {
  jq '.' "${MESOS_LEADER_DIR}/8"*"v2_info.json"
}

printMarathonAppList () {
  (echo -e "ID VERSION"
  jq -r '"\(.apps[] | (.id) + " " + (.version))"' "${MESOS_LEADER_DIR}/8"*"v2_apps.json") | column -t
}

printMarathonAppShow () {
  jq '.apps[] | select(.id == "'"${APP_ID}"'")' "${MESOS_LEADER_DIR}/8"*"v2_apps.json"
}

# This could be filtered much better (e.g., for app first)
printMarathonDeploymentList () {
  (echo -e "ID VERSION"
  jq -r '"\(.[] | (.id) + " " + (.version))"' "${MESOS_LEADER_DIR}/8"*"v2_deployments.json") | column -t
}

printMarathonDeploymentSummary () {
  jq '.[] | select(.id == "'"${DEPLOYMENT_ID}"'")' "${MESOS_LEADER_DIR}/8"*"v2_deployments.json"
}

# Though this will likely not be used much, we should get also get sub-groups eventually...
printMarathonGroupList () {
  (echo -e "ID VERSION"
  jq -r '"\(.groups[] | (.id) + " " + (.version))"' "${MESOS_LEADER_DIR}/8"*"v2_groups.json") | column -t
}

printMarathonGroupSummary () {
  jq '.groups[] | select(.id == "'"${GROUP_ID}"'")' "${MESOS_LEADER_DIR}/8"*"v2_groups.json"
}

printMarathonPodList () {
  (echo -e "ID VERSION"
  jq -r '"\(.[] | (.id) + " " + (.version))"' "${MESOS_LEADER_DIR}/8"*"v2_pods.json") | column -t
}

printMarathonPodShow () {
  jq '.[] | select(.id == "'"${POD_ID}"'")' "${MESOS_LEADER_DIR}/8"*"v2_pods.json"
}

printMarathonTaskList () {
  (echo -e "ID STATE STARTED"
  jq -r '"\(.tasks[] | (.id) + " " + (.state) + " " + (.startedAt))"' "${MESOS_LEADER_DIR}/8"*"v2_tasks.json" | sort -k 1) | column -t
}

printMarathonTaskSummary () {
  jq '.tasks[] | select(.id == "'"${TASK_ID}"'")' "${MESOS_LEADER_DIR}/8"*"v2_tasks.json"
}

case "${1,,}" in
  "marathon" )
    case "${2,,}" in
      "leader" )
        printMarathonLeader
        ;;
      "info" )
        printMarathonInfo
        ;;
      "app" )
        case "${3}" in
          "list" )
            printMarathonAppList
            ;;
          "$(jq -r '"\(.apps[] | select(.id == "'"${3}"'") | .id)"' "${MESOS_LEADER_DIR}/8"*"v2_apps.json")" )
            APP_ID=$3
            case "${4}" in
              "show" )
                printMarathonAppShow
                ;;
            esac
            ;;
        esac
        ;;
      "deployment" )
        case "${3}" in
          "list" )
            printMarathonDeploymentList
            ;;
          "$(jq -r '"\(.[] | select(.id == "'"${3}"'") | .id)"' "${MESOS_LEADER_DIR}/8"*"v2_deployments.json")" )
            DEPLOYMENT_ID=$3
            printMarathonDeploymentSummary
            ;;
        esac
        ;;
      "group" )
        case "${3}" in
          "list" )
            printMarathonGroupList
            ;;
          "$(jq -r '"\(.groups[] | select(.id == "'"${3}"'") | (.id | tostring))"' "${MESOS_LEADER_DIR}/8"*"v2_groups.json")" )
            GROUP_ID=$3
            printMarathonGroupSummary
            ;;
        esac
        ;;
      "pod" )
        case "${3}" in
          "list" )
            printMarathonPodList
            ;;
          "$(jq -r '"\(.[] | select(.id == "'"${3}"'") | .id)"' "${MESOS_LEADER_DIR}/8"*"v2_pods.json")" )
            POD_ID=$3
            case "${4}" in
              "show" )
                printMarathonPodShow
                ;;
            esac
            ;;
        esac
        ;;
      "task" )
        case "${3}" in
          "list" )
            printMarathonTaskList
            ;;
          "$(jq -r '"\(.tasks[] | select(.id == "'"${3}"'") | (.id))"' "${MESOS_LEADER_DIR}/8"*"v2_tasks.json")" )
            TASK_ID=$3
            printMarathonTaskSummary
            ;;
        esac
        ;;
    esac
    ;;
esac

#####
# Task
#####
printTaskList () {
  (echo -e "ID FRAMEWORK_ID SLAVE_ID STATE"
  jq -r '"\(.tasks[] | (.id) + " " + (.framework_id) + " " + (.slave_id) + " " + (.state))"' "${MESOS_LEADER_DIR}/5050-master_tasks.json") | column -t
}

printTaskSummary () {
  jq -r '.tasks[] | select(.id == "'"${TASK_ID}"'")' "${MESOS_LEADER_DIR}/5050-master_tasks.json"
}

case "${1,,}" in
  "task" )
    case "${2}" in
      "" )
        printTaskCommandUsage
        ;;
      "list" )
        printTaskList
        ;;
      "$(jq -r '"\(.tasks[] | select(.id == "'"${2}"'") | .id)"' "${MESOS_LEADER_DIR}/5050-master_tasks.json")" )
        TASK_ID=$2
        printTaskSummary
        ;;
    esac
    ;;
esac

#####
# Agent
#####
printAgentList () {
  (echo -e "ID HOSTNAME ACTIVE REGISTERED"
  echo $MESOS_MASTER_STATE | jq -r '"\(.slaves[] | (.id) + " " + (.hostname) + " " + (.active | tostring) + " " + (.registered_time | todate))"' | sort -k 2) | column -t
}

# Need to do something crafty with this... Perhaps just print similar output to the summary but more readable...
printAgentSummary () {
  jq '.slaves[] | select(.id == "'"${AGENT_ID}"'") | .' "${MESOS_STATE_SUMMARY}"
}

printAgentResources () {
  (echo -e "AGENT_ID IP RESOURCE TOTAL UNRESERVED RESERVED USED"
  echo $MESOS_MASTER_STATE | jq -r '"\(.slaves[] | select(.id == "'"${AGENT_ID}"'") | (.id) + " " + (.hostname) + " CPU "+ (.resources.cpus | tostring) + " " + (.unreserved_resources.cpus | tostring) + " " + (.resources.cpus - .unreserved_resources.cpus | tostring | .[:5]) + " " + (.used_resources.cpus | tostring) + "\n - - MEM "+ (.resources.mem | tostring) + " " + (.unreserved_resources.mem | tostring) + " " + (.resources.mem - .unreserved_resources.mem | tostring) + " " + (.used_resources.mem | tostring) + "\n - - DISK "+ (.resources.disk | tostring) + " " + (.unreserved_resources.disk | tostring) + " " + (.resources.disk - .unreserved_resources.disk | tostring) + " " + (.used_resources.disk | tostring) + "\n - - GPU "+ (.resources.gpus | tostring) + " " + (.unreserved_resources.gpus | tostring) + " " + (.resources.gpus - .unreserved_resources.gpus | tostring) + " " + (.used_resources.gpus | tostring))"') | column -t
}

printAgentFrameworks () {
  (echo -e "ID NAME"
  echo $MESOS_MASTER_STATE | jq -r '.frameworks[] | {id: .id, name: .name, slave_id: .tasks[].slave_id} | select(.slave_id == "'"${AGENT_ID}"'") | "\((.id) + " " + (.name))"' | sort -u -k 2) | column -t
}

# It might make sense to add framework ids in here
printAgentTasks () {
  (echo -e "ID NAME CURRENT_STATE STATES TIMESTAMP"
  echo $MESOS_MASTER_STATE | jq -r '"\(.frameworks[].tasks[] | select(.slave_id == "'"${AGENT_ID}"'") | (.id) + " " +  (.name) + " " + (.state) + " " + (.statuses[] | (.state) + " " + (.timestamp | todate)))"' | sort -k 1) | column -t
}

# printAgentRoles () {
#   Placeholder
# }

printAgentCommandUsage () {
  echo -e "DCOSJQ Agent Usage:"
  (echo -e "agent list - Prints agent id and name of each agent"
  echo -e "agent <agent-id> - Prints a summary of the specified agent"
  echo -e "agent <agent-id> resources - Prints resource summary of the specified agent"
  echo -e "agent <agent-id> frameworks - Prints the framework-ids associated with the agent"
  echo -e "agent <agent-id> tasks - Prints the id, name, role, slave id, and state of each task associated with the agent") | sed 's/^/     /g'
}

# Need to fix the main agent part of this so that empty strings don't get processed if we put the "" option after...
case "${1,,}" in
  "agent" )
    # Beware of case sensitivity here :)
    case "${2}" in
      "" )
        printAgentCommandUsage
        ;;
      "list" )
        printAgentList
        ;;
      "$(echo $MESOS_MASTER_STATE | jq -r '"\(.slaves[] | select(.id == "'"${2}"'") | .id)"')" )
        AGENT_ID=$2
        case "${3,,}" in
          "resources" )
            printAgentResources
            ;;
          "frameworks" )
            printAgentFrameworks
            ;;
          "tasks" )
            printAgentTasks
            ;;
          # "roles" )
          #   # Agent <id> roles
          #   printAgentRoles
          #   ;;
          * )
            printAgentSummary
            ;;
        esac
        ;;
      * )
        printAgentCommandUsage
        ;;
    esac
    ;;
esac

#####
# Role
#####
printRoleList () {
  (echo -e "NAME"
  jq -r '.roles[] | "\(.name)"' "${MESOS_LEADER_DIR}/5050-master_roles.json") | column -t
}

printRoleSummary () {
  jq '.roles[] | select(.name == "'"${ROLE_NAME}"'")' "${MESOS_LEADER_DIR}/5050-master_roles.json"
}

printRoleAgents () {
  (echo -e "SLAVE_ID"
  jq -r '"\(.frameworks[].tasks[] | select(.role == "'"${ROLE_NAME}"'") | .slave_id)"' "${MESOS_LEADER_DIR}/5050-master_frameworks.json" | sort -u)
}

printRoleCommandUsage () {
  echo -e "DCOSJQ Role Usage:"
  (echo -e "role list - Prints the name of each role"
  echo -e "role <role-name> - Prints a summary of the specified role"
  echo -e "role <role-name> agents - Prints the agents assoiceted with the specified role") | sed 's/^/     /g'
}

case "${1,,}" in
  "role" )
    case "${2}" in
      "" )
        printRoleCommandUsage
        ;;
      "list" )
        printRoleList
        ;;
      "$(jq -r '.roles[] | select(.name == "'"${2}"'" ) | "\(.name)"' "${MESOS_LEADER_DIR}/5050-master_roles.json")" )
        ROLE_NAME=$2
        case "${3}" in
          "agents" )
            printRoleAgents
            ;;
          * )
            printRoleSummary
            ;;
        esac
        ;;
      * )
        printRoleCommandUsage
        ;;
    esac
    ;;
esac

#####
# Checks
# \xE2\x9D\x8C - ISSUE
# \xE2\x9C\x94 - OK
#####
checkErrors () {
  #########################
  # General cluster information
  #########################
  echo "************************************"
  echo "****** DC/OS CLUSTER SUMMARY: ******"
  python -c 'import sys, yaml, json; json.dump(yaml.load(sys.stdin), sys.stdout, indent=4)' < "${MESOS_LEADER_DIR}/opt/mesosphere/etc/user.config.yaml" | jq -r '"\("Cluster Name: " + .cluster_name + "\nSecurity Mode: " + .security + "\nNumber of Masters: " + .num_masters)"'
  echo "Cluster config.yaml:"
  cat "${MESOS_LEADER_DIR}/opt/mesosphere/etc/user.config.yaml" | sed 's/^/     /g'
  echo "************************************"

  #########################
  # State Checks
  #########################
  # DC/OS verion uniqueness check
  DCOS_VERSIONS="$( (jq -r '"\(.node_role) \(.ip) \(.dcos_version)"' -- */dcos-diagnostics-health.json | sort -k 3; jq -r '"\(.node_role) \(.ip) \(.dcos_version)"' -- */3dt-health.json | sort -k 3) 2> /dev/null)"
  if [[ $(echo "$DCOS_VERSIONS" | awk '{print$3}' | uniq | wc -l) -gt 1 ]]; then
    echo -e "\xE2\x9D\x8C Multiple DC/OS versions detected:"
    (echo -e "NODE_TYPE IP DCOS_VERSION"
    echo -e "$DCOS_VERSIONS") | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No DC/OS version mismatches: $(echo "${DCOS_VERSIONS}" | awk '{print$3}' | uniq)"
  fi

  # DC/OS component healthiness check
  FAILED_UNITS="$( (jq -r '"\(.node_role) \(.ip) \(.hostname) \(.units[] | select(.health != 0) | .id + " " + (.health | tostring))"' -- */dcos-diagnostics-health.json; jq -r '"\(.node_role) \(.ip) \(.hostname) \(.units[] | select(.health != 0) | .id + " " + (.health | tostring))"' -- */3dt-health.json) 2> /dev/null)"
  if [[ -n $FAILED_UNITS ]]; then
    echo -e "\xE2\x9D\x8C Failed DC/OS components found:"
    (echo -e "NODE_TYPE IP HOSTNAME SERVICE STATUS"
    echo -e "$FAILED_UNITS") | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No DC/OS components reporting as unhealthy."
  fi

  # Unreachable agent check
  UNREACHABLE_AGENTS="$(jq -r '"\(.unreachable.slaves[] | .id.value + " " + (.timestamp.nanoseconds / 1000000000 | gmtime | todate | tostring))"' "${MESOS_LEADER_DIR}/5050-registrar_1__registry.json" 2> /dev/null)"
  if [[ -n $UNREACHABLE_AGENTS ]]; then
    echo -e "\xE2\x9D\x8C Unreachable agents found:"
    (echo -e "SLAVE_ID UNREACHABLE_SINCE"
    echo -e "$UNREACHABLE_AGENTS") | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No agents listed as unreachable."
  fi

  # Multiple native Marathon instance check
  NATIVE_MARATHON_LIST="$(echo $MESOS_MASTER_STATE | jq -r '"\(.frameworks[] | select(.name == "marathon") | select(.webui_url? != null) | (.name) + " " + (.id) + " " + (.active | tostring) + " " + (.webui_url))"')"
  if [[ $(echo "${NATIVE_MARATHON_LIST}" | wc -l) -gt 1 ]]; then
    echo -e "\xE2\x9D\x8C Multiple native Marathon frameworks with webui_url found:"
    (echo -e "NAME ID ACTIVE WEBUI_URL"
    echo -e "${NATIVE_MARATHON_LIST}") | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No multiple native Marathon frameworks with webui_url found."
  fi

  # Inactive framework check
  INACTIVE_FRAMEWORK_LIST="$(echo $MESOS_MASTER_STATE | jq -r '"\(.frameworks[] | select(.active? == false) | (.name) + " " + (.id) + " " + (.active | tostring))"')"
  if [[ -n $INACTIVE_FRAMEWORK_LIST ]]; then
    echo -e "\xE2\x9D\x8C Inactive frameworks found:"
    (echo -e "NAME ID ACTIVE"
    echo -e "${INACTIVE_FRAMEWORK_LIST}") | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No inactive frameworks found."
  fi

  # State size check
  MESOS_STATE_SIZE_LIST="$(find . -type f \( -iname "*master_state*" ! -iname "*overlay*" ! -iname "*summary*" \) -exec du -k {} \; | awk '{print$1}' | sort -u)"
  for i in $MESOS_STATE_SIZE_LIST; do
    if [[ $i -ge 5000 ]]; then
      echo -e "\xE2\x9D\x8C The Mesos state file is currently $(echo "scale=2; $i/1000" | bc -l) MB. State files larger than 5 MB can cause issues with the DC/OS UI. Please see the following link for more information and steps to reduce the size: https://mesosphere-community.force.com/s/article/Reducing-state-json-size"
    elif [[ $i -lt 5000 ]]; then
      echo -e "\xE2\x9C\x94 No Mesos state file larger than 5 MB (current $(echo "scale=2; $i/1000" | bc -l))"
    fi
  done

  #########################
  # Log Checks
  #########################
  # Dockerd running check
  DOCKER_DAEMON_NOT_RUNNING="$(comm -23 <(ls -d -- */*ps*aux* 2> /dev/null | cut -d '/' -f 1) <(grep -i 'dockerd' -- */ps*aux* 2> /dev/null | sort -u | cut -d '/' -f 1))"
  for f in */ps*aux*; do
    if [[ -s "$f" ]]; then
      if [[ ! -z $DOCKER_DAEMON_NOT_RUNNING ]]; then
        echo -e "\xE2\x9D\x8C Docker daemon appears to not be running on $(echo $DOCKER_DAEMON_NOT_RUNNING | wc -l | tr -d '[:space:]') node(s). Please ensure that Docker is enabled on boot and running on the following node(s):"
        echo -e $DOCKER_DAEMON_NOT_RUNNING | sed 's/^/     /g'
      else
        echo -e "\xE2\x9C\x94 No nodes missing a running Docker daemon."
      fi
    else
      echo -e "\xE2\x9C\x94 Skipping Docker daemon check due to no 'ps aux' output."
    fi
    break
  done

  # Zookeeper fsync event check
  ZOOKEEPER_FSYNC_EVENTS="$(grep -i 'fsync-ing the write ahead log in' -- */dcos-exhibitor.service* 2> /dev/null)"
  if [[ -n $ZOOKEEPER_FSYNC_EVENTS ]]; then
    echo -e "\xE2\x9D\x8C Zookeeper fsync threshold exceeded events detected (See root cause and recommendations section within https://jira.mesosphere.com/browse/COPS-4403 if times are excessive):"
    echo -e "$ZOOKEEPER_FSYNC_EVENTS" | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No Zookeeper fsync threshold exceeded events."
  fi

  # Zookeeper all nodes available on startup check
  ZOOKEEPER_START_QUORUM_FAILURES="$(grep -i "Exception: Expected.*servers and.*leader, got.*servers and.*leaders" -- */dcos-exhibitor.service* 2> /dev/null | wc -l)"
  if [[ $ZOOKEEPER_START_QUORUM_FAILURES -gt 0 ]]; then
    echo -e "\xE2\x9D\x8C Zookeeper failed to start ${ZOOKEEPER_START_QUORUM_FAILURES} times due to a missing node. Zookeeper requires that all masters are available before it will start."
  else
    echo -e "\xE2\x9C\x94 No Zookeeper start up failures due to a missing node."
  fi

  # Zookeeper disk full error check
  ZOOKEEPER_DISK_FULL_ERRORS="$(grep -i "No space left on device" -- */dcos-exhibitor.service* 2> /dev/null | wc -l)"
  if [[ $ZOOKEEPER_DISK_FULL_ERRORS -gt 0 ]]; then
    echo -e "\xE2\x9D\x8C Zookeeper logs indicate that the disk is full and has thrown an error ${ZOOKEEPER_DISK_FULL_ERRORS} times. Please check that there is sufficient free space on the disk."
  else
    echo -e "\xE2\x9C\x94 No Zookeeper disk full errors."
  fi

  # CockroachDB time sync check
  COCKROACHDB_TIME_SYNC_EVENTS="$(grep -i "fewer than half the known nodes are within the maximum offset" -- */dcos-cockroach.service* 2> /dev/null | awk 'BEGIN {FS="/"}; {print$1}' | sort -k 2 | uniq -c)"
  if [[ -n $COCKROACHDB_TIME_SYNC_EVENTS ]]; then
    echo -e "\xE2\x9D\x8C CockroachDB logs indicate that there is/was an issue with time sync. Please ensure that time is in sync and CockroachDB is healthy on all Masters."
    (echo -e "EVENTS NODE"
    echo -e "$COCKROACHDB_TIME_SYNC_EVENTS") | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No CockroachDB time sync events."
  fi

  # Private registry certificate error check
  # - Check with the team if we want to add */dcos-marathon.service here
  REGISTRY_CERTIFICATE_ERRORS="$(grep -i "Container.*Failed to perform \'curl\': curl: (60) SSL certificate problem: self signed certificate" -- */dcos-mesos-slave.service* 2> /dev/null | wc -l | awk '{print$1}')"
  if [[ $REGISTRY_CERTIFICATE_ERRORS -gt 0 ]]; then
    echo -e "\xE2\x9D\x8C Detected ${REGISTRY_CERTIFICATE_ERRORS} registry certificate errors. Please see https://jira.mesosphere.com/browse/COPS-2315 and https://jira.mesosphere.com/browse/COPS-2106 for more information."
  else
    echo -e "\xE2\x9C\x94 No private registry certificate errors found."
  fi

  # KMEM event check
  KMEM_EVENTS_PER_NODE="$(grep -i 'SLUB: Unable to allocate memory on node -1' -- */dmesg* 2> /dev/null | awk 'BEGIN {FS="/"}; {print$1}' | sort -k 2 | uniq -c)"
  if [[ -n $KMEM_EVENTS_PER_NODE ]]; then
    echo -e "\xE2\x9D\x8C Detected kmem events (please see advisories: https://support.mesosphere.com/s/article/Critical-Issue-KMEM-MSPH-2018-0006 and https://support.mesosphere.com/s/article/Known-Issue-KMEM-with-Kubernetes-MSPH-2019-0002) on the following nodes:"
    (echo -e "EVENTS NODE"
    echo -e "$KMEM_EVENTS_PER_NODE") | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No KMEM related events found."
  fi

  # OOM event check
  OOM_EVENTS_PER_NODE="$(grep -i 'invoked oom-killer' -- */dmesg* 2> /dev/null | awk 'BEGIN {FS="/"}; {print$1}' | sort | uniq -c)"
  if [[ -n $OOM_EVENTS_PER_NODE ]]; then
    echo -e "\xE2\x9D\x8C Detected out of memory events on the following nodes:"
    (echo -e "EVENTS NODE"
    echo -e "$OOM_EVENTS_PER_NODE") | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No out of memory events found."
  fi
}

case "${1,,}" in
  "checks" )
    checkErrors
    ;;
esac
