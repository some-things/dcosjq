#!/usr/bin/env bash

# TODO:
#####
#
# Rewrite and add functions as needed for if a bundle is complete or if we are only limited to certain state files.
#
#####

########################
# master
# agent
# framework
# role
# offers(?)
# unreachable
# Add fix so that this can be run from any dir within a bundle (Make sure to remove the associated section from 'pre-flight checks' when implementing this...)
# Rewrite things so we don't need to have exits for stuff ran before the master dir checks...
# Add var for MESOS_MASTER_STATE
#########################
# SNIPPETS TO IMPLEMENT:
# jq -r '.leader_info.hostname' */5050-master_state.json
# jq -r '.activated_slaves' */5050-master_state.json
# jq -r '.deactivated_slaves' */5050-master_state.json
# jq -r '.unreachable_slaves' */5050-master_state.json
# .cluster
# .flags
# .version
# .slaves[]
# .frameworks[]
# jq -r '.frameworks[].tasks[].role' 5050-master_state.json | uniq <-- doesn't show * :/
#########################

#####
# JQ pre-flight checks
#####
# Check for jq
if [[ -z $(which jq) ]]; then
  echo "ERROR: 'jq' not found. Please install jq and add it to your PATH to continue."
  exit
fi

#####
# Format all JSON files within the work dir and sub dirs to be more human readable
#####
formatJSON () {
  if [[ ! -z $JSON_FILES ]]; then
    echo "Formatting JSON..."
    for i in $(find . -type f -name '*.json'); do
      cat <<< "$(jq '.' < $i 2> /dev/null)" > $i
    done
    echo "Formatting complete."
  else
    echo "Error: No JSON files found within this directory and its subdirectories."
  fi
}

case "${1,,}" in
  "format" )
    JSON_FILES="$(find . -type f -name '*.json')"
    formatJSON
    exit
    ;;
esac

#####
# Extract
#####
# Set the full path to where you would like to have bundle and ticket files and folders created.
BASE_DIR="${HOME}/Documents/logs/tickets"

# BASE_DIR must be set to a valid path for any 'extract' commands to function properly
if [[ $1 == "extract" ]]; then
  if [[ ! -z $2 ]]; then
    read -p "Ticket number: " TICKET_NUM
    TICKET_DIR="${BASE_DIR}/${TICKET_NUM}"
    mkdir -p "${TICKET_DIR}"
    BUNDLE_DIR="${BASE_DIR}/${TICKET_NUM}/${2%%.zip}"
    echo "Extracting bundle to ${BUNDLE_DIR}..."
    unzip -q -d "${BUNDLE_DIR}" "${2}"
    echo "Gunzip-ing all bundle files..."
    gunzip -q -r "${BUNDLE_DIR}"
    JSON_FILES="$(find ${BUNDLE_DIR} -type f -name '*.json')"
    formatJSON
    # Move the compressed log bundle to the 'storage' directory; Comment the next 2 lines out to not move the original file.
    mkdir -p "${TICKET_DIR}/storage"
    echo "Moving original bundle file to ${TICKET_DIR}/storage/${2}"
    mv $2 "${TICKET_DIR}/storage/${2}"
    echo "Finished extracting bundle to ${BUNDLE_DIR}"
  else
    echo "Please specify a compressed DC/OS diagnostic bundle file to extract."
  fi
  exit
fi

#####
# Bundle pre-flight checks
# TODO: Make these less finicky
#####
# Check that current dir is a bundle dir
if [[ $(pwd) != *"bundle"* ]]; then
  echo "ERROR: The working directory, $(pwd), doesn't seem to be a bundle directory. Please verify the working directory name contains 'bundle'."
  exit
# Ensure at least one master folder exists
elif [[ $(ls -l | grep -i 'master') != *"master"* ]]; then
  echo "ERROR: Unable to find a directory containing the name 'master'. Please ensure that the folder containing the master state files and logs is a name contains the string 'master'."
  exit
fi

