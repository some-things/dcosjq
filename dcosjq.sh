#!/bin/bash

##################################################
##################################################
##################################################
#####
# Extract
#####
# Set the full path to where you would like to have bundle and ticket files and folders created.
#####
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
    mv $2 "${TICKET_DIR}/storage/${2%%.zip}"
    echo "Finished extracting bundle to '${BUNDLE_DIR}'."
    # read -p "Finished extracting bundle to '${BUNDLE_DIR}'. Navigate there now? (y/n) " NAV_CALL
    # if [[ $(echo $NAV_CALL | tr '[:upper:]' '[:lower:]') == "y" || $(echo $NAV_CALL | tr '[:upper:]' '[:lower:]') == "yes" ]]; then
    #   cd "${BUNDLE_DIR}"
    #   echo "Working directory changed to ${BUNDLE_DIR}. Happy debugging!"
    # else
    #   echo "Done"
    # fi
  else
    echo "Please specify a compressed DC/OS diagnostic bundle file to extract."
  fi
  exit
fi

# TODO:
########################
# master
# agent
# framework
# role
# offers(?)
#########################
# framework - prints framework options
# framework list - prints frameworks
# framework <framework-id> agents
# framework <framework-id> roles
#########################
# agent - prints agent options
# agent list - prints agents (fmt: hostname - id)
# agent <agent-id> - prints info about a particular agent (opts: {{used,free,reserved}resources, roles, frameworks})
#########################

# Add fix so that this can be run from any dir within a bundle

#####
# Pre-flight checks
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
# WIP NEED TO ADD A CHECK THAT HOSTNAME ISN'T NULL!
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

