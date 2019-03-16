#!/usr/bin/env bash

# TODO:
########################
# master
# agent
# framework
# role
# offers(?)
# unreachable
# Add fix so that this can be run from any dir within a bundle (Make sure to remove the associated section from 'pre-flight checks' when implementing this...)
#########################

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
    unzip -q -d "${BUNDLE_DIR}" "${2}"
    gunzip -q -r "${BUNDLE_DIR}"
    # Move the compressed log bundle to the 'storage' directory; Comment the next 2 lines out to not move the original file.
    mkdir -p "${TICKET_DIR}/storage"
    mv $2 "${TICKET_DIR}/storage/${2}"
    echo "Finished extracting bundle to '${BUNDLE_DIR}'."
  else
    echo "Please specify a compressed DC/OS diagnostic bundle file to extract."
  fi
  exit
fi

#####
# JQ/bundle pre-flight checks
#####
# Check for jq
if [[ -z $(which jq) ]]; then
  echo "ERROR: 'jq' not found. Please install jq and add it to your PATH to continue."
  exit
# Check that current dir is a bundle dir
elif [[ $(pwd) != *"bundle"* ]]; then
  echo "ERROR: The working directory, $(pwd), doesn't seem to be a bundle directory. Please verify the working directory name contains 'bundle'."
  exit
# Ensure at least one master folder exists
elif [[ $(ls -l | grep -i 'master') != *"master"* ]]; then
  echo "ERROR: Unable to find a directory containing the name 'master'. Please ensure that the folder containing the master state files and logs is a name contains the string 'master'."
  exit
fi

#####
# Find the leading Mesos master directory
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
    MESOS_STATE_SUMMARY="${MESOS_LEADER_DIR}/5050-master_state-summary.json"
    # Verify the Mesos leader dir exists (this could be done better)
    if [[ -z $(ls -l $MESOS_LEADER_DIR | grep -vi 'no such') ]]; then
      echo "ERROR: Couldn't find a the leading Mesos master directory within this directory. Expected path: ${MESOS_LEADER_DIR}"
      exit
    fi
  fi
done