#####
# Find the leading Mesos master directory
# TODO: Make these less finicky
#####
# NEED TO ADD A CHECK THAT HOSTNAME ISN'T NULL!
# echo "ERROR: Hostname field empty. Please verify that ${MESOS_LEADER_DIR}/5050-registrar_1__registry.json has valid information."
for i in $(find ./*master* -type f -name 5050-registrar_1__registry.json); do
  if [[ ! -z $(jq '.master.info.hostname' $i | grep -vi 'null\|\[\|\]' | cut -d '"' -f 2) ]]; then
    # Set the Mesos leader hostname
    MESOS_LEADER_HOSTNAME="$(jq '.master.info.hostname' $i | grep -vi 'null\|\[\|\]' | cut -d '"' -f 2 | uniq)"
    # Check if somehow we're seeing multiple leading masters
    if [[ ! -z $(echo $MESOS_LEADER_HOSTNAME | awk '{print $2}') ]]; then
      echo -e "ERROR: Detected multiple entries for the leading Mesos master. Please address these issues. The hostnames found were:\n ${MESOS_LEADER_HOSTNAME}"
      exit
    fi
    # Set the Mesos leader dir based on HOSTNAME_master format
    MESOS_LEADER_DIR="$(pwd)/${MESOS_LEADER_HOSTNAME}_master"
    MESOS_MASTER_STATE="${MESOS_LEADER_DIR}/5050-master_state.json"
    MESOS_STATE_SUMMARY="${MESOS_LEADER_DIR}/5050-master_state-summary.json"
    # Verify the Mesos leader dir exists (this could be done better)
    if [[ ! -d "${MESOS_LEADER_DIR}" ]]; then
      echo "ERROR: Couldn't find a the leading Mesos master directory within this directory. Expected path: ${MESOS_LEADER_DIR}"
      exit
    fi
  fi
done

#####
# Mesos Leader
#####
case "${1,,}" in
  # Print Mesos leader 'hostname' (IP)
  "leader" )
    echo "Mesos Leader: ${MESOS_LEADER_HOSTNAME}"
    ;;
esac

#####
# Cluster
#####
printClusterResources () {
  echo -e "AGENT_ID IP RESOURCE TOTAL UNRESERVED RESERVED USED\n$(jq -r '"\(.slaves[] | (.id) + " " + (.hostname) + " CPU "+ (.resources.cpus | tostring) + " " + (.unreserved_resources.cpus | tostring) + " " + (.resources.cpus - .unreserved_resources.cpus | tostring) + " " + (.used_resources.cpus | tostring) + "\n - - MEM "+ (.resources.mem | tostring) + " " + (.unreserved_resources.mem | tostring) + " " + (.resources.mem - .unreserved_resources.mem | tostring) + " " + (.used_resources.mem | tostring) + "\n - - DISK "+ (.resources.disk | tostring) + " " + (.unreserved_resources.disk | tostring) + " " + (.resources.disk - .unreserved_resources.disk | tostring) + " " + (.used_resources.disk | tostring) + "\n - - GPU "+ (.resources.gpus | tostring) + " " + (.unreserved_resources.gpus | tostring) + " " + (.resources.gpus - .unreserved_resources.gpus | tostring) + " " + (.used_resources.gpus | tostring))"' ${MESOS_MASTER_STATE})" | column -t
}

case "${1,,}" in
  "cluster" )
    case "${2,,}" in
      "resources" )
        printClusterResources
        ;;
    esac
    ;;
esac

#####
# Framework
# TODO:
#     - Fix framework summary function
#     - Fix framework <id> agents function
#####
printFrameworkList () {
  echo -e "ID NAME\n$(jq -r '.frameworks[] | "\(.id + " " + .name)"' "${MESOS_MASTER_STATE}" | sort -k 2)" | column -t
}

# Need to do something crafty with this... Perhaps just print similar output to the summary but more readable...
printFrameworkIDSummary () {
  jq '.frameworks[] | select(.id == "'$FRAMEWORK_ID'")' "${MESOS_STATE_SUMMARY}"
}

# This needs to be rewritten to a single jq command without any loops
printFrameworkIDAgents () {
  echo -e "HOSTNAME SLAVE_ID\n$(for i in $(jq -r '.frameworks[] | select(.id == "'$FRAMEWORK_ID'") | .tasks[].slave_id' "${MESOS_MASTER_STATE}" | sort -u); do jq -r '"\(.slaves[] | select(.id == "'$i'") | (.hostname) + " " + (.id))"' "${MESOS_MASTER_STATE}"; done | sort -k 1)" | column -t
}

printFrameworkIDTasks () {
  echo -e "ID NAME CURRENT_STATE STATES TIMESTAMP\n$(jq -r '"\(.frameworks[].tasks[] | select(.framework_id == "'$FRAMEWORK_ID'") | (.id) + " " +  (.name) + " " + (.state) + " " + (.statuses[] | (.state) + " " + (.timestamp | todate)))"' "${MESOS_MASTER_STATE}" | sort -k 1)" | column -t
}

printFrameworkIDRoles () {
  echo -e "ROLE_NAME\n$(jq -r '"\(.frameworks[] | select(.id == "'$FRAMEWORK_ID'") | (.role) + "\n" + (.tasks[].role))"' "${MESOS_MASTER_STATE}" | sort -u)" | column -t
}

printFrameworkCommandUsage () {
  echo -e "DCOSJQ Framework Usage:"
  (echo -e "framework list - Prints framework id and name of each framework"
  echo -e "framework <framework-id> - Prints a summary of the specified framework"
  echo -e "framework <framework-id> agents - Prints the slave-ids associated with the framework"
  echo -e "framework <framework-id> tasks - Prints the id, name, role, slave id, and state of each task associated with the framework") | sed 's/^/     /g'
}

# Need to fix the main framework part of this so that empty strings don't get processed if we put the "" option after...
case "${1,,}" in
  "framework" )
    # Beware of case sensitivity here :)
    case "${2}" in
      "" )
        # Framework command usage
        printFrameworkCommandUsage
        ;;
      "list" )
        # Framework list
        printFrameworkList
        ;;
      "$(jq -r '"\(.frameworks[] | select(.id == "'$2'") | .id)"' "${MESOS_MASTER_STATE}")" )
        FRAMEWORK_ID=$2
        case "${3,,}" in
          "agents" )
            # Framework <id> agents
            printFrameworkIDAgents
            ;;
          "tasks" )
            # Framework <id> tasks
            printFrameworkIDTasks
            ;;
          "roles" )
            # Framework <id> roles
            printFrameworkIDRoles
            ;;
          * )
            # Framework <id> summary
            printFrameworkIDSummary
            ;;
        esac
        ;;
      * )
        # Framework command usage
        printFrameworkCommandUsage
        ;;
    esac
    ;;
esac

#####
# Agent
#####
printAgentList () {
  echo -e "ID HOSTNAME ACTIVE\n$(jq -r '"\(.slaves[] | (.id) + " " + (.hostname) + " " + (.active | tostring))"' "${MESOS_MASTER_STATE}" | sort -k 2)" | column -t
}

# Need to do something crafty with this... Perhaps just print similar output to the summary but more readable...
printAgentSummary () {
  jq '.slaves[] | select(.id == "'$AGENT_ID'") | .' $MESOS_STATE_SUMMARY
}

printAgentResources () {
  echo -e "AGENT_ID IP RESOURCE TOTAL UNRESERVED RESERVED USED\n$(jq -r '"\(.slaves[] | select(.id == "'$AGENT_ID'") | (.id) + " " + (.hostname) + " CPU "+ (.resources.cpus | tostring) + " " + (.unreserved_resources.cpus | tostring) + " " + (.resources.cpus - .unreserved_resources.cpus | tostring) + " " + (.used_resources.cpus | tostring) + "\n - - MEM "+ (.resources.mem | tostring) + " " + (.unreserved_resources.mem | tostring) + " " + (.resources.mem - .unreserved_resources.mem | tostring) + " " + (.used_resources.mem | tostring) + "\n - - DISK "+ (.resources.disk | tostring) + " " + (.unreserved_resources.disk | tostring) + " " + (.resources.disk - .unreserved_resources.disk | tostring) + " " + (.used_resources.disk | tostring) + "\n - - GPU "+ (.resources.gpus | tostring) + " " + (.unreserved_resources.gpus | tostring) + " " + (.resources.gpus - .unreserved_resources.gpus | tostring) + " " + (.used_resources.gpus | tostring))"' ${MESOS_MASTER_STATE})" | column -t
}

printAgentFrameworks () {
  echo -e "ID NAME\n$(jq -r '.frameworks[] | {id: .id, name: .name, slave_id: .tasks[].slave_id} | select(.slave_id == "'$AGENT_ID'") | "\((.id) + " " + (.name))"' "${MESOS_MASTER_STATE}" | sort -u -k 2)" | column -t
}

printAgentTasks () {
  echo -e "ID NAME CURRENT_STATE STATES TIMESTAMP\n$(jq -r '"\(.frameworks[].tasks[] | select(.slave_id == "'$AGENT_ID'") | (.id) + " " +  (.name) + " " + (.state) + " " + (.statuses[] | (.state) + " " + (.timestamp | todate)))"' ${MESOS_MASTER_STATE} | sort -k 1)" | column -t
}

# printAgentRoles () {
#   echo "blah blah blah"
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
        # Agent command usage
        printAgentCommandUsage
        ;;
      "list" )
        # Agent list
        printAgentList
        ;;
      "$(jq -r '"\(.slaves[] | select(.id == "'$2'") | .id)"' $MESOS_MASTER_STATE)" )
        AGENT_ID=$2
        case "${3,,}" in
          "resources" )
            # Agent <id> resources
            printAgentResources
            ;;
          "frameworks" )
            # Agent <id> frameworks
            printAgentFrameworks
            ;;
          "tasks" )
            # Agent <id> tasks
            printAgentTasks
            ;;
          # "roles" )
          #   # Agent <id> roles
          #   printAgentRoles
          #   ;;
          * )
            # Agent <id> summary
            printAgentSummary
            ;;
        esac
        ;;
      * )
        # Agent command usage
        printAgentCommandUsage
        ;;
    esac
    ;;
esac

#####
# Role
#####
printRoleList () {
  echo -e "NAME\n$(jq -r '.roles[] | "\(.name)"' $MESOS_LEADER_DIR/5050-master_roles.json)" | column -t
}

printRoleSummary () {
  jq '.roles[] | select(.name == "'$ROLE_NAME'")' $MESOS_LEADER_DIR/5050-master_roles.json
}

printRoleAgents () {
  jq '.frameworks[].tasks[] | select(.role == "'$ROLE_NAME'") | .slave_id' $MESOS_LEADER_DIR/5050-master_frameworks.json | sort -u
}

printRoleCommandUsage () {
  echo -e "DCOSJQ Role Usage:"
  (echo -e "role list - Prints the name of each role"
  echo -e "role <role-name> - Prints a summary of the specified role"
  echo -e "role <role-name> agents - Prints the agents assoiceted with the specified role") | sed 's/^/     /g'
}

if [[ $1 == "role" ]]; then
  if [[ $# -eq 1 ]]; then
    # Print usage
    echo "Print role usage here, etc."
  elif [[ $# -gt 1 ]]; then
    if [[ $2 == "list" ]]; then
      # Print role list
      printRoleList
    elif [[ ! -z $(jq -r '.roles[] | select(.name == "'$2'" ) | "\(.name)"' $MESOS_LEADER_DIR/5050-master_roles.json) ]]; then
      ROLE_NAME=$2
      if [[ $# -eq 2 ]]; then
        # Print <role-id> summary
        printRoleSummary
      elif [[ $3 == "agents" ]]; then
        # Print <role-id> agents
        printRoleAgents
      fi
    else
      # Subcommand/framework-id not found
      echo "ERROR: '$2' is not a valid command or role. Please try again."
      printRoleCommandUsage
    fi
  fi
fi

#####
# Checks
#####
checkErrors () {
  #########################
  # General cluster information
  #########################
  echo "************************************"
  echo "****** DC/OS CLUSTER SUMMARY: ******"
  jq -r '"\("* Cluster Name: " + .cluster_name + "\n* DCOS Version: " + .dcos_version + "\n* DCOS Security Mode: " + .security + "\n* Platform: " + .platform + "\n* Provider: " + .provider + "\n* Docker GC Enabled: " + .enable_docker_gc + "\n* Mesos GC Delay: " + .gc_delay + "\n* Proxy: " + .use_proxy + "\n* DNS Search Domains: " + .dns_search + "\n* GPU Support: " + .enable_gpu_isolation + "\n* GPUs Scarce: " + .gpus_are_scarce + "\n* Exhibitor Backend: " + .exhibitor_storage_backend + "\n* Number of Masters: " + .num_masters + "\n* Master Discovery: " + .master_discovery + "\n* Master List: " + .master_list + "\n* Resolvers: " + .resolvers)"' ${MESOS_LEADER_DIR}/opt/mesosphere/etc/expanded.config.json
  echo "************************************"

  #########################
  # State Checks
  #########################
  #####
  # DC/OS verion uniqueness check
  #####
  DCOS_VERSIONS="$((jq -r '"\(.node_role) \(.ip) \(.dcos_version)"' */dcos-diagnostics-health.json | sort -k 3; jq -r '"\(.node_role) \(.ip) \(.dcos_version)"' */3dt-health.json | sort -k 3) 2> /dev/null)"
  if [[ $(echo "$DCOS_VERSIONS" | awk '{print$3}' | uniq | wc -l) -gt 1 ]]; then
    echo -e "\xE2\x9D\x8C Multiple DC/OS versions detected:"
    echo -e "NODE_TYPE IP DCOS_VERSION\n$DCOS_VERSIONS" | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 All nodes on the same DC/OS version: $(echo $DCOS_VERSIONS | awk '{print$3}' | uniq)"
  fi

  #####
  # DC/OS component healthiness check
  #####
  FAILED_UNITS="$((jq -r '"\(.node_role) \(.ip) \(.hostname) \(.units[] | select(.health != 0) | .id + " " + (.health | tostring))"' */dcos-diagnostics-health.json; jq -r '"\(.node_role) \(.ip) \(.hostname) \(.units[] | select(.health != 0) | .id + " " + (.health | tostring))"' */3dt-health.json) 2> /dev/null)"
  if [[ ! -z $FAILED_UNITS ]]; then
    echo -e "\xE2\x9D\x8C Failed DC/OS components found:"
    echo -e "NODE_TYPE IP HOSTNAME SERVICE STATUS\n$FAILED_UNITS" | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 All components report as healthy."
  fi

  #####
  # Unreachable agent check
  #####
  UNREACHABLE_AGENTS="$(jq -r '"\(.unreachable.slaves[] | .id.value + " " + (.timestamp.nanoseconds / 1000000000 | gmtime | todate | tostring))"' ${MESOS_LEADER_DIR}/5050-registrar_1__registry.json 2> /dev/null)"
  if [[ ! -z $UNREACHABLE_AGENTS ]]; then
    echo -e "\xE2\x9D\x8C Unreachable agents found:"
    echo -e "SLAVE_ID UNREACHABLE_SINCE\n$UNREACHABLE_AGENTS" | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No agents listed as unreachable."
  fi

  #########################
  # Log Checks (tail logs from last service started message to rule out false positives, or otherwise, from the beginning)
  # Ideas:
  # - Port current checks from bun and implement from issues
  # - Check iptables for DC/OS ports
  #########################
  #####
  # Zookeeper fsync event check
  #####
  ZOOKEEPER_FSYNC_EVENTS="$(grep -i 'fsync-ing the write ahead log in' */dcos-exhibitor.service* 2> /dev/null)"
  if [[ ! -z $ZOOKEEPER_FSYNC_EVENTS ]]; then
    echo -e "\xE2\x9D\x8C Zookeeper fsync events detected (See root cause and recommendations section within https://jira.mesosphere.com/browse/COPS-4403 if times are excessive):"
    echo -e "$ZOOKEEPER_FSYNC_EVENTS" | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No Zookeeper fsync events."
  fi

  #####
  # Zookeeper all nodes available on startup check
  #####
  ZOOKEEPER_START_QUORUM_FAILURES="$(grep -i "Exception: Expected.*servers and.*leader, got.*servers and.*leaders" */dcos-exhibitor.service* 2> /dev/null | wc -l)"
  if [[ $ZOOKEEPER_START_QUORUM_FAILURES -gt 0 ]]; then
    echo -e "\xE2\x9D\x8C Zookeeper failed to start ${ZOOKEEPER_START_QUORUM_FAILURES} times due to a missing node. Zookeeper requires that all masters are available before it will start."
  else
    echo -e "\xE2\x9C\x94 No Zookeeper start up failures due to a missing node."
  fi

  #####
  # Zookeeper disk full error check
  #####
  ZOOKEEPER_DISK_FULL_ERRORS="$(grep -i "No space left on device" */dcos-exhibitor.service* 2> /dev/null | wc -l)"
  if [[ $ZOOKEEPER_DISK_FULL_ERRORS -gt 0 ]]; then
    echo -e "\xE2\x9D\x8C Zookeeper logs indicate that the disk is full and has thrown an error ${ZOOKEEPER_DISK_FULL_ERRORS} times. Please check that there is sufficient free space on the disk."
  else
    echo -e "\xE2\x9C\x94 No Zookeeper disk full errors."
  fi

  #####
  # CockroachDB time sync check
  #####
  COCKROACHDB_TIME_SYNC_EVENTS="$(grep -i "fewer than half the known nodes are within the maximum offset" */dcos-cockroach.service* 2> /dev/null | awk 'BEGIN {FS="/"}; {print$1}' | sort -k 2 | uniq -c)"
  if [[ ! -z $COCKROACHDB_TIME_SYNC_EVENTS ]]; then
    echo -e "\xE2\x9D\x8C CockroachDB logs indicate that there is/was an issue with time sync. Please ensure that time is in sync and CockroachDB is healthy on all Masters."
    echo -e "EVENTS NODE\n$COCKROACHDB_TIME_SYNC_EVENTS" | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No CockroachDB time sync events."
  fi

  #####
  # Private registry certificate error check
  #####
  # Check with the team if we want to add */dcos-marathon.service here
  REGISTRY_CERTIFICATE_ERRORS="$(grep -i "Container.*Failed to perform \'curl\': curl: (60) SSL certificate problem: self signed certificate" */dcos-mesos-slave.service* 2> /dev/null | wc -l | awk '{print$1}')"
  if [[ $REGISTRY_CERTIFICATE_ERRORS -gt 0 ]]; then
    echo -e "\xE2\x9D\x8C Detected ${REGISTRY_CERTIFICATE_ERRORS} registry certificate errors. Please see https://jira.mesosphere.com/browse/COPS-2315 and https://jira.mesosphere.com/browse/COPS-2106 for more information."
  else
    echo -e "\xE2\x9C\x94 No private registry certificate errors found."
  fi

  #####
  # KMEM event check
  #####
  KMEM_EVENTS_PER_NODE="$(grep -Ri 'SLUB: Unable to allocate memory on node -1' */dmesg* 2> /dev/null | awk 'BEGIN {FS="/"}; {print$1}' | sort -k 2 | uniq -c)"
  if [[ ! -z $KMEM_EVENTS_PER_NODE ]]; then
    echo -e "\xE2\x9D\x8C Detected kmem events (please see advisories: https://support.mesosphere.com/s/article/Critical-Issue-KMEM-MSPH-2018-0006 and https://support.mesosphere.com/s/article/Known-Issue-KMEM-with-Kubernetes-MSPH-2019-0002) on the following nodes:"
    echo -e "EVENTS NODE\n$KMEM_EVENTS_PER_NODE" | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No KMEM related events found."
  fi

  #####
  # OOM event check
  #####
  OOM_EVENTS_PER_NODE="$(grep -Ri 'invoked oom-killer' */dmesg* 2> /dev/null | awk 'BEGIN {FS="/"}; {print$1}' | sort | uniq -c)"
  if [[ ! -z $OOM_EVENTS_PER_NODE ]]; then
    echo -e "\xE2\x9D\x8C Detected out of memory events on the following nodes:"
    echo -e "EVENTS NODE\n$OOM_EVENTS_PER_NODE" | column -t | sed 's/^/     /g'
  else
    echo -e "\xE2\x9C\x94 No out of memory events found."
  fi
}

case "${1,,}" in
  "checks" )
    checkErrors
    ;;
esac