##################################################
##################################################
##################################################
#####
# Master
#####
# WIP
if [[ $1 == "master" ]]; then
  if [[ $# -eq 1 ]]; then
    echo $MESOS_LEADER_HOSTNAME
  fi
fi

##################################################
##################################################
##################################################
#####
# Framework
#####
# WIP
printFrameworkList () {
  echo -e "ID NAME" | awk '{ printf "%-80s %-40s\n", $1, $2}'
  jq -r '.frameworks[] | "\(.id) \(.name)"' $MESOS_STATE_SUMMARY | awk '{ printf "%-80s %-40s\n", $1, $2}'
}

printFrameworkIDSummary () {
  jq '.frameworks[] | select(.id == "'$FRAMEWORK_ID'")' $MESOS_STATE_SUMMARY
}

printFrameworkIDAgents () {
  echo -e "ID"
  jq -r '.frameworks[] | select(.id == "'$FRAMEWORK_ID'") | .slave_ids[]' $MESOS_STATE_SUMMARY
}

printFrameworkIDTasks () {
  jq '.frameworks[] | select(.id == "'$FRAMEWORK_ID'") | .tasks[] | {id: .id, name: .name, role: .role, slave_id: .slave_id, state: .state}' $MESOS_LEADER_DIR/5050-master_frameworks.json
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
        printFrameworkIDSummary
      elif [[ $3 == "agents" ]]; then
        printFrameworkIDAgents
      elif [[ $3 == "tasks" ]]; then
        printFrameworkIDTasks
      fi
    else
      # Subcommand/framework-id not found
      echo "ERROR: '$2' is not a valid command or framework-id. Please try again."
      echo "Print framework usage here, etc."
    fi
  fi
fi

##################################################
##################################################
##################################################
#####
# Agent
#####
# WIP
printAgentList () {
  echo -e "ID HOSTNAME" | awk '{ printf "%-80s %-40s\n", $1, $2}'
  jq -r '.slaves[] | "\(.id) \(.hostname)"' $MESOS_STATE_SUMMARY | awk '{ printf "%-80s %-40s\n", $1, $2}'
}

printAgentSummary () {
  jq '.slaves[] | select(.id == "'$AGENT_ID'") | .' $MESOS_STATE_SUMMARY
}

# printAgentResourcesCPU () {
#   TOTAL_CPUS="$(jq '.slaves[] | select(.id == '$2') | .resources.cpus' $MESOS_STATE_SUMMARY)"
#   USED_CPUS="$(jq '.slaves[] | select(.id == '$2') | .used_resources.cpus' $MESOS_STATE_SUMMARY)"
#   FREE_CPUS="$(bc <<< "$TOTAL_CPUS - $USED_CPUS")"
#   UNRESERVED_CPUS="$(jq '.slaves[] | select(.id == '$2') | .unreserved_resources.cpus' $MESOS_STATE_SUMMARY)"
# }
#
# printAgentResourcesMEM () {
#   TOTAL_MEM="$(jq '.slaves[] | select(.id == '$2') | .resources.mem' $MESOS_STATE_SUMMARY)"
#   USED_MEM="$(jq '.slaves[] | select(.id == '$2') | .used_resources.mem' $MESOS_STATE_SUMMARY)"
#   FREE_MEM="$(bc <<< "$TOTAL_MEM - $USED_MEM")"
#   UNRESERVED_MEM="$(jq '.slaves[] | select(.id == '$2') | .unreserved_resources.mem' $MESOS_STATE_SUMMARY)"
# }
#
# printAgentResourcesDisk () {
#   TOTAL_DISK="$(jq '.slaves[] | select(.id == '$2') | .resources.disk' $MESOS_STATE_SUMMARY)"
#   USED_DISK="$(jq '.slaves[] | select(.id == '$2') | .used_resources.disk' $MESOS_STATE_SUMMARY)"
#   FREE_DISK="$(bc <<< "$TOTAL_DISK - $USED_DISK")"
#   UNRESERVED_DISK="$(jq '.slaves[] | select(.id == '$2') | .unreserved_resources.disk' $MESOS_STATE_SUMMARY)"
# }
#
# printAgentResourcesGPUS () {
#   TOTAL_GPUS="$(jq '.slaves[] | select(.id == '$2') | .resources.disk' $MESOS_STATE_SUMMARY)"
#   USED_GPUS="$(jq '.slaves[] | select(.id == '$2') | .used_resources.disk' $MESOS_STATE_SUMMARY)"
#   FREE_GPUS="$(bc <<< "$TOTAL_GPUS - $USED_GPUS")"
#   UNRESERVED_GPUS="$(jq '.slaves[] | select(.id == '$2') | .unreserved_resources.cpus' $MESOS_STATE_SUMMARY)"
# }

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
    # If naked, print usage
    echo "Print agent usage here, etc."
  elif [[ $# -gt 1 ]]; then
    if [[ $2 == "list" ]]; then
      printAgentList
    elif [[ ! -z $(jq -r '.slaves[] | select(.id == "'$2'") | "\(.id)"' $MESOS_STATE_SUMMARY) ]]; then
      AGENT_ID=$2
      if [[ $# -eq 2 ]]; then
        printAgentSummary
      elif [[ $3 == "resources" ]]; then
        printAgentResources
      elif [[ $3 == "frameworks" ]]; then
        printAgentFrameworks
      elif [[ $3 == "tasks" ]]; then
        echo "print tasks from agent-id"
      fi
    else
      echo "ERROR: '$2' is not a valid command or agent-id. Please try again."
      echo "Print framework usage here, etc."
    fi
  fi
fi

##################################################
##################################################
##################################################
#####
# Role
#####
# WIP
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
    # If naked, print usage
    echo "Print role usage here, etc."
  elif [[ $# -gt 1 ]]; then
    if [[ $2 == "list" ]]; then
      printRoleList
    elif [[ ! -z $(jq -r '.roles[] | select(.name == "'$2'" ) | "\(.name)"' $MESOS_LEADER_DIR"/5050-master_roles.json") ]]; then
      ROLE_NAME=$2
      if [[ $# -eq 2 ]]; then
        printRoleSummary
      elif [[ $3 == "agents" ]]; then
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
# Offer
#####

# echo "nonexit"
# jq '.frameworks[] | select(.roles[] == "kubernetes-role") | .tasks[].slave_id' 5050-master_frameworks.json

#### add things
#### fix things