#####
# Master
#####
if [[ $1 == "master" ]]; then
  if [[ $# -eq 1 ]]; then
    # Print Mesos leader 'hostname' (IP)
    echo $MESOS_LEADER_HOSTNAME
  fi
fi

#####
# Framework
#####
printFrameworkList () {
  echo -e "ID NAME\n $(jq -r '.frameworks[] | "\(.id) \(.name)"' $MESOS_STATE_SUMMARY)" | column -t
}

printFrameworkIDSummary () {
  jq '.frameworks[] | select(.id == "'$FRAMEWORK_ID'")' $MESOS_STATE_SUMMARY
}

printFrameworkIDAgents () {
  echo -e "ID\n $(jq -r '.frameworks[] | select(.id == "'$FRAMEWORK_ID'") | .slave_ids[]' $MESOS_STATE_SUMMARY)" | column -t
}

printFrameworkIDTasks () {
  echo -e "ID NAME ROLE SLAVE_ID STATE\n $(jq -r '.frameworks[] | select(.id == "'$FRAMEWORK_ID'") | .tasks[] | "\(.id) \(.name) \(.role) \(.slave_id) \(.state)"' $MESOS_LEADER_DIR/5050-master_frameworks.json | sort)" | column -t
}

if [[ $1 == "framework" ]]; then
  if [[ $# -eq 1 ]]; then
    # If naked, print usage
    echo "Print framework usage here, etc."
  elif [[ $# -gt 1 ]]; then
    if [[ $2 == "list" ]]; then
      # Framework list
      printFrameworkList
    elif [[ ! -z $(jq -r '.frameworks[] | select(.id == "'$2'") | "\(.id)"' $MESOS_STATE_SUMMARY) ]]; then
      FRAMEWORK_ID=$2
      if [[ $# -eq 2 ]]; then
        # Print summary for <framework-id>
        printFrameworkIDSummary
      elif [[ $3 == "agents" ]]; then
        # Print agents associated with <framework-id>
        printFrameworkIDAgents
      elif [[ $3 == "tasks" ]]; then
        # Print tasks associated with <framework-id>
        printFrameworkIDTasks
      fi
    else
      # Subcommand/framework-id not found
      echo "ERROR: '$2' is not a valid command or framework-id. Please try again."
      echo "Print framework usage here, etc."
    fi
  fi
fi

#####
# Agent
#####
printAgentList () {
  echo -e "ID HOSTNAME\n $(jq -r '.slaves[] | "\(.id) \(.hostname)"' $MESOS_STATE_SUMMARY | sort -k 2)" | column -t
}

printAgentSummary () {
  jq '.slaves[] | select(.id == "'$AGENT_ID'") | .' $MESOS_STATE_SUMMARY
}

# Need to clean this up - AGENT-ID RESOURCE TOTAL UNRESERVED RESERVED FREE?
printAgentResources () {
  TOTAL_CPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .resources.cpus' $MESOS_STATE_SUMMARY)"
  TOTAL_MEM="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .resources.mem' $MESOS_STATE_SUMMARY)"
  TOTAL_DISK="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .resources.disk' $MESOS_STATE_SUMMARY)"
  TOTAL_GPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .resources.gpus' $MESOS_STATE_SUMMARY)"

  UNRESERVED_CPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .unreserved_resources.cpus' $MESOS_STATE_SUMMARY)"
  UNRESERVED_MEM="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .unreserved_resources.mem' $MESOS_STATE_SUMMARY)"
  UNRESERVED_DISK="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .unreserved_resources.disk' $MESOS_STATE_SUMMARY)"
  UNRESERVED_GPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .unreserved_resources.gpus' $MESOS_STATE_SUMMARY)"

  USED_CPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .used_resources.cpus' $MESOS_STATE_SUMMARY)"
  USED_MEM="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .used_resources.mem' $MESOS_STATE_SUMMARY)"
  USED_DISK="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .used_resources.disk' $MESOS_STATE_SUMMARY)"
  USED_GPUS="$(jq '.slaves[] | select(.id == "'$AGENT_ID'") | .used_resources.gpus' $MESOS_STATE_SUMMARY)"

  FREE_CPUS="$(bc <<< "$TOTAL_CPUS - $USED_CPUS")"
  FREE_MEM="$(bc <<< "$TOTAL_MEM - $USED_MEM")"
  FREE_DISK="$(bc <<< "$TOTAL_DISK - $USED_DISK")"
  FREE_GPUS="$(bc <<< "$TOTAL_GPUS - $USED_GPUS")"

  echo "┌───────── agent-id: $AGENT_ID "
  echo "├─ CPUS: $TOTAL_CPUS"
  echo "│     ├─ Unreserved: $UNRESERVED_CPUS / $TOTAL_CPUS"
  echo "│     └─ Free: $FREE_CPUS / $TOTAL_CPUS"
  echo "├─ MEM: $TOTAL_MEM"
  echo "│     ├─ Unreserved: $UNRESERVED_MEM / $TOTAL_MEM"
  echo "│     └─ Free: $FREE_MEM / $TOTAL_MEM"
  echo "├─ DISK: $TOTAL_DISK"
  echo "│     ├─ Unreserved: $UNRESERVED_DISK / $TOTAL_DISK"
  echo "│     └─ Free: $FREE_DISK / $TOTAL_DISK"
  echo "├─ GPUS: $TOTAL_GPUS"
  echo "│     ├─ Unreserved: $UNRESERVED_GPUS / $TOTAL_GPUS"
  echo "│     └─ Free: $FREE_GPUS / $TOTAL_GPUS"
  echo "└────────────────────────────────────────────────────────"
}

printAgentFrameworks () {
  jq '.slaves[] | select(.id == "'$AGENT_ID'") | .framework_ids[]' $MESOS_STATE_SUMMARY
}

if [[ $1 == "agent" ]]; then
  if [[ $# -eq 1 ]]; then
    # Print usage
    echo "Print agent usage here, etc."
  elif [[ $# -gt 1 ]]; then
    if [[ $2 == "list" ]]; then
      # Print agent list (Need to add Mesos 'hostname' (IP) here)
      printAgentList
    elif [[ ! -z $(jq -r '.slaves[] | select(.id == "'$2'") | "\(.id)"' $MESOS_STATE_SUMMARY) ]]; then
      AGENT_ID=$2
      if [[ $# -eq 2 ]]; then
        # Print <agent-id> summary
        printAgentSummary
      elif [[ $3 == "resources" ]]; then
        # Print <agent-id> resources
        printAgentResources
      elif [[ $3 == "frameworks" ]]; then
        # Print <agent-id> frameworks
        printAgentFrameworks
      elif [[ $3 == "tasks" ]]; then
        # Print <agent-id> tasks
        echo "Not implemented."
      fi
    else
      echo "ERROR: '$2' is not a valid command or agent-id. Please try again."
      echo "Print framework usage here, etc."
    fi
  fi
fi

#####
# Role
#####
printRoleList () {
  echo -e "NAME" | awk '{ printf "%-80s %-40s\n", $1, $2}'
  jq -r '.roles[] | "\(.name)"' $MESOS_LEADER_DIR"/5050-master_roles.json" | awk '{ printf "%-80s %-40s\n", $1, $2}'
}

printRoleSummary () {
  jq '.roles[] | select(.name == "'$ROLE_NAME'")' $MESOS_LEADER_DIR"/5050-master_roles.json"
}

printRoleAgents () {
  jq '.frameworks[].tasks[] | select(.role == "'$ROLE_NAME'") | .slave_id' $MESOS_LEADER_DIR/5050-master_frameworks.json | sort -u
}

if [[ $1 == "role" ]]; then
  if [[ $# -eq 1 ]]; then
    # Print usage
    echo "Print role usage here, etc."
  elif [[ $# -gt 1 ]]; then
    if [[ $2 == "list" ]]; then
      # Print role list
      printRoleList
    elif [[ ! -z $(jq -r '.roles[] | select(.name == "'$2'" ) | "\(.name)"' $MESOS_LEADER_DIR"/5050-master_roles.json") ]]; then
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
      echo "Print role usage here, etc."
    fi
  fi
fi

#####
# Checks (TODO: Eventually make this way more readable... Single line check marks or X and color output.)
#####
if [[ $1 == "checks" ]]; then
  #########################
  # State Checks
  #########################
  #####
  # DC/OS verion uniqueness check
  #####
  DCOS_VERSIONS="$(jq -r '"\(.node_role) \(.ip) \(.dcos_version)"' */dcos-diagnostics-health.json | sort -k 3)"
  if [[ $(echo "$DCOS_VERSIONS" | awk '{print$3}' | uniq | wc -l) -gt 1 ]]; then
    echo -e "\xE2\x9D\x8C Multiple DC/OS versions detected:"
    echo -e "NODE_TYPE IP DCOS_VERSION\n$DCOS_VERSIONS" | column -t
  else
    echo -e "\xE2\x9C\x94 All nodes on the same DC/OS version: $(echo $DCOS_VERSIONS | awk '{print$3}' | uniq)"
  fi
  #####
  # DC/OS component healthiness check (TODO: Add support for 3dt-health.json)
  #####
  FAILED_UNITS="$(jq -r '"\(.node_role) \(.ip) \(.hostname) \(.units[] | select(.health != 0) | .id + " " + (.health | tostring))"' */dcos-diagnostics-health.json)"
  if [[ ! -z $FAILED_UNITS ]]; then
    echo -e "\xE2\x9D\x8C Failed DC/OS components found:"
    echo -e "NODE_TYPE IP HOSTNAME SERVICE STATUS\n$FAILED_UNITS" | column -t
  else
    echo -e "\xE2\x9C\x94 All components report as healthy."
  fi
  #####
  # Unreachable agent check
  #####
  UNREACHABLE_AGENTS="$(jq -r '"\(.unreachable.slaves[] | .id.value + " " + (.timestamp.nanoseconds|tostring))"' ${MESOS_LEADER_DIR}/5050-registrar_1__registry.json 2> /dev/null)"
  if [[ ! -z $UNREACHABLE_AGENTS ]]; then
    echo -e "\xE2\x9D\x8C Unreachable agents found:"
    echo -e "SLAVE_ID TIME_UNREACHABLE\n$UNREACHABLE_AGENTS" | column -t
  else
    echo -e "\xE2\x9C\x94 No agents listed as unreachable."
  fi
  #########################
  # Log Checks (tail logs from last service started message to rule out false positives, or otherwise, from the beginning)
  #########################
fi

#####
# Beautify
#####
if [[ $1 == "beautify" ]]; then
  for i in $(find . -type f -name '*.json'); do
    cat <<< "$(jq '.' < $i)" > $i
  done
fi
